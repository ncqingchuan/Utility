using Module .\Thread\CustomThreadPool.psm1

$path = [System.IO.Path]::Combine($PSScriptRoot, "Data", "Datasource.psm1")
Import-Module -Force -Name $path

$connectionString = "Data Source=SqlServer;Initial Catalog=master;UID=sa;PWD=;max pool size=15;"
$sql = "SELECT @objectId ,@@SPID,USER_ID() AS [User],@@version AS Version"

if ($PSVersionTable.PSEdition -eq "Core") {
    $lib = [System.IO.Path]::Combine($PSScriptRoot, "lib", "System.Data.SqlClient.dll")
}
else {
    $lib = [System.IO.Path]::Combine($PSScriptRoot, "lib", "System.Data.dll")
}

$parameters = @{
    path             = $path;
    connectionString = $connectionString;
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
        $p1 = Get-NewParameter -parameterName "objectId" -value $objectId -dbType Int32
        Get-ExecuteReader -connection $connection -commandText $sql -parameters $p1 -close
    }
    catch {
        Write-Host $_.Exception.Message
    }  
}

$jobs = @()
[CustomThreadPool]$pool = [CustomThreadPool]::new(10, 15, $Host)
1..20 | ForEach-Object { 
    $parameters.objectId = $_
    $jobs += $pool.BeginInvoke( $script, $parameters)
}
$pool.EndInvoke($jobs).List0 
