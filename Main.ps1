using Module .\Thread\CustomThreadPool.psm1

$parameters = @{
    object_id        = 0;
    connectionString = 'Data Source=qingchuan;Initial Catalog=master;UID=sa;PWD=;max pool size=10;';
    debug            = $false
}

$jobs = @()
[CustomThreadPool]$pool = [CustomThreadPool]::new(10, 20, $Host)
1..3000 | ForEach-Object {
    $parameters.objectId = $_
    $jobs += $pool.BeginInvoke( "./example.ps1", $parameters)
}
$pool.EndInvoke($jobs).Data.List0 | Format-Table