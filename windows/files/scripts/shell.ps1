$ErrorActionPreference = 'SilentlyContinue'
$m = Join-Path $env:LOCALAPPDATA 'vmarea-shell-ready'
if (-not (Test-Path $m)) {
    foreach ($n in 'MicrosoftWindows.Client.CBS', 'MicrosoftWindows.Client.Core', 'Microsoft.Windows.ShellExperienceHost', 'Microsoft.Windows.StartMenuExperienceHost') {
        Get-AppxPackage -AllUsers -Name $n | ForEach-Object { Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppxManifest.xml" }
    }
    New-Item -ItemType File -Path $m -Force | Out-Null
}
Start-Process explorer.exe
