# Windows の開発環境セットアップ。何度実行しても同じ状態になる。
# Windows PowerShell 5.1 / PowerShell 7 のどちらからでも実行できる。
$ErrorActionPreference = 'Stop'

$dotfiles = Join-Path $HOME 'dotfiles'

function Update-SessionPath {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

# パッケージ
$packages = @(
    'Git.Git'
    'GitHub.cli'
    'Microsoft.PowerShell'
    'Starship.Starship'
    'Microsoft.VisualStudioCode'
    'infisical.infisical'
)
foreach ($id in $packages) {
    winget list --id $id --exact --accept-source-agreements | Out-Null
    if ($LASTEXITCODE -ne 0) {
        winget install --id $id --exact --source winget --silent `
            --accept-package-agreements --accept-source-agreements
    }
}
Update-SessionPath

# forgejo-cli (fj)。winget にないので Codeberg のリリースを入れる。
# 署名がないので Smart App Control がオンだと起動できない
$fjVersion = '0.6.0'
$fjSha256 = '9ec20aff62da33afe5a46b6fd63c572dc371d8434b576c35e1fc5204c6652643'
$fjDir = Join-Path $env:LOCALAPPDATA 'Programs\fj'
$fjExe = Join-Path $fjDir 'fj.exe'
$fjInstalled = (Test-Path $fjExe) -and ((& $fjExe version 2>$null) -match "v$([regex]::Escape($fjVersion))\b")
if (-not $fjInstalled) {
    $zip = Join-Path $env:TEMP "forgejo-cli-$fjVersion.zip"
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -UseBasicParsing -OutFile $zip `
        "https://codeberg.org/forgejo-contrib/forgejo-cli/releases/download/v$fjVersion/forgejo-cli-x86_64-windows.zip"
    if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $fjSha256) { throw "fj: sha256 mismatch ($zip)" }
    New-Item -ItemType Directory -Force $fjDir | Out-Null
    Expand-Archive $zip $fjDir -Force
    Remove-Item $zip
}
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($userPath -split ';') -notcontains $fjDir) {
    [Environment]::SetEnvironmentVariable('Path', "$userPath;$fjDir", 'User')
}
Update-SessionPath

# リポジトリ
if (-not (Test-Path (Join-Path $dotfiles '.git'))) {
    gh repo clone 5ym/dotfiles $dotfiles
}
gh auth setup-git

# Git
git config --global include.path '~/dotfiles/.gitconfig'

# SSH
$sshDir = Join-Path $HOME '.ssh'
New-Item -ItemType Directory -Force $sshDir | Out-Null
$sshConfig = Join-Path $sshDir 'config'
$include = 'Include ~/dotfiles/.ssh/config'
if (-not (Test-Path $sshConfig) -or -not (Select-String -Path $sshConfig -SimpleMatch $include -Quiet)) {
    # Include は先頭にないと効かない
    $rest = if (Test-Path $sshConfig) { Get-Content $sshConfig } else { @() }
    @($include) + $rest | Set-Content $sshConfig -Encoding ascii
}

# シークレット (SSH 鍵と GitHub 以外の Git サーバーのトークン) は Infisical から取り出して書き出す。
# 普段の git / ssh は書き出したファイルを使うので、Infisical が落ちていても動く
$infisical = @(
    '--domain', 'https://il.doany.io/api'
    '--projectId', 'b3ee533f-5b9e-4fdf-8c44-109926b78f20'
    '--env', 'prod'
    '--path', '/dotfiles'
    '--silent'
)
$exported = infisical export @infisical --format json 2>$null
if ($LASTEXITCODE -ne 0) {
    infisical login --domain https://il.doany.io/api
    $exported = infisical export @infisical --format json
    if ($LASTEXITCODE -ne 0) { throw 'infisical: シークレットを取得できない' }
}
$secrets = @{}
foreach ($s in ($exported | Out-String | ConvertFrom-Json)) { $secrets[$s.key] = $s.value }
$files = @{
    'SSH_MAIN_PEM'    = Join-Path $sshDir 'main.pem'
    'GIT_CREDENTIALS' = Join-Path $HOME '.git-credentials'
}
foreach ($name in $files.Keys) {
    if (-not $secrets[$name]) { throw "infisical: $name がない" }
    $path = $files[$name]
    $value = $secrets[$name] -replace "`r`n", "`n"
    if (-not $value.EndsWith("`n")) { $value += "`n" }
    if (Test-Path $path) { icacls $path /grant:r "${env:USERNAME}:(F)" | Out-Null }
    [IO.File]::WriteAllText($path, $value, (New-Object Text.UTF8Encoding $false))
    # 本人だけ読める (chmod 600 相当)。Windows の OpenSSH はこうしないと鍵を拒否する
    icacls $path /inheritance:r /grant:r "${env:USERNAME}:(R,W)" | Out-Null
}
Remove-Variable exported, secrets

