param([Parameter(Mandatory)][string[]]$RaceIds, [int]$Years = 2, [int]$MinRuns = 10, [double]$MaxAgeDays = 3, [int]$Delay = 2)
# Fetches each runner's race history (db.netkeiba.com/horse/result/<id>/) and keeps the last $Years years.
# Cache: history\<horse id>.json (re-fetched when older than $MaxAgeDays). Writes history.json for the app: { hid: {name, runs:[...]} }.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$hdir = Join-Path $root 'history'; New-Item -ItemType Directory -Force $hdir | Out-Null
$enc = New-Object Text.UTF8Encoding $false
$wc = New-Object Net.WebClient
function Get-Page($u) { $wc.Headers['User-Agent'] = 'Mozilla/5.0'; $b = $wc.DownloadData($u); Start-Sleep -Seconds $Delay; [Text.Encoding]::UTF8.GetString($b) }
function Strip($s) { (([regex]::Replace("$s", '<[^>]+>', ' ')).Replace('&nbsp;', ' ') -replace '\s+', ' ').Trim() }
$since = (Get-Date).Date.AddYears(-$Years)
$fetched = 0; $cached = 0; $failed = @()
$out = [ordered]@{}
foreach ($rid in $RaceIds) {
  $df = Join-Path (Join-Path $root 'tracking\data') "$rid.json"
  if (-not (Test-Path $df)) { $failed += "$rid（出走データなし）"; continue }
  $race = Get-Content -Raw -Encoding UTF8 $df | ConvertFrom-Json
  foreach ($h in $race.horses) {
    if (-not $h.hid) { continue }
    $cf = Join-Path $hdir "$($h.hid).json"
    $use = $null
    if (Test-Path $cf) { $c = Get-Content -Raw -Encoding UTF8 $cf | ConvertFrom-Json; if (((Get-Date) - [datetime]::ParseExact($c.fetched, 'yyyy-MM-dd HH:mm', $null)).TotalDays -lt $MaxAgeDays) { $use = $c; $cached++ } }
    if (-not $use) {
      try {
        $p = Get-Page "https://db.netkeiba.com/horse/result/$($h.hid)/"
        $t = [regex]::Match($p, '(?s)<table[^>]*db_h_race_results.*?</table>').Value
        $runs = @()
        foreach ($tr in ([regex]::Matches($t, '(?s)<tr[^>]*>.*?</tr>') | Select-Object -Skip 1)) {
          $td = @([regex]::Matches($tr.Value, '(?s)<td[^>]*>(.*?)</td>') | % { Strip $_.Groups[1].Value })
          if ($td.Count -lt 30) { continue }
          $dt = [datetime]::MinValue; if (-not [datetime]::TryParseExact($td[0], 'yyyy/MM/dd', $null, 'None', [ref]$dt)) { continue }
          if ($dt -lt $since -and $runs.Count -ge $MinRuns) { continue }   # 2年より前でも、直近 $MinRuns 走までは残す
          $cm = [regex]::Match($td[14], '^(芝|ダ|障)(\d+)')
          $runs += [ordered]@{
            date = $dt.ToString('yyyy-MM-dd'); venue = ($td[1] -replace '^\d+', '' -replace '\d+$', ''); weather = $td[2]; r = $td[3]; race = $td[4]
            raceId = [regex]::Match($tr.Value, '/race/(\d{12})/').Groups[1].Value
            field = $td[6]; waku = $td[7]; num = $td[8]; odds = $td[9]; pop = $td[10]; finish = $td[11]; jockey = $td[12]; kinryo = $td[13]
            surface = $cm.Groups[1].Value; dist = $cm.Groups[2].Value; going = $td[16]; time = $td[18]; margin = $td[19]
            passing = $td[25]; pace = $td[26]; last3f = $td[27]; body = $td[28]; winner = $td[31]
          }
        }
        $use = [ordered]@{ hid = $h.hid; name = $h.name; fetched = (Get-Date -Format 'yyyy-MM-dd HH:mm'); since = $since.ToString('yyyy-MM-dd'); runs = @($runs) }
        [IO.File]::WriteAllText($cf, ($use | ConvertTo-Json -Depth 5), $enc)
        $fetched++
      } catch { $failed += "$($h.name)（$($_.Exception.Message)）" }
    }
    if ($use) { $out["$($h.hid)"] = [ordered]@{ name = $use.name; fetched = $use.fetched; runs = @($use.runs) } }
  }
}
[IO.File]::WriteAllText((Join-Path $root 'history.json'), ($out | ConvertTo-Json -Depth 6), $enc)
$nr = ($out.Values | % { @($_.runs).Count } | Measure-Object -Sum).Sum
"戦績: $($out.Count)頭（新しく取得 $fetched・保存分を使用 $cached）、過去${Years}年のレース計 $nr 件" + $(if ($failed.Count) { " / 失敗: " + ($failed -join '、') } else { '' })
