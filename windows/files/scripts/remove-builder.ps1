$ErrorActionPreference = 'Continue'
$q = quser 2>$null
foreach ($l in $q) { if ($l -match 'vmbuild') { $id = ($l -split '\s+' | Where-Object { $_ -match '^\d+$' } | Select-Object -First 1); if ($id) { logoff $id } } }
Start-Sleep 10
Remove-LocalUser -Name vmbuild -ErrorAction SilentlyContinue
Get-CimInstance Win32_UserProfile | Where-Object { $_.LocalPath -like '*\vmbuild' } | Remove-CimInstance -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force C:\Users\vmbuild -ErrorAction SilentlyContinue
Get-LocalUser | Select-Object Name, Enabled | Format-Table | Out-String
