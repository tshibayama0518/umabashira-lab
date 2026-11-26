param([Parameter(Mandatory)][string]$Id, [string]$Out, [string]$Going = '', [int]$Delay = 2)
# Builds an app-importable JSON (race + horses) for an upcoming JRA race from netkeiba pages.
$ErrorActionPreference = 'Stop'
$venues = @{ '01'='札幌'; '02'='函館'; '03'='福島'; '04'='新潟'; '05'='東京'; '06'='中山'; '07'='中京'; '08'='京都'; '09'='阪神'; '10'='小倉' }
$wc = New-Object Net.WebClient
function Get-Page($u) { $wc.Headers['User-Agent'] = 'Mozilla/5.0'; $b = $wc.DownloadData($u); Start-Sleep -Seconds $Delay; [Text.Encoding]::UTF8.GetString($b) }
function Strip($s) { (([regex]::Replace("$s", '<[^>]+>', ' ')).Replace('&nbsp;', ' ') -replace '\s+', ' ').Trim() }
function Lv($d2) {
  $m = [regex]::Match($d2, 'Icon_GradeType(\d+)')
  if ($m.Success) { switch ([int]$m.Groups[1].Value) { 1 {return 'G1'} 2 {return 'G2'} 3 {return 'G3'} 5 {return 'OP'} 15 {return 'OP'} 16 {return '3勝'} 17 {return '2勝'} 18 {return '1勝'} } }
  $t = Strip $d2
  if ($t -match '未勝利|新馬') { return '未勝利' }; if ($t -match '1勝|500万') { return '1勝' }; if ($t -match '2勝|1000万') { return '2勝' }; if ($t -match '3勝|1600万') { return '3勝' }; if ($t -match 'OP|オープン|\(L\)') { return 'OP' }
  return '?'
}
function Same($a, $b) { $a -and $b -and $a -ne 'x' -and $b -ne 'x' -and ($a.StartsWith($b) -or $b.StartsWith($a)) }

# 1. entry list
$sh = Get-Page "https://race.netkeiba.com/race/shutuba.html?race_id=$Id"
$raceName = Strip ([regex]::Match($sh, '(?s)<h1 class="RaceName">(.*?)</h1>').Groups[1].Value)
$rd = Strip ([regex]::Match($sh, '(?s)<div class="RaceData01">(.*?)</div>').Groups[1].Value)
$cm = [regex]::Match($rd, '(芝|ダ)(\d+)m'); $surf = $(if ($cm.Groups[1].Value -eq '芝') { '芝' } else { 'ダート' }); $dist = $cm.Groups[2].Value
$gm = [regex]::Match($rd, '/\s*(?:馬場\s*:\s*)?(稍重|不良|稍|不|良|重)\s*(/|$)')
$going = $(if ($Going) { $Going } elseif ($gm.Success) { @{ '稍'='稍重'; '不'='不良' }[$gm.Groups[1].Value] } else { '良' }); if (-not $going) { $going = $gm.Groups[1].Value }
$venue = $venues[$Id.Substring(4, 2)]
$entries = @()
foreach ($r in ([regex]::Split($sh, '(?=<tr class="HorseList)') | ? { $_ -match '^<tr class="HorseList' -and $_ -match 'class="HorseName"' })) {
  $idx = [regex]::Match($r, 'id="odds-1_(\d+)"').Groups[1].Value
  $uma = Strip ([regex]::Match($r, '(?s)<td class="Umaban\d*[^"]*"[^>]*>(.*?)</td>').Groups[1].Value)
  $name = Strip ([regex]::Match($r, '(?s)class="HorseName">.*?<a[^>]*>(.*?)</a>').Groups[1].Value)
  $jk = Strip ([regex]::Match($r, '(?s)<td class="Jockey">(.*?)</td>').Groups[1].Value)
  $kin = ([regex]::Matches($r, '(?s)<td class="Txt_C">\s*([\d.]+)\s*</td>') | % { $_.Groups[1].Value } | Select-Object -First 1)
  $cancel = ($r -match '^<tr class="HorseList[^"]*Cancel') -or ((Strip ([regex]::Match($r, '(?s)<td class="Weight">(.*?)</td>').Groups[1].Value)) -match '取消|除外')
  $hid = [regex]::Match($r, 'db\.netkeiba\.com/horse/(\d+)').Groups[1].Value
  $entries += [pscustomobject]@{ hid = $hid; idx = [int]$idx; uma = $uma; name = $name; jockey = $jk; kinryo = ("$kin" -replace '\.0$', ''); cancel = $cancel }
}
# 2. odds (real odds once on sale, otherwise netkeiba's predicted odds)
$oj = Get-Page "https://race.netkeiba.com/api/api_get_jra_odds.html?race_id=$Id&type=1&action=update" | ConvertFrom-Json
$oddsStatus = $oj.status
$odds = @{}; if ($oj.data.odds.'1') { foreach ($p in $oj.data.odds.'1'.PSObject.Properties) { $odds[[int]$p.Name] = $p.Value[0] } }
# place odds (only once betting is open; predicted odds have no place odds)
$place = @{}
if ($oddsStatus -ne 'yoso') {
  try {
    $pj = Get-Page "https://race.netkeiba.com/api/api_get_jra_odds.html?race_id=$Id&type=2&action=update" | ConvertFrom-Json
    if ($pj.data.odds.'2') { foreach ($p in $pj.data.odds.'2'.PSObject.Properties) { $place[[int]$p.Name] = @($p.Value[0], $p.Value[1]) } }
  } catch { }
}
# odds snapshot log (one file per run) for tracking how the odds move
$root = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $root 'odds_log'; New-Item -ItemType Directory -Force $logDir | Out-Null
$snap = [ordered]@{ id = $Id; taken = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); status = $oddsStatus; official = "$($oj.data.official_datetime)"
  horses = @($entries | % { [ordered]@{ name = $_.name; num = $_.uma; cancel = [bool]$_.cancel; win = "$($odds[$_.idx])"; placeMin = $(if ($place[$_.idx]) { $place[$_.idx][0] } else { '' }); placeMax = $(if ($place[$_.idx]) { $place[$_.idx][1] } else { '' }) } }) }
