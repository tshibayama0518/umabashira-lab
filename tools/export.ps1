# Writes tracking.json for the app: live results summary + per-race rows + this week's schedule.
$root = Split-Path -Parent $PSScriptRoot
$tdir = Join-Path $root 'tracking'
$enc = New-Object Text.UTF8Encoding $false
$rows = @(); $csv = Join-Path $tdir 'results.csv'
if (Test-Path $csv) { $rows = @(Import-Csv $csv -Encoding UTF8) }
function S($col) { [double](($rows | % { [double]$_.$col } | Measure-Object -Sum).Sum) }
$week = @(); $wf = Join-Path $tdir 'week.json'
$doneIds = @($rows | % { $_.id })
if (Test-Path $wf) { $week = @((Get-Content -Raw -Encoding UTF8 $wf | ConvertFrom-Json) | % { [ordered]@{ id = $_.id; date = $_.date; start = $_.start; name = $_.name; grade = $_.grade; recorded = ($doneIds -contains $_.id) } }) }
$obj = [ordered]@{
  updated = (Get-Date -Format 'yyyy-MM-dd HH:mm')
  races = @($rows | % { [ordered]@{
      id = $_.id; date = $_.date; race = $_.race; going = $_.going; oddsSource = $_.oddsSource; predMade = $_.predMade
      honsei = $_.honsei; honFinish = $_.honFinish; honOdds = $_.honFinalOdds; winner = $_.winner; winnerMark = $_.winnerMark; winnerOdds = $_.winnerFinalOdds
      favFinish = $_.favFinish; favWinPay = [double]$_.favWinPay
      stake = [ordered]@{ win = [double]$_.winStake; quinella = [double]$_.quinStake; wide = [double]$_.wideStake; trio = [double]$_.trioStake; value = [double]$_.valueStake }
      ret = [ordered]@{ win = [double]$_.winReturn; quinella = [double]$_.quinReturn; wide = [double]$_.wideReturn; trio = [double]$_.trioReturn; value = [double]$_.valueReturn } } })
  week = $week
}
[IO.File]::WriteAllText((Join-Path $root 'tracking.json'), ($obj | ConvertTo-Json -Depth 6), $enc)
"tracking.json: 記録 $($rows.Count) レース"
