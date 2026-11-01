$ErrorActionPreference = 'Stop'
$root = Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root } | Where-Object { Test-Path ($_ + 'updates\updates.json') } | Select-Object -First 1
$list = Get-Content "${root}updates\updates.json" -Raw | ConvertFrom-Json
$out = @()
foreach ($u in $list) {
    $f = Join-Path "${root}updates" $u.file
    Write-Output "install $($u.kb) $($u.role)"
    $p = Start-Process dism.exe -ArgumentList "/online /add-package /packagepath:`"$f`" /norestart /LogPath:C:\Windows\Temp\dism-$($u.kb).log" -Wait -PassThru -NoNewWindow
    $code = $p.ExitCode
    Write-Output "  dism exit $code"
    if ($code -ne 0 -and $code -ne 3010) {
        $w = Start-Process wusa.exe -ArgumentList "`"$f`" /quiet /norestart" -Wait -PassThru
        $code = $w.ExitCode
        Write-Output "  wusa exit $code"
        if ($code -eq 2359302) { $code = 0 }
    }
    if ($code -ne 0 -and $code -ne 3010 -and $u.role -ne 'prereq') { throw "update failed for $($u.kb): $code" }
    $out += @{ kb = $u.kb; role = $u.role; exit = $code }
}
ConvertTo-Json -Compress -InputObject @($out)