[IO.File]::WriteAllText((Join-Path $logDir ("{0}_{1}.json" -f $Id, (Get-Date -Format 'yyyyMMdd-HHmmss'))), ($snap | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
# 3. past runs
$past = Get-Page "https://race.netkeiba.com/race/shutuba_past.html?race_id=$Id"
$info = @{}
foreach ($r in ([regex]::Split($past, '(?=<tr class="HorseList")') | ? { $_ -match 'Horse02' })) {
  $name = [regex]::Match($r, 'db\.netkeiba\.com/horse/(\d+)').Groups[1].Value
  $h6 = Strip ([regex]::Match($r, '(?s)<div class="Horse06[^"]*">(.*?)</div>').Groups[1].Value)
  $rest = $(if ($h6 -match '中(\d+)週') { $matches[1] } elseif ($h6 -match '連闘') { '0' } else { '' })
  $jtd = [regex]::Match($r, '(?s)<td class="Jockey">(.*?)</td>').Groups[1].Value
  $jfull = Strip ([regex]::Match($jtd, '(?s)<a [^>]*jockey[^>]*>(.*?)</a>').Groups[1].Value)
  $runs = @()
  foreach ($c in ([regex]::Split($r, '(?=<td class="Past[ "])') | ? { $_ -match 'Data_Item' } | Select-Object -First 5)) {
    $d1 = Strip ([regex]::Match($c, '(?s)<div class="Data01">(.*?)</div>').Groups[1].Value)
    $d3 = Strip ([regex]::Match($c, '(?s)<div class="Data03">(.*?)</div>').Groups[1].Value)
    $d5 = Strip ([regex]::Match($c, '(?s)<div class="Data05">(.*?)</div>').Groups[1].Value)
    $d6 = Strip ([regex]::Match($c, '(?s)<div class="Data06">(.*?)</div>').Groups[1].Value)
    $d7 = Strip ([regex]::Match($c, '(?s)<div class="Data07">(.*?)</div>').Groups[1].Value)
    $fin = Strip ([regex]::Match($c, '(?s)<span class="Num">(.*?)</span>').Groups[1].Value)
    $fs = [regex]::Match($d3, '(\d+)頭').Groups[1].Value; $pos = [regex]::Match($d6, '^(\d+)').Groups[1].Value
    $runs += [pscustomobject]@{
      fin = $(if ($fin -match '^\d+$') { $fin } else { 'x' }); venue = $(if ($d1 -match '^\d{4}\.\d{2}\.\d{2}\s+(\S+)') { $matches[1] -replace '\d+$', '' } else { 'x' })
      cls = Lv ([regex]::Match($c, '(?s)<div class="Data02">(.*?)</div>').Groups[1].Value)
      surf = [regex]::Match($d5, '^(芝|ダ)').Groups[1].Value; dist = [regex]::Match($d5, '^\S(\d+)').Groups[1].Value
      pop = $(if ($d3 -match '(\d+)人') { $matches[1] } else { 'x' }); jk = $(if ($d3 -match '\d+人\s+(\S+)') { $matches[1] } else { 'x' })
      l3 = [regex]::Match($d6, '\((\d+\.\d)\)').Groups[1].Value; margin = $(if ($d7 -match '\((-?\d+(\.\d+)?)\)') { $matches[1] } else { 'x' })
      early = $(if ($fs -and $pos -and [int]$fs -gt 0) { "$pos/$fs" } else { 'x' })
    }
  }
  $info[$name] = [pscustomobject]@{ rest = $rest; jfull = $jfull; runs = $runs }
}
# 4. training evaluation
$oik = Get-Page "https://race.netkeiba.com/race/oikiri.html?race_id=$Id"
$train = @{}
foreach ($m in [regex]::Matches($oik, '(?s)<tr class\s*=\s*"OikiriDataHead\d+ HorseList".*?</tr>')) {
  $n = [regex]::Match($m.Value, 'db\.netkeiba\.com/horse/(\d+)').Groups[1].Value
  $train[$n] = [regex]::Match($m.Value, 'class="Rank_[^"]*">\s*([A-E])\s*<').Groups[1].Value
}
# 5. assemble
$s0 = $(if ($surf -eq '芝') { '芝' } else { 'ダ' })
$horses = foreach ($e in ($entries | ? { -not $_.cancel } | Sort-Object { if ($_.uma -match '^\d+$') { [int]$_.uma } else { 100 + $_.idx } })) {
  $x = $info[$e.hid]; $runs = $(if ($x) { @($x.runs) } else { @() })
  $first3 = @($runs | Select-Object -First 3)
  $apt = @(0, 0, 0, 0)
  foreach ($r in $runs) { if ($r.surf -eq $s0 -and $r.dist -and [math]::Abs([int]$r.dist - [int]$dist) -le 200) { switch ($r.fin) { '1' { $apt[0]++ } '2' { $apt[1]++ } '3' { $apt[2]++ } default { $apt[3]++ } } } }
  $cur = $(if ($x -and $x.jfull) { $x.jfull } else { $e.jockey })
  [ordered]@{
    num = $(if ($e.uma -match '^\d+$') { $e.uma } else { '' }); name = $e.name; hid = $e.hid; jockey = $e.jockey; jwin = ''; kinryo = $e.kinryo
    odds = "$($odds[$e.idx])"; recent = (($first3 | % { if ($_.fin -eq 'x') { '18' } else { $_.fin } }) -join '-')
    last3f = $(if ($runs.Count) { $runs[0].l3 } else { '' }); apt = ($apt -join '-'); body = ''
    cls = (($first3 | % { $_.cls }) -join ','); margin = (($first3 | % { $_.margin }) -join ','); pop = (($first3 | % { $_.pop }) -join ','); rest = $(if ($x) { $x.rest } else { '' })
    train = "$($train[$e.hid])"
    jkfin = (($runs | ? { Same $_.jk $cur } | % { $_.fin }) -join ','); vfin = (($runs | ? { $_.venue -eq $venue } | % { $_.fin }) -join ',')
    early = (($first3 | % { $_.early }) -join ','); finish = ''
  }
}
$dm = [regex]::Match($sh, '<title>[^<]*?(\d{4})年(\d{1,2})月(\d{1,2})日')
$rdate = $(if ($dm.Success) { '{0}-{1:D2}-{2:D2}' -f $dm.Groups[1].Value, [int]$dm.Groups[2].Value, [int]$dm.Groups[3].Value } else { '' })
$oddsLabel = @{ 'yoso' = 'netkeibaの予想オッズ'; 'middle' = '発売中のオッズ'; 'result' = '確定オッズ' }[$oddsStatus]; if (-not $oddsLabel) { $oddsLabel = "$oddsStatus" }
$start = [regex]::Match($rd, '(\d{1,2}:\d{2})発走').Groups[1].Value
$obj = [ordered]@{ race = [ordered]@{ id = $Id; start = $start; name = $raceName; venue = $venue; surface = $surf; dist = $dist; going = $going; date = $rdate; updated = (Get-Date -Format 'yyyy-MM-dd HH:mm'); oddsSource = $oddsLabel; oddsTime = "$($oj.data.official_datetime)" }; horses = @($horses) }
$json = $obj | ConvertTo-Json -Depth 6
if ($Out) { [IO.File]::WriteAllText($Out, $json, (New-Object Text.UTF8Encoding $false)) }
"race: $raceName $venue $surf$dist $going / odds: $oddsStatus / entries: $(@($horses).Count) / 馬番あり: $(@($horses | ? { $_.num }).Count) / 調教評価あり: $(@($horses | ? { $_.train }).Count) / 馬柱あり: $(@($horses | ? { $_.recent }).Count)"
