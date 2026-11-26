param([Parameter(Mandatory)][string]$Path, [switch]$NoSave)
# Same learned model as the app (umabashira-lab.html, LEARNED). Prints a Markdown summary.
$W = [ordered]@{ train = 0.1915; prevpop = 0.0966; margin = -0.1949; combofit = -0.0702; venuefit = -0.0667; heavyfront = 0.2863; bigloss = -0.1557; h2_best = 0.0936; h2_g1 = -0.074 }
$d = Get-Content -Raw -Encoding UTF8 $Path | ConvertFrom-Json
$race = $d.race; $hs = @($d.horses)
function Num($v) { $s = "$v".Trim(); $x = 0.0; if ($s -ne '' -and [double]::TryParse($s, [ref]$x)) { return $x }; return $null }
function Toks($s, $sep) { $t = "$s".Trim(); if ($t -eq '') { return ,@() }; return ,@($t -split $sep | ? { "$_".Trim() -ne '' }) }
function WAvg3($vals) { $w = @(0.5, 0.3, 0.2); $a = 0.0; $t = 0.0; for ($i = 0; $i -lt [math]::Min(3, $vals.Count); $i++) { if ($vals[$i] -ne $null) { $a += $w[$i] * $vals[$i]; $t += $w[$i] } }; if ($t -gt 0) { return $a / $t }; return $null }
function Fit($s) { $t = Toks $s '[,、\s\-・/]+'; if ($t.Count -eq 0) { return $null }; $c = 0; foreach ($x in $t) { $n = Num $x; if ($n -ne $null -and $n -ge 1 -and $n -le 3) { $c++ } }; return ($c + 0.7) / ($t.Count + 2) }
function Raw($k, $h) {
  switch ($k) {
    'h2_best' { return Num $h.h2_best }
    'h2_g1' { return Num $h.h2_g1 }
    'train' { $m = @{ 'A' = 3.0; 'B' = 2.0; 'C' = 1.0; 'D' = 0.0; 'E' = 0.0 }; $r = "$($h.train)".Trim().ToUpper(); if ($m.ContainsKey($r)) { return $m[$r] }; return $null }
    'prevpop' { $t = Toks $h.pop '[,、\s]+'; $v = New-Object 'object[]' $t.Count; for ($i = 0; $i -lt $t.Count; $i++) { $n = Num $t[$i]; $v[$i] = $(if ($n -ne $null -and $n -ge 1) { [math]::Log($n) } else { $null }) }; $a = WAvg3 $v; if ($a -eq $null) { return $null }; return -$a }
    'margin' { $t = Toks $h.margin '[,、\s]+'; $v = New-Object 'object[]' $t.Count; for ($i = 0; $i -lt $t.Count; $i++) { $n = Num $t[$i]; $v[$i] = $(if ($n -ne $null) { [math]::Max([double]-1.0, [math]::Min([double]3.0, [double]$n)) } else { $null }) }; $a = WAvg3 $v; if ($a -eq $null) { return $null }; return -$a }
    'combofit' { return Fit $h.jkfin }
    'venuefit' { return Fit $h.vfin }
    'heavyfront' { if (-not $race.going -or $race.going -eq '良') { return $null }; $t = Toks $h.early '[,、\s]+'; $v = New-Object 'object[]' $t.Count; for ($i = 0; $i -lt $t.Count; $i++) { $x = "$($t[$i])"; if ($x -match '^\s*(\d+)\s*/\s*(\d+)\s*$') { $v[$i] = $(if ([int]$matches[2] -gt 0) { [double]$matches[1] / [double]$matches[2] } else { $null }) } else { $n = Num $x; $v[$i] = $(if ($n -ne $null -and $n -ge 0 -and $n -le 1) { $n } else { $null }) } }; $a = WAvg3 $v; if ($a -eq $null) { return $null }; return -$a }
    'bigloss' { $t = Toks $h.margin '[,、\s]+'; if ($t.Count -eq 0) { return $null }; $n = Num $t[0]; if ($n -eq $null) { return $null }; if ($n -ge 1.0) { return 1.0 }; return 0.0 }
  }
}
function Std($vals) {
  $xs = @(); foreach ($x in $vals) { if ($x -ne $null) { $xs += [double]$x } }
  $out = New-Object 'double[]' $vals.Count
  if ($xs.Count -lt 2) { return ,$out }
  $m = ($xs | Measure-Object -Average).Average; $sd = [math]::Sqrt((($xs | % { ($_ - $m) * ($_ - $m) }) | Measure-Object -Sum).Sum / $xs.Count)
  for ($i = 0; $i -lt $vals.Count; $i++) { if ($vals[$i] -ne $null -and $sd -ge 1e-9) { $out[$i] = [math]::Max([double]-2.5, [math]::Min([double]2.5, ([double]$vals[$i] - $m) / $sd)) } }
  return ,$out
}
$n = $hs.Count
$inv = New-Object 'object[]' $n; for ($i = 0; $i -lt $n; $i++) { $o = Num $hs[$i].odds; $inv[$i] = $(if ($o -ne $null -and $o -ge 1) { 1.0 / $o } else { $null }) }
$known = @($inv | ? { $_ -ne $null }); $fill = $(if ($known.Count) { ($known | Measure-Object -Average).Average } else { 1.0 })
for ($i = 0; $i -lt $n; $i++) { if ($inv[$i] -eq $null) { $inv[$i] = $fill } }
$s = ($inv | Measure-Object -Sum).Sum
$z = @{}; foreach ($k in $W.Keys) { $raw = New-Object 'object[]' $n; for ($i = 0; $i -lt $n; $i++) { $raw[$i] = Raw $k $hs[$i] }; $z[$k] = Std $raw }
$u = New-Object 'double[]' $n
for ($i = 0; $i -lt $n; $i++) { $a = [math]::Log($inv[$i] / $s); foreach ($k in $W.Keys) { $a += $W[$k] * $z[$k][$i] }; $u[$i] = $a }
$mx = ($u | Measure-Object -Maximum).Maximum; $e = @($u | % { [math]::Exp($_ - $mx) }); $sum = ($e | Measure-Object -Sum).Sum
$rows = for ($i = 0; $i -lt $n; $i++) { $o = Num $hs[$i].odds; $p = $e[$i] / $sum; [pscustomobject]@{ num = "$($hs[$i].num)"; name = $hs[$i].name; odds = $o; p = $p; ev = $(if ($o) { $p * $o } else { $null }); train = $hs[$i].train; mark = '' } }
$rk = @($rows | Sort-Object { -$_.p })
$marks = @('◎', '○', '▲', '△', '△'); for ($i = 0; $i -lt [math]::Min(5, $rk.Count); $i++) { $rk[$i].mark = $marks[$i] }
$star = @($rk | Select-Object -Skip 5 | ? { $_.ev -ne $null -and $_.ev -ge 1 -and $_.odds -ge 10 } | Sort-Object { -$_.ev }) | Select-Object -First 1
if ($star) { $star.mark = '☆' }
$lbl = { param($r) if ($r.num) { "$($r.num) $($r.name)" } else { $r.name } }
"## $($race.name)（$($race.date) $($race.venue) $($race.surface)$($race.dist)m 馬場:$($race.going)）"
"更新: $($race.updated) / オッズ: $($race.oddsSource) $($race.oddsTime) / $n 頭"
""
"| 印 | 馬 | 調教 | 単勝 | 予想勝率 | 期待値 |"
"|---|---|---|---|---|---|"
foreach ($r in $rk) { "| {0} | {1} | {2} | {3} | {4:N1}% | {5} |" -f $r.mark, (& $lbl $r), $r.train, $(if ($r.odds) { "{0:N1}倍" -f $r.odds } else { '—' }), (100 * $r.p), $(if ($r.ev -ne $null) { '{0:N2}' -f $r.ev } else { '—' }) }
""
$hon = $rk[0]; $par = @($rk | Select-Object -Skip 1 -First 4); $opp = @($par) + @($star | ? { $_ })
"買い目の目安（各100円）"
"- 単勝: $(& $lbl $hon)"
"- 馬連: $(& $lbl $hon) から " + (($par | % { & $lbl $_ }) -join '・') + "（$($par.Count)点）"
if ($star) { "- ワイド: $(& $lbl $hon) – $(& $lbl $star)" }
"- 3連複: $(& $lbl $hon) 1頭軸、相手 " + (($opp | % { & $lbl $_ }) -join '・') + "（$($opp.Count * ($opp.Count - 1) / 2)点）"
$val = @($rk | ? { $_.ev -ne $null -and $_.ev -ge 1.0 -and $_.odds -le 50 })
"- 妙味単勝（期待値1.0以上）: " + $(if ($val.Count) { ($val | % { "$(& $lbl $_)（$('{0:N2}' -f $_.ev)）" }) -join '・' } else { 'なし' })

