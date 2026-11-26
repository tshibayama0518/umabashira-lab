param([string]$MapFile = 'races_hid.json', [int]$Delay = 2)
# 過去レース（races\*.json）の全出走馬の全戦績を取得して history_all\<hid>.json に保存する（取得済みはスキップ＝途中再開可）。
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$dir = Join-Path $root 'history_all'; New-Item -ItemType Directory -Force $dir | Out-Null
$log = Join-Path $root 'histall.log'
$enc = New-Object Text.UTF8Encoding $false
$wc = New-Object Net.WebClient
function Strip($s) { (([regex]::Replace("$s", '<[^>]+>', ' ')).Replace('&nbsp;', ' ') -replace '\s+', ' ').Trim() }
$map = Get-Content -Raw -Encoding UTF8 (Join-Path $root $MapFile) | ConvertFrom-Json
$ids = @($map.PSObject.Properties | % { $_.Value.PSObject.Properties | % { $_.Value } } | Select-Object -Unique)
$i = 0; $ok = 0; $ng = 0
foreach ($hid in $ids) {
  $i++
  $cf = Join-Path $dir "$hid.json"
  if (Test-Path $cf) { continue }
  try {
    $wc.Headers['User-Agent'] = 'Mozilla/5.0'
    $p = [Text.Encoding]::UTF8.GetString($wc.DownloadData("https://db.netkeiba.com/horse/result/$hid/"))
    $t = [regex]::Match($p, '(?s)<table[^>]*db_h_race_results.*?</table>').Value
    $runs = @()
    foreach ($tr in ([regex]::Matches($t, '(?s)<tr[^>]*>.*?</tr>') | Select-Object -Skip 1)) {
      $td = @([regex]::Matches($tr.Value, '(?s)<td[^>]*>(.*?)</td>') | % { Strip $_.Groups[1].Value })
      if ($td.Count -lt 30) { continue }
      $dt = [datetime]::MinValue; if (-not [datetime]::TryParseExact($td[0], 'yyyy/MM/dd', $null, 'None', [ref]$dt)) { continue }
      $cm = [regex]::Match($td[14], '^(芝|ダ|障)(\d+)')
      $runs += [ordered]@{
        date = $dt.ToString('yyyy-MM-dd'); venue = ($td[1] -replace '^\d+', '' -replace '\d+$', ''); race = $td[4]
        raceId = [regex]::Match($tr.Value, '/race/(\d{12})/').Groups[1].Value
        field = $td[6]; num = $td[8]; odds = $td[9]; pop = $td[10]; finish = $td[11]; jockey = $td[12]; kinryo = $td[13]
        surface = $cm.Groups[1].Value; dist = $cm.Groups[2].Value; going = $td[16]; time = $td[18]; margin = $td[19]
        passing = $td[25]; last3f = $td[27]; body = $td[28]
      }
    }
    if (-not $t) { throw 'no table' }
    [IO.File]::WriteAllText($cf, ([ordered]@{ hid = $hid; fetched = (Get-Date -Format 'yyyy-MM-dd HH:mm'); runs = @($runs) } | ConvertTo-Json -Depth 5), $enc)
    $ok++
  } catch { $ng++; Add-Content -Path $log -Value "NG $hid $($_.Exception.Message)" -Encoding utf8 }
  Start-Sleep -Seconds $Delay
  if ($i % 50 -eq 0) { Add-Content -Path $log -Value ("{0} {1}/{2} ok={3} ng={4}" -f (Get-Date -Format 'HH:mm:ss'), $i, $ids.Count, $ok, $ng) -Encoding utf8 }
}
Add-Content -Path $log -Value ("finished {0} ok={1} ng={2}" -f (Get-Date -Format 'HH:mm:ss'), $ok, $ng) -Encoding utf8
"done ok=$ok ng=$ng total=$($ids.Count)"
