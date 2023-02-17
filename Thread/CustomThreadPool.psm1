using namespace System.Management.Automation.Runspaces
using namespace System.Management.Automation.Host
class CustomThreadPool:System.IDisposable {
   
    [RunspacePool] hidden $pool

    CustomThreadPool([int]$minPoolSize, [int] $maxPoolSize, [PSHost] $psHost) {
        if ($minPoolSize -lt 0 -or $maxPoolSize -lt 0 -or ($minPoolSize -gt $maxPoolSize)) {
            throw "minPoolSize and maxPoolSize must be greater than 0 ,and maxPoolSize must be greater than minPoolSize."
        }
        if ($null -eq $psHost) {
            throw "The value of psHost cannot be null."
        }
        $this.pool = [runspacefactory]::CreateRunspacePool($minPoolSize, $maxPoolSize, $psHost)
        $this.pool.Open()
    }

    CustomThreadPool([int]$minPoolSize, [int] $maxPoolSize) {
        if ($minPoolSize -lt 0 -or $maxPoolSize -lt 0 -or ($minPoolSize -gt $maxPoolSize)) {
            throw "minPoolSize and maxPoolSize must be greater than 0 ,and maxPoolSize must be greater than minPoolSize."
        }
        $this.pool = [runspacefactory]::CreateRunspacePool($minPoolSize, $maxPoolSize)
        $this.pool.Open()
    }

    [CustomThreadPoolData] BeginInvoke([scriptblock] $script, [HashTable] $parameters) {
        try {
            [powershell]$shell = [powershell]::Create().AddScript($script)
            if (-not ($null -eq $parameters -or $parameters.Count -eq 0) ) { 
                [void]$shell.AddParameters($parameters) 
            }
            $shell.RunspacePool = $this.pool
            return [CustomThreadPoolData]::new($shell, $shell.BeginInvoke())
        }
        catch {
            $this.Close()
            throw $_
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
            $this.Close()
        }
    }

    [void] hidden Close() {
        $this.pool.Close()
    }

    [void] hidden Dispose() {
        $this.Close()
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
