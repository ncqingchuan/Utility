using Module .\Thread\CustomThreadPool.psm1

$path = "$($PSScriptRoot)/TestReult/result.txt"
$module = "$($PSScriptRoot)/Thread/LockObject.psm1"
$parameters = @{
    Path   = $path;
    Number = 0
}

$jobs = @()

[initialsessionstate]$session = [CustomInitialSession]::ImportPSModule($module)
# $session = [CustomInitialSession]::AddVariables(@{P1 = 123 })
[CustomThreadPool]$pool = [CustomThreadPool]::new(5, 10, $session, $Host)

1..100 | ForEach-Object {
    $parameters.Number = $_
    $jobs += $pool.BeginInvoke( "$($PSScriptRoot)\Monitor.ps1", $parameters)
}
$pool.EndInvoke($jobs, { Write-Host "#" -NoNewline })
Write-Host "`r`nEND"
