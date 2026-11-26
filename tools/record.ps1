param([Parameter(Mandatory)][string]$Id, [int]$Delay = 2)
# After a race: fetch result + payouts, compare with the last saved prediction, log results and odds movement.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$enc = New-Object Text.UTF8Encoding $false
$wc = New-Object Net.WebClient
function Get-Page($u) { $wc.Headers['User-Agent'] = 'Mozilla/5.0'; $b = $wc.DownloadData($u); Start-Sleep -Seconds $Delay; [Text.Encoding]::UTF8.GetString($b) }
function Strip($s) { (([regex]::Replace("$s", '<[^>]+>', ' ')).Replace('&nbsp;', ' ') -replace '\s+', ' ').Trim() }
function Num($v) { $s = "$v".Trim(); $x = 0.0; if ($s -ne '' -and [double]::TryParse($s, [ref]$x)) { return $x }; return $null }

# 1. prediction to grade: the newest saved one
# only predictions made before post time count (a late run after the race must not be graded)
$pred = $null
foreach ($f in (Get-ChildItem (Join-Path $root 'predictions') -Filter "${Id}_*.json" -ErrorAction SilentlyContinue | Sort-Object Name -Descending)) {
  $c = Get-Content -Raw -Encoding UTF8 $f.FullName | ConvertFrom-Json
  if ($c.date -and $c.start) { $post = [datetime]::ParseExact("$($c.date) $($c.start)", 'yyyy-MM-dd H:mm', $null); if ([datetime]::ParseExact($c.made, 'yyyy-MM-dd HH:mm:ss', $null) -ge $post) { continue } }
  $pred = $c; break
}
if (-not $pred) { throw "発走前に作った予想ファイルがありません: predictions\${Id}_*.json" }

# 2. result page
$res = Get-Page "https://race.netkeiba.com/race/result.html?race_id=$Id"
$tbl = [regex]::Match($res, '(?s)<table[^>]*class="[^"]*RaceTable01[^"]*".*?</table>').Value
$fin = @{}; $numOf = @{}; $final = @{}
foreach ($r in ([regex]::Split($tbl, '(?=<tr[^>]*HorseList)') | ? { $_ -match '<td class="Result_Num"' })) {
  $rank = Strip ([regex]::Match($r, '(?s)<td class="Result_Num">(.*?)</td>').Groups[1].Value)
  $nums = [regex]::Matches($r, '(?s)<td class="Num[^"]*">\s*<div>(.*?)</div>')
  $num = Strip $nums[1].Groups[1].Value
  $nm = Strip ([regex]::Match($r, 'class="HorseNameSpan">(.*?)</span>').Groups[1].Value)
  $od = Strip ([regex]::Match($r, '(?s)class="Odds Txt_R">\s*<span[^>]*>(.*?)</span>').Groups[1].Value)
  $fin[$nm] = $rank; $numOf[$nm] = $num; $final[$nm] = $od
}
if (-not $fin.Count) { throw "結果がまだ出ていないか、読み取れませんでした" }
$pt = [regex]::Match($res, '(?s)<div class="ResultPayBack.*?ResultPayBackRightWrap').Value
$P = @{}
foreach ($k in @{ Tansho = 'win'; Fukusho = 'place'; Umaren = 'quinella'; Wide = 'wide'; Fuku3 = 'trio' }.GetEnumerator()) {
  $m = [regex]::Match($pt, "(?s)<tr class=""$($k.Key)"">(.*?)</tr>"); if (-not $m.Success) { continue }
  $row = $m.Groups[1].Value
  $resTd = [regex]::Match($row, '(?s)<td class="Result">(.*?)</td>').Groups[1].Value
  $pays = @(([regex]::Match($row, '(?s)<td class="Payout"><span>(.*?)</span>').Groups[1].Value -split '<br\s*/?>') | % { [int](($_ -replace '[^\d]', '')) })
  $tab = @{}
  if ($k.Key -eq 'Tansho' -or $k.Key -eq 'Fukusho') { $n = @([regex]::Matches($resTd, '<span>(\d+)</span>') | % { $_.Groups[1].Value }); for ($i = 0; $i -lt $n.Count; $i++) { $tab[$n[$i]] = $pays[$i] } }
  else { $i = 0; foreach ($g in ([regex]::Split($resTd, '<ul>') | ? { $_ -match '<li>' })) { $n = @([regex]::Matches($g, '<span>(\d+)</span>') | % { $_.Groups[1].Value } | Sort-Object { [int]$_ }); $tab[($n -join '-')] = $pays[$i]; $i++ } }
  $P[$k.Value] = $tab
}
function Pay($type, $names) { $ns = @($names | % { $numOf[$_] }); if ($ns -contains $null -or $ns -contains '') { return 0 }; $key = (@($ns | Sort-Object { [int]$_ }) -join '-'); $v = $P[$type][$key]; if ($v) { return [int]$v }; return 0 }

