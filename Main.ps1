using Module .\Thread\CustomThreadPool.psm1

$scriptPath = "$($PSScriptRoot)\DataBase.ps1"

$parameters = @{
    objectId         = 0;
    lock             = "$($PSScriptRoot)\TestResult\log.txt";
    connectionString = 'Data Source=qingchuan;Initial Catalog=HighwaveDw;Integrated Security=true'
}

$modules = "$($PSScriptRoot)\Thread\LockObject.psm1", "$($PSScriptRoot)\Data\Datasource.psm1"

[CustomInitialSession]$session = [CustomInitialSession]::new()
$session = $session.AddModules($modules)
[CustomThreadPool]$pool = [CustomThreadPool]::new(10, 15, $session, $Host)

$jobs = @()
1..100 | ForEach-Object {
    $parameters.objectId = $_
    $jobs += $pool.BeginInvoke( $scriptPath, $parameters)
}
$pool.EndInvoke($jobs)

