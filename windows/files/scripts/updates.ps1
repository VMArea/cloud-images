$ErrorActionPreference = 'Stop'
$root = Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root } | Where-Object { Test-Path ($_ + 'updates\updates.json') } | Select-Object -First 1
$list = Get-Content "${root}updates\updates.json" -Raw | ConvertFrom-Json
$out = @()
foreach ($u in $list) {
    $f = Join-Path "${root}updates" $u.file
    $sig = Get-AuthenticodeSignature $f
    Write-Output "install $($u.kb) $($u.role) signature=$($sig.Status)"
    $p = Start-Process dism.exe -ArgumentList "/online /add-package /packagepath:`"$f`" /norestart /LogPath:C:\Windows\Temp\dism-$($u.kb).log" -Wait -PassThru -NoNewWindow
    Write-Output "  exit $($p.ExitCode)"
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010 -and $u.role -ne "prereq") { throw "dism failed for $($u.kb): $($p.ExitCode)" }
    $out += @{ kb = $u.kb; role = $u.role; exit = $p.ExitCode }
}
ConvertTo-Json -Compress -InputObject @($out)
