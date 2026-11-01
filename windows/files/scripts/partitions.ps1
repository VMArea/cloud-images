$ErrorActionPreference = 'Continue'
reagentc /disable | Out-Null
$c = Get-Partition -DriveLetter C
Get-Partition -DiskNumber $c.DiskNumber | Where-Object { $_.Offset -gt $c.Offset } | ForEach-Object {
    Remove-Partition -DiskNumber $c.DiskNumber -PartitionNumber $_.PartitionNumber -Confirm:$false
}
$max = (Get-PartitionSupportedSize -DriveLetter C).SizeMax
Resize-Partition -DriveLetter C -Size $max
Get-Partition -DiskNumber $c.DiskNumber | ForEach-Object { "$($_.PartitionNumber):$($_.Type):$($_.Size)" }
exit 0