# machine-readable copy for the results log (tools\record.ps1)
if (-not $NoSave -and $race.id) {
  $root = Split-Path -Parent $PSScriptRoot
  $dir = Join-Path $root 'predictions'; New-Item -ItemType Directory -Force $dir | Out-Null
  $pairs = { param($a, $list) @($list | % { ,@($a.name, $_.name) }) }
  $wideList = New-Object System.Collections.ArrayList; if ($star) { [void]$wideList.Add(@($hon.name, $star.name)) }
  $trio = @(); for ($i = 0; $i -lt $opp.Count; $i++) { for ($k = $i + 1; $k -lt $opp.Count; $k++) { $trio += ,@($hon.name, $opp[$i].name, $opp[$k].name) } }
  $obj = [ordered]@{
    id = $race.id; name = $race.name; date = $race.date; start = $race.start; going = $race.going; made = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); oddsSource = $race.oddsSource; oddsTime = $race.oddsTime
    horses = @($rk | % { [ordered]@{ name = $_.name; num = $_.num; mark = $_.mark; odds = $_.odds; p = [math]::Round($_.p, 5); ev = $(if ($_.ev -ne $null) { [math]::Round($_.ev, 3) } else { $null }) } })
    bets = [ordered]@{ win = @($hon.name); quinella = @(& $pairs $hon $par); wide = $wideList; trio = $trio; value = @($val | % { $_.name }) }
  }
  [IO.File]::WriteAllText((Join-Path $dir ("{0}_{1}.json" -f $race.id, (Get-Date -Format 'yyyyMMdd-HHmmss'))), ($obj | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding $false))
}
