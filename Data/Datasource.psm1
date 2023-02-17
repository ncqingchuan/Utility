using namespace System.Reflection
using namespace System.Data.Common
using namespace System.Data
function Get-DbConnection {
    param (
        [string]$providerFile,
        [string]$providerName = ("System.Data.SqlClient"),
        [string]$connectionString
    )
    try {
        if (-not [string]::IsNullOrWhiteSpace($ProviderFile)) {
            [Assembly]$assembly = [Assembly]::LoadFrom($ProviderFile)

            if ($PSVersionTable.PSEdition -eq "Core") {
                [type]$type = $assembly.GetTypes() | Where-Object { [DbProviderFactory].IsAssignableFrom($_) } | Select-Object -First 1
            }
            else {
                [type]$type = $assembly.GetExportedTypes() | Where-Object { [DbProviderFactory].IsAssignableFrom($_) } | Select-Object -First 1
            }
            
            if (!$type) {
                throw "not implement DbProviderFactory class"
            }
            [FieldInfo]$fieldInfo = $type.GetField("Instance", [BindingFlags]::Public -bor [BindingFlags]::Static)
            if (!$fieldInfo) {
                throw "this class is not contain 'Instance' static field."
            }
            [DbProviderFactory]$Factory = $fieldInfo.GetValue($null)
        }
        else {
            [DbProviderFactory]$Factory = [DbProviderFactories]::GetFactory($providerName)  
        }        
        $con = $Factory.CreateConnection()
        $con.ConnectionString = $ConnectionString
        $con
    }
    catch {
        throw $_
    }
}

function Get-DbCommand {
    param (
        [System.Data.Common.DbConnection]$conenction,
        [string]$commandText,
        [System.Data.CommandType]$commandType = ([System.Data.CommandType]::Text),
        [psobject[]]$parameters = $null,
        [int]$commandTimeout = 30,
        [System.Data.Common.DbTransaction]$transaction = $null
    )

    $cmd = $Conenction.CreateCommand()
    $cmd.CommandText = $commandText
    $cmd.CommandTimeout = $commandTimeout
    $cmd.CommandType = $commandType
    if ($null -ne $parameters) {
        foreach ($item in $parameters) {
            $param = $cmd.CreateParameter()
            $param.ParameterName = $item.parameterName
            $param.Direction = $item.direction
            $param.IsNullable = $item.isNullable
            $param.Value = $item.value
            $param.Size = $item.size
            $param.Precision = $item.precision
            $param.Scale = $item.scale
            $param.DbType = $item.dbType
            [void]$cmd.Parameters.Add($param)
        }    
    }
    
    $cmd.Transaction = $transaction
    return $cmd
}

