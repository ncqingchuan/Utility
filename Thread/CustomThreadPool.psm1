using namespace System.Management.Automation.Runspaces
using namespace System.Management.Automation.Host
using namespace System.Management.Automation
class CustomThreadPool:System.IDisposable {
   
    [RunspacePool]  $pool

    CustomThreadPool([int]$minPoolSize, [int] $maxPoolSize, [PSHost] $psHost) {
        if ($minPoolSize -lt 0 -or $maxPoolSize -lt 0 -or ($minPoolSize -gt $maxPoolSize)) {
            throw "minPoolSize and maxPoolSize must be greater than 0 ,and maxPoolSize must be greater than minPoolSize."
        }
        if ($null -eq $psHost) {
            throw "The value of psHost cannot be null."
        }
        [initialsessionstate] $sessionState = [initialsessionstate]::CreateDefault()
        $this.pool = [runspacefactory]::CreateRunspacePool($minPoolSize, $maxPoolSize, $sessionState, $psHost)
        $this.pool.Open()
    }

    [CustomThreadPoolData] BeginInvoke([scriptblock] $script, [HashTable] $parameters) {
        [powershell]$shell = $null
        try {
            $shell = [powershell]::Create().AddScript($script)
            if (-not ($null -eq $parameters -or $parameters.Count -eq 0) ) { 
                [void]$shell.AddParameters($parameters) 
            }
            $shell.RunspacePool = $this.pool
            return [CustomThreadPoolData]::new($shell, $shell.BeginInvoke())
        }
        catch {
            $shell.Dispose()
            $this.Close()
            throw $_
        }
    }

    [CustomThreadPoolData] BeginInvoke([string] $scriptPath, [HashTable] $parameters) {
        [powershell]$shell = $null
        
        try {
            [Command] $cmd = [Command]::new($scriptPath)
            if (-not ($null -eq $parameters -or $parameters.Count -eq 0) ) { 
                foreach ($key in $parameters.Keys) {
                    [void]$cmd.Parameters.Add($key, $parameters.$key)
                }
            }
            $shell = [powershell]::Create()
            $shell.RunspacePool = $this.pool
            $shell.Commands.AddCommand($cmd)
            return [CustomThreadPoolData]::new($shell, $shell.BeginInvoke())
        }
        catch {
            $shell.Dispose() 
            $this.Close()                       
            throw $_
        }
    }

    [void] AddVariables([HashTable] $variables) {
        foreach ($key in $variables.Keys) {
            [SessionStateVariableEntry]$entry = [SessionStateVariableEntry]::new($key, $variables.$key, $null)
            $this.pool.InitialSessionState.Variables.Add($entry)
        }
    }

    [void] ImportPSModules([string[]] $modulesPaths) {
        $this.pool.InitialSessionState.ImportPSModule($modulesPaths)
    }

    [PSDataCollection[psobject][]] EndInvoke([CustomThreadPoolData[]] $jobs) {
        $results = @()
        [CustomThreadPoolData]$job = $null
        try {
            foreach ($job in $jobs) {
                $results += $job.Shell.EndInvoke($job.AsyncResult)
                $job.Shell.Dispose()
            }
            return $results 
        }
        catch {
            $job.Shell.Dispose()
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
