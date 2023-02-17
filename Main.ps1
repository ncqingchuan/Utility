using Module .\Thread\CustomThreadPool.psm1

Import-Module -Force -Name .\Data\Datasource.psm1
$path = [System.IO.Path]::Combine($PSScriptRoot, "Data", "Datasource.psm1")
$connectionString = 'Data Source=qingchuan;Initial Catalog=master;UID=sa;PWD=;max pool size=3'
$sql = "SELECT @@SPID AS SPID ,@objectId as ObjectId"

if ($PSVersionTable.PSEdition -eq "Core") {
    $lib = [System.IO.Path]::Combine($PSScriptRoot, "lib", "System.Data.SqlClient.dll")
}
else {
    $lib = [System.IO.Path]::Combine($PSScriptRoot, "lib", "System.Data.dll")
}

$parameters = @{
    path             = $path;
    connectionString = $connectionString ;
    sql              = $sql;
    lib              = $lib
}

$script = {
    param(
        [string] $connectionString,
        [string]$path,        
        [string]$sql,
        [int] $objectId,
        [string]$lib
    )
    try {
        Import-Module -Name $path -Force
        $connection = Get-DbConnection -connectionString $connectionString -providerFile $lib
        $p1 = Get-DbParameter -parameterName "objectId" -value $objectId -dbType Int32
        Get-ExecuteReader -connection $connection -commandText $sql -parameters $p1
    }
    catch {
        Write-Host $_.Exception.Message
    }  
}

[CustomThreadPool]$pool = [CustomThreadPool]::new(3, 6, $Host)
$jobs = @()
1..6 | ForEach-Object { 
    $parameters.objectId = $_
    $jobs += $pool.BeginInvoke( $script, $parameters)
}

$pool.EndInvoke($jobs).List0