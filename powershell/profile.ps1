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

# PSReadLine の予測候補は既定だと明るい白を薄く (97;2) 出すので、ライトテーマでは見えない。
# GitHub Light の muted (#6E7781) にする。リストの選択行も既定は暗い背景 (256 色の 238) なので明るい青にする。
# Windows PowerShell 5.1 同梱の PSReadLine 2.0 には予測の色がないので除外。
if ((Get-Module PSReadLine).Version -ge [version]'2.1') {
    $esc = [char]27
    Set-PSReadLineOption -Colors @{
        InlinePrediction       = "$esc[38;2;110;119;129m"
        ListPredictionSelected = "$esc[48;2;221;244;255m"
    }
}
