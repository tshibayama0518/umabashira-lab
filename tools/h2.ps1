param([Parameter(Mandatory)][string]$Path)
# 出走馬の過去2年の戦績（history\<hid>.json）から h2_best（2年内の最高着差）と h2_g1（G1での3着内率）を計算して、レースデータに書き込む。
# 検証（scratchpad\h2feat.ps1）と同じ定義。
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
function N($v){ if($v -eq $null){return $null}; $s="$v".Trim(); $d=0.0; if([double]::TryParse($s,[ref]$d)){return $d}; return $null }
$d = Get-Content -Raw -Encoding UTF8 $Path | ConvertFrom-Json
$rd = [datetime]$d.race.date; $from = $rd.AddDays(-730); $ok = 0
foreach ($h in $d.horses) {
  $b = $null; $g = $null
  $f = Join-Path $root "history\$($h.hid).json"
  if ($h.hid -and (Test-Path $f)) {
    $runs = @((Get-Content -Raw -Encoding UTF8 $f | ConvertFrom-Json).runs | ? {
      $dt = [datetime]$_.date; $fin = N $_.finish
      $dt -lt $rd -and $dt -ge $from -and $_.surface -ne '障' -and $fin -ne $null -and $fin -gt 0 })
    $ms = @($runs | % { N $_.margin } | ? { $_ -ne $null })
    if ($ms.Count) { $b = -[math]::Max(-1.0, [double]($ms | Measure-Object -Minimum).Minimum) }
    $g1 = @($runs | ? { $_.race -match '\(GI\)' })
    if ($g1.Count) { $t = @($g1 | ? { (N $_.finish) -le 3 }).Count; $g = ($t + 0.7) / ($g1.Count + 2) }
    $ok++
  }
  $h | Add-Member -NotePropertyName h2_best -NotePropertyValue $b -Force
  $h | Add-Member -NotePropertyName h2_g1 -NotePropertyValue $g -Force
}
[IO.File]::WriteAllText($Path, ($d | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding $false))
"2年戦績の要素: $ok/$(@($d.horses).Count)頭"