# 3. grade the prediction
$hon = $pred.horses[0].name
$b = $pred.bets
$calc = [ordered]@{}
foreach ($t in 'win', 'quinella', 'wide', 'trio') {
  $combos = @($b.$t); if ($t -eq 'win') { $combos = @(, @($b.win)) }
  $stake = 0; $ret = 0
  foreach ($c in $combos) { $names = @(@($c) | ? { $_ -is [string] -and $_ -ne '' }); $need = @{ win = 1; quinella = 2; wide = 2; trio = 3 }[$t]; if ($names.Count -ne $need) { continue }; $stake += 100; $ret += Pay $t $names }
  $calc[$t] = @($stake, $ret)
}
$vs = 0; $vr = 0; foreach ($nm in @($b.value)) { if ($nm) { $vs += 100; $vr += Pay 'win' @($nm) } }
$calc['value'] = @($vs, $vr)
$fav = ($pred.horses | ? { $_.odds } | Sort-Object { [double]$_.odds } | Select-Object -First 1).name
$winner = ($fin.GetEnumerator() | ? { $_.Value -eq '1' } | Select-Object -First 1).Key
$row = [ordered]@{
  id = $Id; date = $pred.date; race = $pred.name; going = $pred.going; predMade = $pred.made; oddsSource = $pred.oddsSource
  honsei = $hon; honFinish = $fin[$hon]; honOddsAtPred = $pred.horses[0].odds; honFinalOdds = $final[$hon]; honP = $pred.horses[0].p
  winner = $winner; winnerMark = (($pred.horses | ? { $_.name -eq $winner }).mark); winnerFinalOdds = $final[$winner]
  favAtPred = $fav; favFinish = $fin[$fav]
  winStake = $calc.win[0]; winReturn = $calc.win[1]; quinStake = $calc.quinella[0]; quinReturn = $calc.quinella[1]
  wideStake = $calc.wide[0]; wideReturn = $calc.wide[1]; trioStake = $calc.trio[0]; trioReturn = $calc.trio[1]
  valueStake = $calc.value[0]; valueReturn = $calc.value[1]; favWinPay = $(if ($fin[$fav] -eq '1') { $P.win[$numOf[$fav]] } else { 0 })
}
$tdir = Join-Path $root 'tracking'; New-Item -ItemType Directory -Force $tdir | Out-Null
$csv = Join-Path $tdir 'results.csv'
$all = @(); if (Test-Path $csv) { $all = @(Import-Csv $csv -Encoding UTF8 | ? { $_.id -ne $Id }) }
$all += [pscustomobject]$row
$all | Sort-Object date, id | Export-Csv $csv -NoTypeInformation -Encoding UTF8

