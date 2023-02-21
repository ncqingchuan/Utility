using Module .\Thread\CustomThreadPool.psm1

$path = "$($PSScriptRoot)\result.txt"

$parameters = @{
    Path   = $path;
    Number = 0
}

$jobs = @()
[CustomThreadPool]$pool = [CustomThreadPool]::new(5, 10, $Host)


1..10 | ForEach-Object {
    $parameters.Number = $_
    $jobs += $pool.BeginInvoke( "$($PSScriptRoot)\Monitor.ps1", $parameters)
}
$pool.EndInvoke($jobs)
