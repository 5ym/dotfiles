# Windows の開発環境セットアップ。何度実行しても同じ状態になる。
# Windows PowerShell 5.1 / PowerShell 7 のどちらからでも実行できる。
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$dotfiles = Join-Path $HOME 'dotfiles'

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
foreach ($id in 'Git.Git', 'GitHub.cli', 'jqlang.jq', 'Microsoft.PowerShell', 'Starship.Starship', 'Microsoft.VisualStudioCode', 'danything.wslc-compose') {
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
    $userPath = "$userPath;$fjDir"
    [Environment]::SetEnvironmentVariable('Path', $userPath, 'User')
}
# winget と上で入れたものを、このセッションでも使えるようにする
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + $userPath

# リポジトリと Git
if (-not (Test-Path "$dotfiles\.git")) { gh repo clone 5ym/dotfiles $dotfiles }
gh auth setup-git
git config --global include.path '~/dotfiles/.gitconfig'

# Dev Drive。作成には管理者権限が要るので、ないときだけ UAC を出す。
# 5.1 は BOM なし UTF-8 のスクリプトを Shift_JIS として読むので pwsh で実行する
$pwsh = (Get-Command pwsh).Source
if (-not (Test-Path 'C:\DevDrive\DevDrive.vhdx')) {
    $p = Start-Process $pwsh -Verb RunAs -Wait -PassThru `
        -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$dotfiles\devdrive.ps1`""
    if ($p.ExitCode -ne 0) { throw "devdrive.ps1 が失敗した ($($p.ExitCode))" }
}
$dev = (Get-Volume -FileSystemLabel DevDrive).DriveLetter

# danything/gitops。sops などの運用のコマンドは、手元に入れずに gitops の tools (wslc のコンテナ) で動かす
$gitops = "${dev}:\danything\gitops"
if (-not (Test-Path "$gitops\.git")) { gh repo clone danything/gitops $gitops }
$t = '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "$gitops\tools\t.ps1"

# シークレットはこのリポジトリの secrets.sops.yaml (SOPS。gitops の管理者の age の鍵で暗号化) から取り出してファイルに書き出す。
# 鍵が gitops の .home に無ければ recovery/sops-age.key.age をパスフレーズで開いて置き、取り出したら消す
# (置いてあった鍵は残す)。復号した中身はメモリで受け取る
$key = "$gitops\.home\.config\sops\age\keys.txt"
$placed = -not (Test-Path $key)
# 鍵を置くところから try に入れる (開けずに途中で止まったときも、書きかけの鍵を残さない)
try {
    if ($placed) {
        & $pwsh @t sh -c 'mkdir -p ~/.config/sops/age && age -d -o ~/.config/sops/age/keys.txt recovery/sops-age.key.age'
        if ($LASTEXITCODE -ne 0) { throw 'age: recovery/sops-age.key.age を開けない' }
    }
    $exported = Get-Content -Raw "$dotfiles\secrets.sops.yaml" |
        & $pwsh @t sops -d --input-type yaml --output-type json /dev/stdin
    if ($LASTEXITCODE -ne 0) { throw 'sops: secrets.sops.yaml を開けない' }
} finally {
    if ($placed) { Remove-Item $key -ErrorAction SilentlyContinue }
}
$cred = ($exported | Out-String | ConvertFrom-Json).GIT_CREDENTIALS
if (-not $cred) { throw 'sops: secrets.sops.yaml に GIT_CREDENTIALS がない' }
$credFile = "$HOME\.git-credentials"
if (Test-Path $credFile) { icacls $credFile /grant:r "${env:USERNAME}:(F)" | Out-Null }
[IO.File]::WriteAllText($credFile, ($cred.TrimEnd() -replace "`r`n", "`n") + "`n")
# 本人だけ読める (chmod 600 相当)
icacls $credFile /inheritance:r /grant:r "${env:USERNAME}:(R,W)" | Out-Null
# fj (forgejo-cli) も GIT_CREDENTIALS のトークンでログインする。GIT_CREDENTIALS は Forgejo のホスト
# (fj.doany.io、code.ffmpeg.org) だけなので、全行を登録する (fj の auth login は自前の
# インスタンスでは使えない)。トークンは標準入力で渡す (引数だとプロセス一覧に出る)。
# 登録済みのホストは何もしない (whoami は read:user の権限が要るので、fj の keys.json で見る)
$fjKeys = Join-Path $env:APPDATA 'forgejo-cli\forgejo-cli\data\keys.json'
$fjHosts = if (Test-Path $fjKeys) { (Get-Content $fjKeys -Raw | ConvertFrom-Json).hosts } else { $null }
foreach ($line in ($cred -split "`r?`n") | Where-Object { $_ -match '^https://[^:/]+:[^@]+@[^/]+/?$' }) {
    $uri = [Uri]$line
    if ($fjHosts -and $fjHosts.($uri.Host)) { continue }
    [Uri]::UnescapeDataString($uri.UserInfo.Split(':', 2)[1]) | & "$fjDir\fj.exe" -H $uri.Host auth add-token | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Warning "fj: $($uri.Host) のトークンを登録できなかった" }
}
Remove-Variable exported, cred, line, uri -ErrorAction SilentlyContinue

# PowerShell プロファイル。5.1 と 7 の両方から dotfiles のものを読む。前のプロファイルが dotfiles を読む行でなければ .bak に残す。
# ファイルを直接 dot-source しない。5.1 は BOM なし UTF-8 を Shift_JIS として読み、日本語で終わるコメントの次の行まで
# コメントになって構文エラーになる
$loader = '. ([scriptblock]::Create([IO.File]::ReadAllText("$HOME\dotfiles\profile.ps1")))'
foreach ($dir in 'WindowsPowerShell', 'PowerShell') {
    $p = Join-Path ([Environment]::GetFolderPath('MyDocuments')) "$dir\Microsoft.PowerShell_profile.ps1"
    New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null
    if ((Test-Path $p) -and (Get-Content $p -Raw) -notmatch 'dotfiles.*profile\.ps1') { Copy-Item $p "$p.bak" -Force }
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

# Windows Terminal。settings.json は UI も書き込むので、terminal.json の項目だけ上書きする
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
    Merge-Json $settings (Get-Content "$dotfiles\terminal.json" -Raw -Encoding UTF8 | ConvertFrom-Json)
    Copy-Item $wt "$wt.bak" -Force
    # WriteAllText は BOM なし UTF-8 (5.1 の Set-Content -Encoding utf8 は BOM を付ける)
    [IO.File]::WriteAllText($wt, ($settings | ConvertTo-Json -Depth 32))
}

Write-Host 'done. 新しいターミナルを開くと反映される'
