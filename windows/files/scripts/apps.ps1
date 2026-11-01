$ErrorActionPreference = 'Stop'
$root = Get-PSDrive -PSProvider FileSystem | ForEach-Object { $_.Root } | Where-Object { Test-Path ($_ + 'apps\apps.json') } | Select-Object -First 1
$apps = Get-Content "${root}apps\apps.json" -Raw | ConvertFrom-Json
$result = @()
foreach ($a in $apps) {
    $f = Join-Path "${root}apps" $a.file
    $sig = Get-AuthenticodeSignature $f
    if ($a.signer -and ($sig.Status -ne 'Valid' -or $sig.SignerCertificate.Subject -notmatch [regex]::Escape($a.signer))) {
        throw "signature check failed for $($a.id): $($sig.Status) $($sig.SignerCertificate.Subject)"
    }
    if ($a.file -like '*.msi') {
        $p = Start-Process msiexec.exe -ArgumentList "/i `"$f`" /qn /norestart ALLUSERS=1" -Wait -PassThru
    } else {
        $p = Start-Process $f -ArgumentList $a.args -Wait -PassThru
    }
    if (-not (Test-Path $a.path)) { throw "$($a.id) not installed (exit $($p.ExitCode))" }
    $result += @{ id = $a.id; version = (Get-Item $a.path).VersionInfo.ProductVersion; signer = "$($sig.SignerCertificate.Subject)"; exit = $p.ExitCode }
}
Get-ChildItem 'C:\Users\Public\Desktop', 'C:\Users\Default\Desktop' -Filter *.lnk -Force -ErrorAction SilentlyContinue | Remove-Item -Force
Get-ChildItem 'C:\Users\*\Desktop\*.lnk' -Force -ErrorAction SilentlyContinue | Remove-Item -Force
$result | ConvertTo-Json -Compress
