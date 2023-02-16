using namespace System.Management.Automation.Runspaces
using namespace System.Management.Automation.Host
class CustomThreadPool {
   
    [RunspacePool] hidden $pool

    CustomThreadPool([int]$minPoolSize, [int] $maxPoolSize, [PSHost] $psHost) {
        if ($minPoolSize -lt 0 -or $maxPoolSize -lt 0 -or ($minPoolSize -lt $maxPoolSize)) {
            throw [System.ArgumentException]::new()
        }
        $this.pool = [runspacefactory]::CreateRunspacePool($minPoolSize, $maxPoolSize, $psHost)
    }

    CustomThreadPool([int]$minPoolSize, [int] $maxPoolSize) {
        if ($minPoolSize -lt 0 -or $maxPoolSize -lt 0 -or ($minPoolSize -lt $maxPoolSize)) {
            throw [System.ArgumentException]::new()
        }
        $this.pool = [runspacefactory]::CreateRunspacePool($minPoolSize, $maxPoolSize)
    }

    [CustomThreadPoolData] BeginInvoke([scriptblock] $script, [HashTable] $parameters) {
        try {

            if ($this.pool.RunspacePoolStateInfo.State -ne [RunspacePoolState]::Opened) {
                $this.pool.Open()
            }

            [powershell]$shell = [powershell]::Create().AddScript($script)
            if ($null -ne $parameters -or $parameters.Count -lt 0 ) { $shell.AddParameters($parameters) }
            $shell.RunspacePool = $this.pool
            return [CustomThreadPoolData]::new($shell, $shell.BeginInvoke())
        }
        catch {
            throw $_
            $this.pool.Close()
        }     

    }

    [System.Object] EndInvoke([CustomThreadPoolData[]] $jobs) {
        $results = @()
        try {
            foreach ($job in $jobs) {
                $results += $job.Shell.EndInvoke($job.AsyncResult)
            }
            return $results
        }
        catch {
            throw $_
        }
        finally {
            $this.pool.Close()
        }
    }

    [void] Close() {
        $this.pool.Close()
    }
}

class CustomThreadPoolData {
   
    [powershell] $Shell
    [System.IAsyncResult] $AsyncResult

    CustomThreadPoolData( [powershell] $Shell, [System.IAsyncResult] $AsyncResult) {
        $this.Shell = $Shell
        $this.AsyncResult = $AsyncResult
    }

}
