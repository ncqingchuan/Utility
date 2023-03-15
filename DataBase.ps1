param(
    [int]$objectId,
    [string]$lock,
    [string]$connectionString
)

$sql = "p_Get_Return_Value"
try {
    $connection = Get-DbConnection -connectionString $connectionString
    $p1 = Get-DbParameter -parameterName "@returnValue" -dbType Int32 -direction ([System.Data.ParameterDirection]::ReturnValue)
    $p2 = Get-DbParameter -parameterName "@objectId" -dbType Int32 -value $objectId
    Get-ExecuteNonQuery -connection $connection -commandText $sql -parameters $p1, $p2 -close -commandType StoredProcedure | Out-Null
    Lock-Object ($lock) {
        Add-Content -Path $lock -Value $objectId
    }
    return $true
}
catch {
    Lock-Object ($lock) {
        Add-Content -Path $lock -Value $_.Exception.Message
    }
    return $false
}
