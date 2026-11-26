# umabashira-lab.html（アプリ本体）から GitHub Pages 用の index.html を作る。アプリを直したら実行する。
$root = Split-Path -Parent $PSScriptRoot
$src = [IO.File]::ReadAllText((Join-Path $root 'umabashira-lab.html'), [Text.Encoding]::UTF8)
$html = '<!doctype html><html lang="ja"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"></head><body>' + "`n" + $src + "`n</body></html>`n"
[IO.File]::WriteAllText((Join-Path $root 'index.html'), $html, (New-Object Text.UTF8Encoding $false))
"index.html を作りました"