# PowerShell プロファイル (5.1 と 7 の両方から dotfiles のものを読む)
$docs = [Environment]::GetFolderPath('MyDocuments')
$loader = '. (Join-Path $HOME ''dotfiles\powershell\profile.ps1'')'
foreach ($dir in 'WindowsPowerShell', 'PowerShell') {
    $profilePath = Join-Path $docs "$dir\Microsoft.PowerShell_profile.ps1"
    New-Item -ItemType Directory -Force (Split-Path $profilePath) | Out-Null
    if ((Test-Path $profilePath) -and ((Get-Content $profilePath -Raw) -notmatch [regex]::Escape($loader))) {
        Copy-Item $profilePath "$profilePath.bak" -Force
    }
    Set-Content $profilePath $loader -Encoding ascii
}
# プロファイルを読めるようにする (既定の Restricted だとスクリプトを実行できない)
if ((Get-ExecutionPolicy -Scope CurrentUser) -in 'Undefined', 'Restricted') {
    Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force
}

# フォント (FiraCode Nerd Font)。ユーザー単位で入れるので管理者権限は要らない
$fontVersion = 'v3.5.1'
$fontSha256 = '239395baf60c89b2eaf4862b6b09db0ef95605cd3e8eef51c00345822a81a665'
$fontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
if (-not (Test-Path (Join-Path $fontDir 'FiraCodeNerdFontMono-Regular.ttf'))) {
    $zip = Join-Path $env:TEMP "FiraCode-$fontVersion.zip"
    $extract = Join-Path $env:TEMP "FiraCode-$fontVersion"
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -UseBasicParsing -OutFile $zip `
        "https://github.com/ryanoasis/nerd-fonts/releases/download/$fontVersion/FiraCode.zip"
    if ((Get-FileHash $zip -Algorithm SHA256).Hash -ne $fontSha256) { throw "font: sha256 mismatch ($zip)" }
    Expand-Archive $zip $extract -Force
    New-Item -ItemType Directory -Force $fontDir | Out-Null
    Add-Type -AssemblyName System.Drawing
    $fontReg = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
    foreach ($ttf in Get-ChildItem $extract -Filter *.ttf) {
        $dest = Join-Path $fontDir $ttf.Name
        Copy-Item $ttf.FullName $dest -Force
        $fc = New-Object System.Drawing.Text.PrivateFontCollection
        $fc.AddFontFile($dest)
        # Light などはファミリー名にウェイトが入っているので、Bold / Regular だけ付け足す
        $name = $fc.Families[0].Name
        $style = ($ttf.BaseName -split '-')[-1]
        if ($style -in 'Bold', 'Regular') { $name = "$name $style" }
        New-ItemProperty $fontReg -Name "$name (TrueType)" -Value $dest -Force | Out-Null
        $fc.Dispose()
    }
    Remove-Item $zip, $extract -Recurse -Force
}

# Windows Terminal。settings.json は UI や Terminal 自身も書き込むので丸ごと置き換えず、
# terminal/settings.json に書いた項目だけ上書きする
$wtSettings = Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'
if (Test-Path $wtSettings) {
    function Merge-Json($base, $overlay) {
        foreach ($p in $overlay.PSObject.Properties) {
            $current = $base.PSObject.Properties[$p.Name]
            if ($current -and $current.Value -is [pscustomobject] -and $p.Value -is [pscustomobject]) {
                Merge-Json $current.Value $p.Value
            } else {
                $base | Add-Member -NotePropertyName $p.Name -NotePropertyValue $p.Value -Force
            }
        }
    }
    $settings = Get-Content $wtSettings -Raw -Encoding UTF8 | ConvertFrom-Json
    $overlay = Get-Content (Join-Path $dotfiles 'terminal\settings.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    Merge-Json $settings $overlay
    Copy-Item $wtSettings "$wtSettings.bak" -Force
    # BOM なし UTF-8 で書く (5.1 の Set-Content -Encoding utf8 は BOM を付ける)
    [IO.File]::WriteAllText($wtSettings, ($settings | ConvertTo-Json -Depth 32), (New-Object Text.UTF8Encoding $false))
}

# Dev Drive。作成には管理者権限が要るので、ないときだけ UAC を出して devdrive.ps1 を実行する
if (-not (Test-Path 'C:\DevDrive\DevDrive.vhdx')) {
    # 5.1 は BOM なし UTF-8 のスクリプトを Shift_JIS として読んで壊すので pwsh で実行する
    $p = Start-Process (Get-Command pwsh).Source -Verb RunAs -Wait -PassThru -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$(Join-Path $dotfiles 'devdrive.ps1')`""
    )
    if ($p.ExitCode -ne 0) { throw "devdrive.ps1 が失敗した ($($p.ExitCode))" }
}

Write-Host 'done. 新しいターミナルを開くと反映される'
