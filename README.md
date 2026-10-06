# dotfiles

Windows (PowerShell) の開発環境。Linux 環境が必要な作業は wslc のコンテナで行う。

## init

先に Smart App Control をオフにしておく (署名のない fj などが起動できないため。一度オフにすると OS を初期化しないと戻せない)。

```powershell
winget install --id GitHub.cli --exact --source winget
# 新しいターミナルで
gh auth login
gh api repos/5ym/dotfiles/contents/init.ps1 -H 'Accept: application/vnd.github.raw' | Out-String | Invoke-Expression
```

`init.ps1` は何度実行してもよい。やること:

- winget で Git / GitHub CLI / PowerShell 7 / Starship / VS Code / Infisical CLI、Codeberg から fj (forgejo-cli) を入れる
- `~/dotfiles` に clone し、`~/.gitconfig` と `~/.ssh/config` からこのリポジトリの設定を読む
- Infisical (https://il.doany.io の `/dotfiles`、prod) の `SSH_MAIN_PEM` と `GIT_CREDENTIALS` を `~/.ssh/main.pem` と `~/.git-credentials` に書き出す
- PowerShell 5.1 / 7 のプロファイル、FiraCode Nerd Font、Windows Terminal (`terminal/settings.json` の項目だけ上書き)
- Dev Drive がなければ UAC を出して作る (`devdrive.ps1`、50GB。clone 先は `<ドライブ>:\<org>\<repo>`)

上書きするプロファイルと Terminal の設定は `.bak` に残す。

## シークレット

リポジトリには置かず、Infisical の `/dotfiles` に置く。作り直したら Infisical の値を差し替えて、各端末で `init.ps1` を実行し直す。
`GIT_CREDENTIALS` は GitHub 以外の Git サーバー (fj.doany.io、code.ffmpeg.org) 用で、`https://<ユーザー>:<トークン>@<ホスト>` を 1 行ずつ書く。

fj は端末ごとに `fj -H fj.doany.io auth add-key <ユーザー> <トークン>` でログインする。

## 更新

fj とフォントのバージョンは `init.ps1` に URL と sha256 で書いてある (配布元がチェックサムを出していないので、ダウンロードした zip から計算する)。
