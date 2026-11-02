$ErrorActionPreference = 'Stop'
$vol = Get-Volume | Where-Object { $_.FileSystemLabel -eq 'config-2' -and $_.DriveLetter } | Select-Object -First 1
if (-not $vol) { exit 0 }
$p = "$($vol.DriveLetter):\openstack\latest\user_data"
if (-not (Test-Path $p)) { exit 0 }
$text = Get-Content $p -Raw
$pw = [regex]::Match($text, '(?m)^password:\s*(\S.*?)\s*$')
if ($pw.Success) {
    $v = $pw.Groups[1].Value.Trim('"', "'")
    ([ADSI]'WinNT://./Administrator,user').SetPassword($v)
}
$m = [regex]::Match($text, '(?m)^hostname:\s*([A-Za-z0-9][A-Za-z0-9.-]*)\s*$')
if (-not $m.Success) { $m = [regex]::Match($text, '(?m)^fqdn:\s*([A-Za-z0-9][A-Za-z0-9.-]*)\s*$') }
if (-not $m.Success) { exit 0 }
$name = $m.Groups[1].Value.Split('.')[0]
$cur = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters').Hostname
if ($cur -eq $name) { exit 0 }
Add-Type -Namespace VMArea -Name Host -MemberDefinition '[DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] public static extern bool SetComputerNameExW(int t, string n);'
if (-not [VMArea.Host]::SetComputerNameExW(5, $name)) { throw "SetComputerNameEx failed: $([Runtime.InteropServices.Marshal]::GetLastWin32Error())" }
exit 1001