function Get-NewParameter {
    <#
    .SYNOPSIS
    创建SQL参数
    
    .DESCRIPTION
    Long description
    
    .PARAMETER parameterName
    参数名称
    
    .PARAMETER direction
    参数方向
    
    .PARAMETER value
    参数值
    
    .PARAMETER dbType
    参数类型
    
    .PARAMETER size
    参数大小
    
    .PARAMETER scale
    参数标量
    
    .PARAMETER precision
    参数精度
    
    .PARAMETER isNullable
    参数是否为空
    
    .EXAMPLE
    Get-NewParameter -parameterName "@p1" -direction Output -dbType DateTime
    
    .NOTES
    General notes
    #>
    param (
        [Parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [string]$parameterName,
        [System.Data.ParameterDirection]$direction = ([System.Data.ParameterDirection]::Input),
        [System.Object]$value = $null,
        [System.Data.DbType]$dbType = ([System.Data.DbType]::Object),
        [int]$size = 50,
        [int]$scale = 0,
        [int]$precision = 0,
        [bool]$isNullable = $true
        
    )
    
    return New-Object psobject -Property ([Ordered]@{ parameterName = $parameterName; direction = $direction; value = $value; size = $size; `
                scale = $scale; precision = $precision; dbType = $dbType ; isNullable = $isNullable 
        })
}


function Get-ExecuteNonQuery {
    param (
        [System.Data.Common.DbConnection]$connection,
        [string]$commandText,
        [System.Data.CommandType]$CommandType = ([System.Data.CommandType]::Text),
        [psobject[]]$parameters = $null,
        [int]$commandTimeout = 30,
        [System.Data.Common.DbTransaction]$transaction = $null,
        [switch]$close
    ) 
    try {
        [System.Data.Common.DbCommand]$cmd = Get-DbCommand -conenction $Connection -commandText $commandText -commandType $commandType `
            -parameters $parameters -commandTimeout $commandTimeout -transaction $transaction
        if ($connection.State -ne [System.Data.ConnectionState]::Open) { $connection.Open() }
        $effect = $cmd.ExecuteNonQuery()
        $effect 
    }
    catch {
        throw $_
    }
    finally {
        foreach ($p in $parameters ) {
            if ($p.direction -in @([System.Data.ParameterDirection]::Output, [System.Data.ParameterDirection]::InputOutput)) {
                $p.Value = $cmd.Parameters[$p.ParameterName].Value
            }            
        }        
        if ($null -ne $connection -and $close) { $connection.Close() }
    }    
}


function Get-ExecuteScalar {
    param (
        [System.Data.Common.DbConnection]$connection,
        [string]$commandText,
        [System.Data.CommandType]$CommandType = ([System.Data.CommandType]::Text),
        [psobject[]]$parameters = $null,
        [int]$commandTimeout = 30,
        [System.Data.Common.DbTransaction]$transaction = $null,
        [switch]$close
    ) 
    try {
        [System.Data.Common.DbCommand]$cmd = Get-DbCommand -conenction $Connection -commandText $commandText -commandType $commandType `
            -parameters $parameters -commandTimeout $commandTimeout -transaction $transaction
        if ($connection.State -ne [System.Data.ConnectionState]::Open) { $connection.Open() }
        $obj = $cmd.ExecuteScalar()
        return $obj
    }
    catch {
        throw $_
    }
    finally {
        foreach ($p in $parameters ) {
            if ($p.direction -in @([System.Data.ParameterDirection]::Output, [System.Data.ParameterDirection]::InputOutput)) {
                $p.value = $cmd.Parameters[$p.ParameterName].Value
            }            
        }     
        if ($null -ne $connection -and $close) { $connection.Close() }
    }    
}

function Get-ExecuteReader {
    param (
        [ValidateNotNull()]
        [Parameter(Mandatory = $true)]
        [System.Data.Common.DbConnection]$connection,
        [ValidateNotNull()]
        [Parameter(Mandatory = $true)]
        [string]$commandText,
        [System.Data.CommandType]$commandType = ([System.Data.CommandType]::Text),
        [psobject[]]$parameters = $null,
        [int]$commandTimeout = 30,
        [System.Data.Common.DbTransaction]$transaction = $null,
        [switch]$close
    )
    $resultList = [Ordered]@{}; $j = 0
    try {
        [System.Data.Common.DbCommand]$cmd = Get-DbCommand -conenction $Connection -commandText $commandText -commandType $commandType `
            -parameters $parameters -commandTimeout $commandTimeout -transaction $transaction
        if ($connection.State -ne [System.Data.ConnectionState]::Open) { $connection.Open() }
        $reader = $cmd.ExecuteReader()
        do {            
            $tempList = @()      
            while ($reader.Read()) {

                $property = [Ordered]@{}

                for ($i = 0; $i -lt $reader.FieldCount; $i++) {
                    $name = $reader.GetName($i)

                    if ([string]::IsNullOrWhiteSpace($name)) {
                        $name = "Column$i"
                    }
                    $property.($name) = $reader.GetValue($i) 
                }
                $tempList += New-Object psobject -Property $property
            }
            $resultList.("List$($j)") = $tempList; $j++           
        } while ($reader.NextResult())
   
        return $resultList 
    }
    catch {
        throw $_
    }
    finally {
        if ($null -ne $reader) {
            $reader.Close()
            foreach ($p in $parameters ) {
                if ($p.direction -in @([System.Data.ParameterDirection]::Output, [System.Data.ParameterDirection]::InputOutput)) {
                    $p.Value = $cmd.Parameters[$p.ParameterName].Value
                }                
            }    
        }
        if ($null -ne $Connection -and $close) { $Connection.Close() }        
    }    
}

function Get-Schema {
    param (
        [ValidateNotNull()]
        [Parameter(Mandatory = $true)]
        [System.Data.Common.DbConnection]$connection,
        [ValidateNotNull()]
        [Parameter(Mandatory = $true)]
        [string]$commandText,
        [System.Data.CommandType]$commandType = ([System.Data.CommandType]::Text),
        [psobject[]]$parameters = $null,
        [int]$commandTimeout = 30,
        [System.Data.Common.DbTransaction]$transaction = $null,
        [switch]$close
    )
    $resultList = [Ordered]@{}; $j = 0
    try {
        [System.Data.Common.DbCommand]$cmd = Get-DbCommand -conenction $Connection -commandText $commandText -commandType $commandType `
            -parameters $parameters -commandTimeout $commandTimeout -transaction $transaction
        if ($connection.State -ne [System.Data.ConnectionState]::Open) { $connection.Open() }
        $reader = $cmd.ExecuteReader([System.Data.CommandBehavior]::SchemaOnly)
        do {
            $table = $reader.GetSchemaTable()
            $tempList = @()      
            foreach ($row in $table.Rows) {
                $properties = [ordered]@{}
                for ($i = 0; $i -lt $table.Columns.Count; $i++) {
                    $properties.($table.Columns[$i]) = $row[$i]
                }
                $tempList += New-Object psobject -Property $properties
            }
            $resultList.("Schema$($j)") = $tempList; $j++           
        } while ($reader.NextResult())
   
        $resultList 
    }
    catch {
        throw $_
    }
    finally {
        if ($null -ne $reader) {
            $reader.Close()
            foreach ($p in $parameters ) {
                if ($p.direction -in @([System.Data.ParameterDirection]::Output, [System.Data.ParameterDirection]::InputOutput)) {
                    $p.Value = $cmd.Parameters[$p.ParameterName].Value
                }                
            }    
        }
        if ($null -ne $Connection -and $close) { $Connection.Close() }        
    }    
}
