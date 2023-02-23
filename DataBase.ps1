param(
    [bool] $debug,
    [int]$objectId
)
if ($debug -eq $true) {
    $DebugPreference = "continue"
}

$sql = "SELECT @objectId Paramter ,@@SPID SPID,USER_ID() AS [User]"
$connectionString = 'Data Source=qingchuan;Initial Catalog=master;Uid=sa;pwd='

if ($PSVersionTable.PSEdition -eq "Core") {
    $lib = [System.IO.Path]::Combine($PSScriptRoot, "lib", "System.Data.SqlClient.dll")
}
else {
    $lib = [System.IO.Path]::Combine($PSScriptRoot, "lib", "System.Data.dll")
}

try {
    Write-Debug "Start at: $((Get-Date).ToString(""HH:mm:ss.ffffff""))"
    $connection = Get-DbConnection -connectionString $connectionString -providerFile $lib
    $p1 = Get-DbParameter -parameterName "objectId" -value $objectId -dbType Int32
    $result = Get-ExecuteReader -connection $connection -commandText $sql -parameters $p1 -close
    return @{Code = 0; Data = $result }
}
catch {
    Write-Debug "Exception:$($_.Exception.Message)"
    return @{Code = 1; Data = (New-Object psobject -Property @{
                Message  = $_.Exception.Message;
                ObjectId = $objectId 
            }) 
    }
}
