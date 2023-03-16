param(
    [int]$objectId,
    [string]$lock,
    [string]$connectionString
)

# Import-Module -Name .\Thread\LockObject.psm1 -Force
# Import-Module -Name .\Data\Datasource.psm1 -Force
# $connectionString = 'Data Source=qingchuan;Initial Catalog=HighwaveDw;Integrated Security=true'
$sql = "p_Get_Return_Value"
try {
    $connection = New-Object System.Data.SqlClient.SqlConnection -ArgumentList $connectionString
    $Job = Register-ObjectEvent -InputObject $connection -EventName "InfoMessage" -Action {
        Param(
            [System.Object]$sender,
            [System.Data.SqlClient.SqlInfoMessageEventArgs] $e
        )
        $Message = $e.Errors
    } 
    $p1 = Get-DbParameter -parameterName "@returnValue" -dbType Int32 -direction ([System.Data.ParameterDirection]::ReturnValue)
    $p2 = Get-DbParameter -parameterName "@objectId" -dbType Int32 -value $objectId
    Get-ExecuteNonQuery -connection $connection -commandText $sql -parameters $p1, $p2 -close -commandType StoredProcedure | Out-Null
    $value = & $Job.Module { $Message }
    Lock-Object ($lock) {
        Add-Content -Path $lock -Value $value.Message
    }
    return $true    
}
catch {
    Lock-Object ($lock) {
        Add-Content -Path $lock -Value $_.Exception.Message
    }
    return $false
}
