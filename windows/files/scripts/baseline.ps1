$ErrorActionPreference = 'Continue'
function Set-Reg($Path, $Name, $Value, $Type = 'DWord') {
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type
}
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' fDenyTSConnections 0
Set-Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp' UserAuthentication 1
Set-Service TermService -StartupType Automatic
Enable-NetFirewallRule -DisplayGroup 'Remote Desktop'
Get-NetFirewallRule -DisplayGroup 'Remote Desktop' | Set-NetFirewallRule -Profile Any
if (-not (Get-NetFirewallRule -Name 'VMArea-RDP-TCP-In' -ErrorAction SilentlyContinue)) {
    New-NetFirewallRule -Name 'VMArea-RDP-TCP-In' -DisplayName 'Remote Desktop (TCP 3389)' -Direction Inbound -Protocol TCP -LocalPort 3389 -Action Allow -Profile Any | Out-Null
}
foreach ($n in 'FPS-ICMP4-ERQ-In', 'FPS-ICMP6-ERQ-In') {
    Set-NetFirewallRule -Name $n -Enabled True -Profile Any -ErrorAction SilentlyContinue
}
net accounts /lockoutthreshold:0 | Out-Null
$inf = Join-Path $env:TEMP 'vmarea-sec.inf'
$db = Join-Path $env:TEMP 'vmarea-sec.sdb'
secedit /export /cfg $inf /areas SECURITYPOLICY | Out-Null
$c = Get-Content $inf
$c = $c | Where-Object { $_ -notmatch '^(LockoutBadCount|AllowAdministratorLockout)\s*=' }
$c = $c -replace '^\[System Access\]', "[System Access]`r`nLockoutBadCount = 0`r`nAllowAdministratorLockout = 0"
Set-Content -Path $inf -Value $c -Encoding Unicode
secedit /configure /db $db /cfg $inf /areas SECURITYPOLICY | Out-Null
Remove-Item $inf, $db -Force -ErrorAction SilentlyContinue
powercfg /h off | Out-Null
$hp = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
if (-not ((powercfg /l) -match $hp)) { powercfg /duplicatescheme $hp $hp | Out-Null }
powercfg /setactive $hp | Out-Null
powercfg /change standby-timeout-ac 0 | Out-Null
powercfg /change monitor-timeout-ac 0 | Out-Null
Set-TimeZone -Id 'UTC'
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Reliability' ShutdownReasonOn 0
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Reliability' ShutdownReasonUI 0
Set-Reg 'HKLM:\SOFTWARE\Microsoft\ServerManager' DoNotOpenServerManagerAtLogon 1
Set-Reg 'HKLM:\SOFTWARE\Microsoft\ServerManager' DoNotPopWACConsoleAtSMLaunch 1
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Server\ServerManager' DoNotOpenAtLogon 1
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' NoAutoUpdate 0
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' AUOptions 2
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' NoAutoRebootWithLoggedOnUsers 1
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection' DisableRealtimeMonitoring 1
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection' DisableBehaviorMonitoring 1
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection' DisableOnAccessProtection 1
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Real-Time Protection' DisableIOAVProtection 1
try { Set-MpPreference -DisableRealtimeMonitoring $true -ErrorAction Stop } catch { Write-Output "Set-MpPreference: $($_.Exception.Message)" }
Disable-NetAdapterPowerManagement -Name * -ErrorAction SilentlyContinue

$setup = Get-ItemProperty 'HKLM:\SYSTEM\Setup' -ErrorAction SilentlyContinue
if ($setup.OOBEInProgress -eq 0 -and $setup.SystemSetupInProgress -eq 0) {
    Remove-Item 'C:\Windows\Panther\unattend.xml', 'C:\Windows\System32\Sysprep\Unattend.xml', 'C:\Program Files\Cloudbase Solutions\Cloudbase-Init\conf\Unattend.xml' -Force -ErrorAction SilentlyContinue
    Remove-Item 'C:\Windows\Panther\Unattend' -Recurse -Force -ErrorAction SilentlyContinue
}
Set-Reg 'HKLM:\SOFTWARE\Policies\Microsoft\EdgeUpdate' CreateDesktopShortcutDefault 0
$chrome = 'C:\Program Files\Google\Chrome\Application'
if (Test-Path $chrome) {
    foreach ($n in 'initial_preferences', 'master_preferences') {
        Set-Content "$chrome\$n" '{"distribution":{"do_not_create_desktop_shortcut":true,"do_not_create_quick_launch_shortcut":true,"do_not_create_taskbar_shortcut":true}}' -Encoding ASCII
    }
}
$trimDir = 'C:\ProgramData\VMArea'
New-Item -ItemType Directory -Path $trimDir -Force | Out-Null
Set-Content -Path "$trimDir\memory-trim.ps1" -Encoding UTF8 -Value @'
$os = Get-CimInstance Win32_OperatingSystem
$free = $os.FreePhysicalMemory * 1KB
$keep = [math]::Max(512MB, $os.TotalVisibleMemorySize * 1KB * 0.05)
$chunks = [math]::Floor(($free - $keep) / 256MB)
if ($chunks -lt 4) { exit 0 }
$held = New-Object System.Collections.Generic.List[byte[]]
for ($c = 0; $c -lt $chunks; $c++) {
    try { $a = [byte[]]::new(256MB) } catch { break }
    for ($o = 0; $o -lt $a.Length; $o += 4096) { $a[$o] = 0 }
    $held.Add($a)
}
exit 0
'@
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File $trimDir\memory-trim.ps1"
$trigger = New-ScheduledTaskTrigger -Daily -At '01:00' -RandomDelay (New-TimeSpan -Hours 4)
$settings = New-ScheduledTaskSettingsSet -Priority 7 -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -StartWhenAvailable -DontStopIfGoingOnBatteries -AllowStartIfOnBatteries
Register-ScheduledTask -TaskName 'VMArea Memory Trim' -TaskPath '\VMArea\' -Action $action -Trigger $trigger -Settings $settings -User 'SYSTEM' -RunLevel Highest -Description 'Zeroes free memory once a day so the host can reclaim it. Safe to disable.' -Force | Out-Null
Write-Output 'baseline applied'
exit 0
