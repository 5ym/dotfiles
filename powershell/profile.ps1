# Windows PowerShell 5.1 / PowerShell 7 共通のプロファイル。
# init.ps1 が $PROFILE からこのファイルを読むように設定する。

# Starship
$env:STARSHIP_CONFIG = Join-Path $HOME 'dotfiles\starship.toml'
$starship = Get-Command starship -CommandType Application -ErrorAction SilentlyContinue
if ($starship) {
    # init スクリプトを毎回生成すると起動が遅いので、starship.exe が更新されたときだけ作り直す
    $cache = Join-Path $env:LOCALAPPDATA 'starship\init.ps1'
    if (-not (Test-Path $cache) -or
        (Get-Item $starship.Source).LastWriteTime -gt (Get-Item $cache).LastWriteTime) {
        New-Item -ItemType Directory -Force (Split-Path $cache) | Out-Null
        & $starship.Source init powershell --print-full-init | Out-File $cache -Encoding utf8
    }
    . $cache
}
