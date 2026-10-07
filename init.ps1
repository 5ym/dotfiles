# Windows の開発環境セットアップ。何度実行しても同じ状態になる。
# Windows PowerShell 5.1 / PowerShell 7 のどちらからでも実行できる。
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$dotfiles = Join-Path $HOME 'dotfiles'

function Update-SessionPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

# zip をダウンロードして sha256 を照合し、展開したディレクトリを返す
function Expand-VerifiedZip($url, $sha256) {
    $zip = Join-Path $env:TEMP (Split-Path $url -Leaf)
    $dir = "$zip.d"
    Invoke-WebRequest -UseBasicParsing -OutFile $zip $url
    if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $sha256) { throw "sha256 mismatch: $url" }
    Expand-Archive $zip $dir -Force
    Remove-Item $zip
    $dir
}

# パッケージ
foreach ($id in 'Git.Git', 'GitHub.cli', 'Microsoft.PowerShell', 'Starship.Starship', 'Microsoft.VisualStudioCode', 'danything.wslc-compose') {
    winget list --id $id --exact --accept-source-agreements | Out-Null
    if ($LASTEXITCODE -ne 0) {
        winget install --id $id --exact --source winget --silent --accept-package-agreements --accept-source-agreements
    }
}

# forgejo-cli (fj)。winget にないので Codeberg のリリースを入れる (署名がないので Smart App Control はオフにしておく)
$fjVersion = '0.6.0'
$fjDir = Join-Path $env:LOCALAPPDATA 'Programs\fj'
if (-not ((Test-Path "$fjDir\fj.exe") -and ((& "$fjDir\fj.exe" version 2>$null) -match "v$fjVersion\b"))) {
    $d = Expand-VerifiedZip "https://codeberg.org/forgejo-contrib/forgejo-cli/releases/download/v$fjVersion/forgejo-cli-x86_64-windows.zip" `
        '9ec20aff62da33afe5a46b6fd63c572dc371d8434b576c35e1fc5204c6652643'
    New-Item -ItemType Directory -Force $fjDir | Out-Null
    Move-Item "$d\fj.exe" $fjDir -Force
    Remove-Item $d -Recurse
}
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($userPath -split ';') -notcontains $fjDir) {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$fjDir", 'User')
}
Update-SessionPath

# リポジトリと Git
if (-not (Test-Path "$dotfiles\.git")) { gh repo clone 5ym/dotfiles $dotfiles }
gh auth setup-git
git config --global include.path '~/dotfiles/.gitconfig'

# SSH。Include は先頭にないと効かない
$sshDir = Join-Path $HOME '.ssh'
$sshConfig = Join-Path $sshDir 'config'
$include = 'Include ~/dotfiles/.ssh/config'
New-Item -ItemType Directory -Force $sshDir | Out-Null
$rest = if (Test-Path $sshConfig) { @(Get-Content $sshConfig) } else { @() }
if ($rest -notcontains $include) { @($include) + $rest | Set-Content $sshConfig -Encoding ascii }

# Dev Drive。作成には管理者権限が要るので、ないときだけ UAC を出す。
# 5.1 は BOM なし UTF-8 のスクリプトを Shift_JIS として読むので pwsh で実行する
$pwsh = (Get-Command pwsh).Source
if (-not (Test-Path 'C:\DevDrive\DevDrive.vhdx')) {
    $p = Start-Process $pwsh -Verb RunAs -Wait -PassThru `
        -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$dotfiles\devdrive.ps1`""
    if ($p.ExitCode -ne 0) { throw "devdrive.ps1 が失敗した ($($p.ExitCode))" }
}
$dev = (Get-Volume -FileSystemLabel DevDrive).DriveLetter

# danything/gitops。infisical などの運用のコマンドは、手元に入れずに gitops の tools (wslc のコンテナ) で動かす
$gitops = "${dev}:\danything\gitops"
if (-not (Test-Path "$gitops\.git")) { gh repo clone danything/gitops $gitops }
$tools = "-NoProfile -ExecutionPolicy Bypass -File `"$gitops\tools\t.ps1`""

# シークレットは Infisical から取り出してファイルに書き出す (普段の git / ssh は Infisical なしで動く)。
# 未ログインだと export がログインの入力を待つので、標準入力を閉じてすぐ失敗させる (出力はメモリで受け取る)
function Export-Secrets {
    $psi = New-Object Diagnostics.ProcessStartInfo $pwsh, ("$tools infisical export --domain https://il.doany.io/api " +
        '--projectId b3ee533f-5b9e-4fdf-8c44-109926b78f20 --env prod --path /dotfiles --silent --format json')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $p = [Diagnostics.Process]::Start($psi)
    $p.StandardInput.Close()
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    if ($p.ExitCode -eq 0) { $out }
}
$exported = Export-Secrets
if (-not $exported) {
    # ブラウザのログインはコンテナに戻ってこられないので、ブラウザに出るトークンを貼り付ける
    & $pwsh -NoProfile -ExecutionPolicy Bypass -File "$gitops\tools\t.ps1" infisical login --domain https://il.doany.io/api
    $exported = Export-Secrets
    if (-not $exported) { throw 'infisical: シークレットを取得できない' }
}
$secrets = @{}
foreach ($s in ($exported | Out-String | ConvertFrom-Json)) { $secrets[$s.key] = $s.value }
foreach ($e in @{ SSH_MAIN_PEM = "$sshDir\main.pem"; GIT_CREDENTIALS = "$HOME\.git-credentials" }.GetEnumerator()) {
    if (-not $secrets[$e.Key]) { throw "infisical: $($e.Key) がない" }
    if (Test-Path $e.Value) { icacls $e.Value /grant:r "${env:USERNAME}:(F)" | Out-Null }
    [IO.File]::WriteAllText($e.Value, ($secrets[$e.Key].TrimEnd() -replace "`r`n", "`n") + "`n")
    # 本人だけ読める (chmod 600 相当)。Windows の OpenSSH はこうしないと鍵を拒否する
    icacls $e.Value /inheritance:r /grant:r "${env:USERNAME}:(R,W)" | Out-Null
}
Remove-Variable exported, secrets

# PowerShell プロファイル。5.1 と 7 の両方から dotfiles のものを読む
$loader = '. (Join-Path $HOME ''dotfiles\powershell\profile.ps1'')'
foreach ($dir in 'WindowsPowerShell', 'PowerShell') {
    $p = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "$dir\Microsoft.PowerShell_profile.ps1"
    New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null
    if ((Test-Path $p) -and (Get-Content $p -Raw) -notmatch [regex]::Escape($loader)) { Copy-Item $p "$p.bak" -Force }
    Set-Content $p $loader -Encoding ascii
}
# 既定の Restricted ではプロファイルを読めない。上位のスコープに設定があると警告のエラーになるので続ける
if ((Get-ExecutionPolicy -Scope CurrentUser) -in 'Undefined', 'Restricted') {
    try { Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force } catch { Write-Warning $_ }
}

# フォント (FiraCode Nerd Font) をユーザー単位で入れる
$fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
if (-not (Test-Path "$fontDir\FiraCodeNerdFontMono-Regular.ttf")) {
    $d = Expand-VerifiedZip 'https://github.com/ryanoasis/nerd-fonts/releases/download/v3.5.1/FiraCode.zip' `
        '239395baf60c89b2eaf4862b6b09db0ef95605cd3e8eef51c00345822a81a665'
    New-Item -ItemType Directory -Force $fontDir | Out-Null
    Add-Type -AssemblyName System.Drawing
    foreach ($ttf in Get-ChildItem $d -Filter *.ttf) {
        $dest = Join-Path $fontDir $ttf.Name
        Copy-Item $ttf.FullName $dest -Force
        $fc = New-Object System.Drawing.Text.PrivateFontCollection
        $fc.AddFontFile($dest)
        # Light などはファミリー名にウェイトが入っているので、Bold / Regular だけ付け足す
        $style = ($ttf.BaseName -split '-')[-1]
        $name = $fc.Families[0].Name + $(if ($style -in 'Bold', 'Regular') { " $style" })
        New-ItemProperty 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts' -Name "$name (TrueType)" -Value $dest -Force | Out-Null
        $fc.Dispose()
    }
    Remove-Item $d -Recurse
}

# Windows Terminal。settings.json は UI も書き込むので、terminal/settings.json の項目だけ上書きする
$wt = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
if (Test-Path $wt) {
    function Merge-Json($base, $overlay) {
        foreach ($p in $overlay.PSObject.Properties) {
            $cur = $base.PSObject.Properties[$p.Name]
            if ($cur -and $cur.Value -is [pscustomobject] -and $p.Value -is [pscustomobject]) { Merge-Json $cur.Value $p.Value }
            else { $base | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force }
        }
    }
    $settings = Get-Content $wt -Raw -Encoding UTF8 | ConvertFrom-Json
    Merge-Json $settings (Get-Content "$dotfiles\terminal\settings.json" -Raw -Encoding UTF8 | ConvertFrom-Json)
    Copy-Item $wt "$wt.bak" -Force
    # WriteAllText は BOM なし UTF-8 (5.1 の Set-Content -Encoding utf8 は BOM を付ける)
    [IO.File]::WriteAllText($wt, ($settings | ConvertTo-Json -Depth 32))
}

Write-Host 'done. 新しいターミナルを開くと反映される'
