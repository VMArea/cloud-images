$ErrorActionPreference = 'Stop'
$cb = 'C:\Program Files\Cloudbase Solutions\Cloudbase-Init'
$root = Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root } | Where-Object { Test-Path ($_ + 'cloudbase\cloudbase-init.conf') } | Select-Object -First 1
$msi = (Get-ChildItem -Path "${root}cloudbase" -Filter *.msi).FullName
$p = Start-Process msiexec.exe -ArgumentList "/i `"$msi`" /qn /norestart RUN_SERVICE_AS_LOCAL_SYSTEM=1 /l*v C:\Windows\Temp\cloudbase-init-install.log" -Wait -PassThru
Write-Output "cloudbase-init msi exit $($p.ExitCode)"
Stop-Service cloudbase-init -Force -ErrorAction SilentlyContinue
Copy-Item "${root}cloudbase\cloudbase-init.conf" "$cb\conf\cloudbase-init.conf" -Force
Copy-Item "${root}cloudbase\cloudbase-init-unattend.conf" "$cb\conf\cloudbase-init-unattend.conf" -Force
Copy-Item "${root}cloudbase\Unattend.xml" "$cb\conf\Unattend.xml" -Force
Set-Service cloudbase-init -StartupType Automatic
New-Item -ItemType Directory -Force 'C:\Windows\Setup\Scripts' | Out-Null
Copy-Item "${root}scripts\baseline.ps1" 'C:\Windows\Setup\Scripts\vmarea-baseline.ps1' -Force
$sc = @(
    '@echo off',
    'powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Windows\Setup\Scripts\vmarea-baseline.ps1',
    'del /f /q "C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\Unattend.xml"',
    'del /f /q C:\Windows\Panther\unattend.xml',
    'rd /s /q C:\Windows\Panther\Unattend',
    'del /f /q C:\Windows\System32\Sysprep\Unattend.xml',
    'exit /b 0'
)
Set-Content -Path 'C:\Windows\Setup\Scripts\SetupComplete.cmd' -Value $sc -Encoding Ascii
New-Item -ItemType Directory -Force 'C:\ProgramData\VMArea' | Out-Null
$readme = 'These files let the control panel set your password, hostname and network, and run startup scripts. Removing or changing them can stop those features working. We cannot support servers where they were changed. Files: C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\ (configuration), QEMU guest agent service, VirtIO drivers.'
[IO.File]::WriteAllText('C:\ProgramData\VMArea\README.txt', $readme + "`r`n", (New-Object Text.UTF8Encoding($false)))
New-Item -ItemType Directory -Force "$cb\LocalScripts" | Out-Null
Copy-Item "${root}scripts\baseline.ps1" "$cb\LocalScripts\vmarea-baseline.ps1" -Force
Remove-Item -Recurse -Force "$cb\log\*" -ErrorAction SilentlyContinue
$esp = Get-Partition -DiskNumber 0 | Where-Object { $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' } | Select-Object -First 1
$esp | Add-PartitionAccessPath -AccessPath 'S:\' -ErrorAction Stop
New-Item -ItemType Directory -Force 'S:\EFI\Boot' | Out-Null
Copy-Item 'S:\EFI\Microsoft\Boot\bootmgfw.efi' 'S:\EFI\Boot\bootx64.efi' -Force
$esp | Remove-PartitionAccessPath -AccessPath 'S:\'
Remove-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name DefaultPassword -ErrorAction SilentlyContinue
Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name AutoAdminLogon -Value 0
if ([Environment]::OSVersion.Version.Build -ge 26100) {
    Copy-Item "${root}scripts\shell.ps1" 'C:\ProgramData\VMArea\shell.ps1' -Force
    Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name Shell -Value 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\ProgramData\VMArea\shell.ps1'
}
Write-Output 'prepared'
