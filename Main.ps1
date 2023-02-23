using Module .\Thread\CustomThreadPool.psm1

$scriptPath = "$($PSScriptRoot)\DataBase.ps1"
$modules = "$($PSScriptRoot)/Thread/LockObject.psm1", "$($PSScriptRoot)\Data\Datasource.psm1"
$parameters = @{
    debug    = $false;
    objectId = 0
}

$jobs = @()
[CustomInitialSession]$session = [CustomInitialSession]::new()
$session = $session.AddModules($modules)
[CustomThreadPool]$pool = [CustomThreadPool]::new(5, 10, $session.Session, $Host)

1..30 | ForEach-Object {
    $parameters.objectId = $_
    $jobs += $pool.BeginInvoke( $scriptPath, $parameters)
}
$pool.EndInvoke($jobs).Data.List0
