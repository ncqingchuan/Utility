param(
    [string] $connectionString,
    [string]$sql,
    [bool] $debug,
    [int]$objectId
)
if ($debug -eq $true) {
    $DebugPreference = "continue"
}
$connectionString = "Data Source=qingchuan;Initial Catalog=master;Integrated Security=true;max pool size=15;"
$sql = "SELECT @objectId Paramter ,@@SPID SPID,USER_ID() AS [User],@@version AS Version"

$path = [System.IO.Path]::Combine($PSScriptRoot, "Data", "Datasource.psm1")
Import-Module -Name $path -Force

if ($PSVersionTable.PSEdition -eq "Core") {
    $lib = [System.IO.Path]::Combine($PSScriptRoot, "lib", "System.Data.SqlClient.dll")
}
else {
    $lib = [System.IO.Path]::Combine($PSScriptRoot, "lib", "System.Data.dll")
}

Write-Debug "Start at: $((Get-Date).ToString(""HH:mm:ss.ffffff""))"
try {

    $connection = Get-DbConnection -connectionString $connectionString -providerFile $lib
    $p1 = Get-DbParameter -parameterName "objectId" -value $objectId -dbType Int32
    Get-ExecuteReader -connection $connection -commandText $sql -parameters $p1 -close
}
catch {
    Write-Host $_.Exception.Message
}
Start-Sleep -Seconds 2
Write-Debug "End at: $((Get-Date).ToString(""HH:mm:ss.ffffff""))"