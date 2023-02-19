using Module .\Thread\CustomThreadPool.psm1

$parameters = @{
    debug     = $true;
    object_id = 0;
}

$jobs = @()
[CustomThreadPool]$pool = [CustomThreadPool]::new(5, 10, $Host)
1..10 | ForEach-Object {
    $parameters.objectId = $_
    $jobs += $pool.BeginInvoke( "./example.ps1", $parameters)
}
$pool.EndInvoke($jobs).List0