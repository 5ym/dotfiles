# Dev Drive (ReFS, Defender のパフォーマンスモード) を VHDX で作る。管理者権限で実行する。
# init.ps1 から VHDX がないときだけ呼ばれる。clone 先は <ドライブ>:\<org>\<repo>
param(
    [string]$VhdPath = 'C:\DevDrive\DevDrive.vhdx',
    [int]$SizeGB = 50,
    [string]$TaskName = 'Mount DevDrive'
)
$ErrorActionPreference = 'Stop'

if (Test-Path $VhdPath) { Write-Host "$VhdPath はもうある"; return }

# D から順に空いているドライブ文字を使う
$used = (Get-PSDrive -PSProvider FileSystem).Name
$letter = [char[]]([int][char]'D'..[int][char]'Z') | Where-Object { $used -notcontains [string]$_ } | Select-Object -First 1
if (-not $letter) { throw 'ドライブ文字が空いていない' }

New-Item -ItemType Directory -Force (Split-Path $VhdPath) | Out-Null
$dp = Join-Path $env:TEMP 'devdrive-create.txt'
"create vdisk file=`"$VhdPath`" maximum=$($SizeGB * 1024) type=expandable`r`nselect vdisk file=`"$VhdPath`"`r`nattach vdisk" |
    Out-File $dp -Encoding ascii
diskpart /s $dp | Out-Null
if ($LASTEXITCODE -ne 0) { throw "diskpart が失敗した ($LASTEXITCODE)" }
Remove-Item $dp
Start-Sleep 3

$disk = Get-DiskImage -ImagePath $VhdPath | Get-Disk
if ($disk.BusType -ne 'File Backed Virtual') { throw "想定外のディスク ($($disk.Number), $($disk.BusType))" }
Initialize-Disk -Number $disk.Number -PartitionStyle GPT
New-Partition -DiskNumber $disk.Number -UseMaximumSize -DriveLetter $letter | Out-Null
# Format-Volume -DevDrive は環境によってパラメーターセットを解決できないので format を使う
cmd /c "echo Y| format ${letter}: /DevDrv /Q /V:DevDrive" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "format が失敗した ($LASTEXITCODE)" }

# 接続した VHDX は再起動で外れるので、起動時に attach し直す。
# タスクの既定は「バッテリー駆動中は起動しない」なので、ノート PC だと電源を挿さずに起動したとき外れたままになる
$attach = Join-Path (Split-Path $VhdPath) 'attach.txt'
"select vdisk file=`"$VhdPath`"`r`nattach vdisk" | Out-File $attach -Encoding ascii
Register-ScheduledTask -TaskName $TaskName -Force `
    -Action (New-ScheduledTaskAction -Execute 'diskpart.exe' -Argument "/s `"$attach`"") `
    -Trigger (New-ScheduledTaskTrigger -AtStartup) `
    -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries) `
    -Principal (New-ScheduledTaskPrincipal -UserId 'SYSTEM' -RunLevel Highest) | Out-Null

fsutil devdrv query "${letter}:"
Write-Host "Dev Drive: ${letter}:\ ($VhdPath, ${SizeGB}GB)"
