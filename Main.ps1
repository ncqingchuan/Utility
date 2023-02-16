using Module .\Thread\CustomThreadPool.psm1

Import-Module -Force -Name .\Data\Datasource.psm1
$path = [System.IO.Path]::Combine($PSScriptRoot, "Data", "Datasource.psm1")
$connectionString = "Data Source=192.168.0.4;Initial Catalog=master;UID=sa;PWD="
$sql = "SELECT * FROM sys.objects where object_id=@objectId"

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
        $p1 = Get-NewParameter -parameterName "objectId" -value $objectId -dbType Int32
        Get-ExecuteReader -connection $connection -commandText $sql -parameters $p1
    }
    catch {
        Write-Host $_.Exception.Message
    }  
}

[CustomThreadPool]$pool = [CustomThreadPool]::new(5, 5, $Host)
$jobs = @()
1..30 | ForEach-Object { 
    $parameters.objectId = $_
    $jobs += $pool.BeginInvoke( $script, $parameters )
}

$pool.EndInvoke($jobs).Table0 | Format-Table
