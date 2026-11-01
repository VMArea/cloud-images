$ErrorActionPreference = 'Continue'
Stop-Service wuauserv -Force -ErrorAction SilentlyContinue
Dism.exe /Online /Cleanup-Image /StartComponentCleanup /ResetBase
function Wipe($p) { Get-ChildItem $p -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue }
Wipe 'C:\Windows\SoftwareDistribution\Download'
Wipe 'C:\Windows\Panther'
Wipe 'C:\Windows\System32\Sysprep\Panther'
Remove-Item 'C:\Windows\System32\Sysprep\Unattend.xml', 'C:\Windows\System32\Sysprep\sysprep.xml' -Force -ErrorAction SilentlyContinue
Wipe 'C:\Windows\Temp'
Get-ChildItem 'C:\Users' -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object { Wipe (Join-Path $_.FullName 'AppData\Local\Temp') }
Wipe 'C:\Windows\Logs'
Wipe 'C:\Windows\debug'
Get-ChildItem 'C:\Windows\INF' -Filter 'setupapi*.log' -Force -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
Wipe 'C:\ProgramData\Microsoft\Windows\WER'
Stop-Service cloudbase-init -Force -ErrorAction SilentlyContinue
Wipe 'C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log'
Wipe 'C:\$Recycle.Bin'
Get-ChildItem 'C:\Users\*\Desktop\*' -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
Get-ChildItem 'C:\Users\Public\Desktop\*' -Force -ErrorAction SilentlyContinue | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
$z = 'C:marea-zero.tmp'
$buf = New-Object byte[] (4MB)
$fs = [IO.File]::Create($z)
try { while ((Get-PSDrive C).Free -gt 200MB) { $fs.Write($buf, 0, $buf.Length); $fs.Flush() } } catch {}
$fs.Close()
Remove-Item $z -Force
wevtutil el | ForEach-Object { wevtutil cl $_ 2>$null }
Write-Output 'cleanup done'
