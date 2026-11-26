param(
  [Parameter(Mandatory)][ValidateSet('plan', 'update', 'record')][string]$Mode,
  [double]$WithinHours = 0,   # update: only races whose post time is within this many hours (0 = all upcoming)
  [int]$Delay = 2
)
# Weekly automation for JRA flat graded races (G1/G2/G3).
#   plan   : find this week's graded races (today .. +5 days), save tracking\week.json, then run update for all
#   update : refresh data + prediction for races that have not started yet; rebuild upcoming.json (all races of the week)
#   record : record results for races that finished and are not recorded yet
$ErrorActionPreference = 'Stop'
$tools = $PSScriptRoot; $root = Split-Path -Parent $tools
$tdir = Join-Path $root 'tracking'; New-Item -ItemType Directory -Force $tdir | Out-Null
$weekFile = Join-Path $tdir 'week.json'
$enc = New-Object Text.UTF8Encoding $false
$wc = New-Object Net.WebClient
function Get-Page($u) { $wc.Headers['User-Agent'] = 'Mozilla/5.0'; $b = $wc.DownloadData($u); Start-Sleep -Seconds $Delay; [Text.Encoding]::UTF8.GetString($b) }
function Strip($s) { (([regex]::Replace("$s", '<[^>]+>', ' ')).Replace('&nbsp;', ' ') -replace '\s+', ' ').Trim() }
function PostTime($r) { [datetime]::ParseExact("$($r.date) $($r.start)", 'yyyy-MM-dd H:mm', $null) }
function Save-Week($w) { [IO.File]::WriteAllText($weekFile, (ConvertTo-Json -InputObject @($w) -Depth 5), $enc) }
function Load-Week { if (Test-Path $weekFile) { return @(Get-Content -Raw -Encoding UTF8 $weekFile | ConvertFrom-Json) }; return @() }

if ($Mode -eq 'plan') {
  $found = @()
  for ($d = 0; $d -le 5; $d++) {
    $day = (Get-Date).Date.AddDays($d); $ds = $day.ToString('yyyyMMdd')
    $h = Get-Page "https://race.netkeiba.com/top/race_list_sub.html?kaisai_date=$ds"
    foreach ($li in [regex]::Matches($h, '(?s)<li class="RaceList_DataItem.*?</li>')) {
      $v = $li.Value; $g = $null
      if ($v -match 'Icon_GradeType1[" ]') { $g = 'G1' } elseif ($v -match 'Icon_GradeType2[" ]') { $g = 'G2' } elseif ($v -match 'Icon_GradeType3[" ]') { $g = 'G3' }
      if (-not $g) { continue }
      $long = Strip ([regex]::Match($v, 'RaceList_ItemLong[^>]*>(.*?)<').Groups[1].Value)
      if ($long -notmatch '^(芝|ダ)\d+m') { continue }   # flat only
      $found += [pscustomobject]@{
        id = [regex]::Match($v, 'race_id=(\d+)').Groups[1].Value; date = $day.ToString('yyyy-MM-dd'); grade = $g
        start = Strip ([regex]::Match($v, 'RaceList_Itemtime">(.*?)<').Groups[1].Value); name = Strip ([regex]::Match($v, 'class="ItemTitle">(.*?)<').Groups[1].Value); course = $long
      }
    }
  }
  $old = Load-Week
  $week = @($old | ? { (PostTime $_) -gt (Get-Date).AddDays(-3) -and -not ($found.id -contains $_.id) }) + @($found)   # keep unrecorded races from the last few days
  Save-Week $week
  "今週の重賞: " + (($found | % { "$($_.date) $($_.start) $($_.name)($($_.grade))" }) -join ' / ')
  if (-not $found.Count) { "見つかりませんでした（出馬表がまだ出ていない可能性があります）" }
  $Mode = 'update'; $WithinHours = 0
}

if ($Mode -eq 'update') {
  $week = Load-Week; $now = Get-Date; $done = @(); $todo = @()
  foreach ($r in $week) {
    $post = PostTime $r
    if ($post -le $now.AddMinutes(5)) { continue }
    if ($WithinHours -gt 0 -and $post -gt $now.AddHours($WithinHours)) { continue }
    $dataDir = Join-Path $tdir 'data'; New-Item -ItemType Directory -Force $dataDir | Out-Null
    $out = Join-Path $dataDir "$($r.id).json"
    try {
      $msg = & (Join-Path $tools 'prepare.ps1') -Id $r.id -Out $out -Delay $Delay
      $todo += [pscustomobject]@{ r = $r; out = $out; msg = "$msg" }
    } catch { $done += "NG $($r.name): $($_.Exception.Message)" }
  }
  # runners' race history for the last 2 years (cached per horse; re-fetched when older than 3 days) -> features h2_* -> prediction
  $ids = @($week | ? { (PostTime $_) -gt $now } | % { $_.id } | ? { Test-Path (Join-Path (Join-Path $tdir 'data') "$_.json") })
  if ($ids.Count) { try { & (Join-Path $tools 'history.ps1') -RaceIds $ids -Delay $Delay } catch { "戦績の取得に失敗: $($_.Exception.Message)" } }
  foreach ($t in $todo) {
    try {
      $h2 = & (Join-Path $tools 'h2.ps1') -Path $t.out
      $md = & (Join-Path $tools 'predict.ps1') -Path $t.out
      [IO.File]::WriteAllText((Join-Path (Join-Path $root 'predictions') ("{0}_{1}.md" -f $t.r.id, (Get-Date -Format 'yyyyMMdd-HHmm'))), ($md -join "`r`n"), $enc)
      $done += "OK $($t.r.name): $($t.msg) / $h2"
    } catch { $done += "NG $($t.r.name): $($_.Exception.Message)" }
  }
  # upcoming.json for the app: every race of the week that has data, soonest first
  $list = @()
  foreach ($r in ($week | Sort-Object { PostTime $_ })) {
    $f = Join-Path (Join-Path $tdir 'data') "$($r.id).json"
    if (Test-Path $f) { $list += (Get-Content -Raw -Encoding UTF8 $f | ConvertFrom-Json) }
  }
  [IO.File]::WriteAllText((Join-Path $root 'upcoming.json'), (ConvertTo-Json -InputObject @($list) -Depth 8), $enc)
  if ($done.Count) { $done } else { "更新対象のレースはありませんでした" }
  "upcoming.json: $($list.Count) レース"
}

if ($Mode -eq 'record') {
  $week = Load-Week; $now = Get-Date
  $csv = Join-Path $tdir 'results.csv'
  $recorded = @(); if (Test-Path $csv) { $recorded = @(Import-Csv $csv -Encoding UTF8 | % { $_.id }) }
  $out = @()
  foreach ($r in $week) {
    if ($recorded -contains $r.id) { continue }
    if ((PostTime $r).AddMinutes(30) -gt $now) { $out += "まだ: $($r.name)"; continue }
    try { $out += & (Join-Path $tools 'record.ps1') -Id $r.id -Delay $Delay } catch { $out += "NG $($r.name): $($_.Exception.Message)" }
  }
  if ($out.Count) { $out } else { "記録対象のレースはありませんでした" }
}

# results + schedule for the app (tracking.json), refreshed on every run
& (Join-Path $tools 'export.ps1')