# 4. odds movement from snapshots
$snaps = @(Get-ChildItem (Join-Path $root 'odds_log') -Filter "${Id}_*.json" -ErrorAction SilentlyContinue | Sort-Object Name | % { Get-Content -Raw -Encoding UTF8 $_.FullName | ConvertFrom-Json })
$mv = @()
foreach ($nm in $fin.Keys) {
  $series = @($snaps | % { $s = $_; $h = $s.horses | ? { $_.name -eq $nm } | Select-Object -First 1; if ($h -and (Num $h.win)) { "$($s.status)@$($s.taken.Substring(5,11))=$($h.win)" } })
  $firstReal = $snaps | ? { $_.status -ne 'yoso' } | Select-Object -First 1
  $fr = $(if ($firstReal) { Num (($firstReal.horses | ? { $_.name -eq $nm } | Select-Object -First 1).win) } else { $null })
  $fo = Num $final[$nm]
  $mv += [pscustomobject][ordered]@{ id = $Id; date = $pred.date; race = $pred.name; horse = $nm; num = $numOf[$nm]; finish = $fin[$nm]; firstOdds = $fr; finalOdds = $fo; ratio = $(if ($fr -and $fo) { [math]::Round($fo / $fr, 3) } else { $null }); series = ($series -join ' ') }
}
$mcsv = Join-Path $tdir 'odds_moves.csv'
$mall = @(); if (Test-Path $mcsv) { $mall = @(Import-Csv $mcsv -Encoding UTF8 | ? { $_.id -ne $Id }) }
$mall += $mv
$mall | Export-Csv $mcsv -NoTypeInformation -Encoding UTF8

# 5. summary
$R = @(Import-Csv $csv -Encoding UTF8)
function S($col) { ($R | % { [double]$_.$col } | Measure-Object -Sum).Sum }
function Pct($a, $b) { if ($b) { '{0:N1}%' -f (100 * $a / $b) } else { '—' } }
$n = $R.Count
$hw = @($R | ? { $_.honFinish -eq '1' }).Count; $h3 = @($R | ? { $_.honFinish -match '^[123]$' }).Count
$fw = @($R | ? { $_.favFinish -eq '1' }).Count
$md = @(
  "# 実戦成績（馬柱ラボ）", "", "更新: $(Get-Date -Format 'yyyy-MM-dd HH:mm') / 記録したレース: $n", "",
  "| 項目 | 成績 |", "|---|---|",
  "| ◎の勝率 | $(Pct $hw $n)（$hw 勝） |", "| ◎の3着以内率 | $(Pct $h3 $n) |", "| 1番人気の勝率（参考） | $(Pct $fw $n) |",
  "| 単勝（◎）回収率 | $(Pct (S 'winReturn') (S 'winStake')) |", "| 馬連 回収率 | $(Pct (S 'quinReturn') (S 'quinStake')) |",
  "| ワイド 回収率 | $(Pct (S 'wideReturn') (S 'wideStake')) |", "| 3連複 回収率 | $(Pct (S 'trioReturn') (S 'trioStake')) |",
  "| 妙味単勝 回収率 | $(Pct (S 'valueReturn') (S 'valueStake'))（$((S 'valueStake')/100) 点） |", "| 1番人気の単勝回収率（参考） | $(Pct (S 'favWinPay') ($n * 100)) |", "",
  "## レースごと", "", "| 日付 | レース | ◎（着順） | 勝ち馬（印・確定オッズ） | 収支 |", "|---|---|---|---|---|"
) + @($R | % { $st = [double]$_.winStake + [double]$_.quinStake + [double]$_.wideStake + [double]$_.trioStake + [double]$_.valueStake; $rt = [double]$_.winReturn + [double]$_.quinReturn + [double]$_.wideReturn + [double]$_.trioReturn + [double]$_.valueReturn; "| $($_.date) | $($_.race) | $($_.honsei)（$($_.honFinish)着） | $($_.winner)（$(if ($_.winnerMark) { $_.winnerMark } else { '無印' })・$($_.winnerFinalOdds)倍） | $('{0:+#,0;-#,0;0}' -f ($rt - $st))円 |" })
[IO.File]::WriteAllText((Join-Path $tdir 'summary.md'), ($md -join "`r`n"), $enc)
"記録しました: $($pred.name) ◎$hon $($fin[$hon])着 / 勝ち馬 $winner / オッズの記録 $($snaps.Count) 回分"
