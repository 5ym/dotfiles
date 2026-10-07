# dotfiles

Windows (PowerShell) の開発環境。Linux 環境が必要な作業は wslc のコンテナで行う。

## init

先に Smart App Control をオフにしておく (署名のない fj などが起動できないため。一度オフにすると OS を初期化しないと戻せない)。

```powershell
winget install --id GitHub.cli --exact --source winget
# 新しいターミナルで
gh auth login
# 5.1 は gh の出力 (UTF-8) を CP932 として読み、日本語のコメントが化けて構文エラーになる
[Console]::OutputEncoding = [Text.Encoding]::UTF8
gh api repos/5ym/dotfiles/contents/init.ps1 -H 'Accept: application/vnd.github.raw' | Out-String | Invoke-Expression
```

`init.ps1` は何度実行してもよい。やること:

- winget で Git / GitHub CLI / jq / PowerShell 7 / Starship / VS Code / [wslc-compose](https://github.com/danything/wslc-compose)、Codeberg から fj (forgejo-cli) を入れる。
  jq は gitops の tools のコンテナに入れず手元に置く (コンテナを起こすほどではなく、パイプの先で使うことが多いため)
- `~/dotfiles` に clone し、`~/.gitconfig` と `~/.ssh/config` からこのリポジトリの設定を読む
- Dev Drive がなければ UAC を出して作る (`devdrive.ps1`、50GB。clone 先は `<ドライブ>:\<org>\<repo>`)
- [danything/gitops](https://github.com/danything/gitops) を `<Dev Drive>:\danything\gitops` に clone する。
  infisical などの運用のコマンドは手元に入れず、その `tools/t.ps1` (wslc のコンテナ) で動かす
- Infisical (https://il.doany.io の `/dotfiles`、prod) の `SSH_MAIN_PEM` と `GIT_CREDENTIALS` を `~/.ssh/main.pem` と `~/.git-credentials` に書き出す。
  未ログインならブラウザでログインする (ログイン情報は gitops の `.home/`)
- PowerShell 5.1 / 7 のプロファイル、FiraCode Nerd Font、Windows Terminal (`terminal/settings.json` の項目だけ上書き)

上書きするプロファイルと Terminal の設定は `.bak` に残す。

## シークレット

リポジトリには置かず、Infisical の `/dotfiles` に置く。作り直したら Infisical の値を差し替えて、各端末で `init.ps1` を実行し直す。
`GIT_CREDENTIALS` は GitHub 以外の Git サーバー (fj.doany.io、code.ffmpeg.org) 用で、`https://<ユーザー>:<トークン>@<ホスト>` を 1 行ずつ書く。

fj (forgejo-cli) も `GIT_CREDENTIALS` の fj.doany.io のトークンで `init.ps1` がログインする
(`fj auth login` は Codeberg など fj に組み込まれたインスタンスにしか使えない)。
組織の Actions のシークレットを書くなど、fj で使う権限はそのトークンに付けておく。

NetBird の exit ノードを使っていると、`*.doany.io` を外向きの IPv4 で引いたときに折り返しになって届かないので、
NetBird の DNS ゾーンで `*.doany.io` (と `*.s.doany.io`) を内部の 10.0.0.2 に向けている (`nb.doany.io` だけは例外で外向きのまま)。

## 更新

fj とフォントのバージョンは `init.ps1` に URL と sha256 で書いてある (配布元がチェックサムを出していないので、ダウンロードした zip から計算する)。
