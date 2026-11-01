$ErrorActionPreference = 'Continue'
Start-Transcript -Path C:\Windows\Temp\first-logon.log -Force
$root = Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root } | Where-Object { Test-Path ($_ + 'virtio-win-gt-x64.msi') } | Select-Object -First 1
Write-Host "virtio root: $root"
$p = Start-Process msiexec.exe -ArgumentList "/i `"${root}virtio-win-gt-x64.msi`" /qn /norestart /l*v C:\Windows\Temp\virtio-gt.log" -Wait -PassThru
Write-Host "virtio-win-gt exit $($p.ExitCode)"
$p = Start-Process msiexec.exe -ArgumentList "/i `"${root}guest-agent\qemu-ga-x86_64.msi`" /qn /norestart /l*v C:\Windows\Temp\qemu-ga.log" -Wait -PassThru
Write-Host "qemu-ga exit $($p.ExitCode)"
Set-Service -Name QEMU-GA -StartupType Automatic
Start-Service -Name QEMU-GA
Stop-Transcript
