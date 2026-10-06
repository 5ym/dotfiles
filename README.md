# dotfiles

Windows (PowerShell) の開発環境。Linux 環境が必要な作業は wslc のコンテナで行う。

## init

先に Smart App Control をオフにする(Windows セキュリティ → アプリとブラウザーの制御 → スマート アプリ コントロールの設定)。署名のない CLI (fj など) が起動できなくなるため。一度オフにすると OS を初期化しないとオンに戻せない。

PowerShell で実行する。

```powershell
winget install --id GitHub.cli --exact --source winget
# 新しいターミナルを開いてから
gh auth login
gh api repos/5ym/dotfiles/contents/init.ps1 -H 'Accept: application/vnd.github.raw' | Out-String | Invoke-Expression
```

`init.ps1` がやること(何度実行してもよい):

- winget で Git / GitHub CLI / PowerShell 7 / Starship / VS Code / Infisical CLI を入れる
- fj (forgejo-cli) を Codeberg のリリースから `%LOCALAPPDATA%\Programs\fj` に入れて PATH に追加(sha256 を照合)
- このリポジトリを `~/dotfiles` に clone し、`gh auth setup-git`
- `~/.gitconfig` から `~/dotfiles/.gitconfig` を include
- `~/.ssh/config` の先頭に `Include ~/dotfiles/.ssh/config`
- Infisical (https://il.doany.io、`/dotfiles` の prod) からシークレットを取り出し、`~/.ssh/main.pem` と `~/.git-credentials` に本人だけ読める権限で書き出す(未ログインならログインを求める)
- FiraCode Nerd Font を入れ、Windows Terminal に `terminal/settings.json` の項目を上書きする
- Windows PowerShell 5.1 と PowerShell 7 の `$PROFILE` から `powershell/profile.ps1` を読む(元のファイルは `.bak` に残す)
- 実行ポリシーが Restricted なら CurrentUser を RemoteSigned にする
- Dev Drive がなければ、UAC を出して `devdrive.ps1` で作る(`C:\DevDrive\DevDrive.vhdx`、50GB の可変サイズ、空いているドライブ文字を D から)。起動時に attach し直すタスク「Mount DevDrive」も登録する。clone 先は `<ドライブ>:\<org>\<repo>`

## GitHub 以外の Git サーバー

`.gitconfig` で `fj.doany.io`(Forgejo)と `code.ffmpeg.org` の認証を `~/.git-credentials` から読む。中身は Infisical の `/dotfiles/GIT_CREDENTIALS` に 1 行ずつ置く。トークンを作り直したら Infisical の値を差し替え、各端末で `init.ps1` を実行し直す。

```
https://<ユーザー>:<トークン>@fj.doany.io
```

SSH 鍵も同じく Infisical の `/dotfiles/SSH_MAIN_PEM`。リポジトリにはシークレットを置かない(`.gitignore` 済み)。

Forgejo のトークンは 設定 → アプリケーション で作る(push だけなら `write:repository`)。

## fj (forgejo-cli)

端末ごとに一度ログインする。

```powershell
fj -H fj.doany.io auth add-key <ユーザー> <トークン>
```

fj を更新するときは `init.ps1` の `$fjVersion` と `$fjSha256`(リリースの zip の sha256。配布元はチェックサムを出していない)を書き換えて `init.ps1` を実行し直す。

改行は `.gitattributes` で LF に固定している。
