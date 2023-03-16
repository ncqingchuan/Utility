using namespace System.Management.Automation.Runspaces
using namespace System.Management.Automation.Host
using namespace System.Management.Automation
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

    CustomThreadPool([int]$minPoolSize, [int] $maxPoolSize, [CustomInitialSession]$initSession, [PSHost] $psHost) {
        if ($minPoolSize -lt 0 -or $maxPoolSize -lt 0 -or ($minPoolSize -gt $maxPoolSize)) {
            throw "minPoolSize and maxPoolSize must be greater than 0 ,and maxPoolSize must be greater than minPoolSize."
        }
        if ($null -eq $psHost) {
            throw "The value of psHost cannot be null."
        }

        if ($null -eq $initSession) {
            throw "The value of initSession cannot be null."
        }
        $this.pool = [runspacefactory]::CreateRunspacePool($minPoolSize, $maxPoolSize, $initSession.Session, $psHost)
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
            if ($null -ne $shell) { $shell.Dispose() }
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
            if ($null -ne $shell) { $shell.Dispose() }
            $this.Close()                       
            throw $_
        }
    }

    [void] ImportPSModule([string[]]$modules) {
        $this.pool.InitialSessionState.ImportPSModule($modules)
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

    [PSDataCollection[psobject][]] EndInvoke([CustomThreadPoolData[]] $jobs, [scriptblock] $processCallback) {
        $results = @()
        [CustomThreadPoolData]$job = $null
        try {
            foreach ($job in $jobs) {
                $results += $job.Shell.EndInvoke($job.AsyncResult)
                if ($null -ne $processCallback) {
                    . $processCallback
                }
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


class CustomInitialSession {
    [initialsessionstate]  hidden $_session 
    CustomInitialSession () {
        $this._session = [initialsessionstate]::CreateDefault()
        $this | Add-Member -MemberType ScriptProperty -Name 'Session' -Value {
            return $this._session
        }  -SecondValue {
            throw  'This is a readonly property.'
        } -ErrorAction Ignore
    }
    
    [CustomInitialSession]  AddModules([string[]]$modules) {
        $this._session.ImportPSModule($modules)
        return $this
    }

    [CustomInitialSession]  AddVariables([HashTable] $variables) {
        foreach ($key in $variables.Keys) {
            [SessionStateVariableEntry]$entry = [SessionStateVariableEntry]::new($key, $variables.$key, $null)
            $this._session.Variables.Add($entry)
        }
        return $this
    }

    [CustomInitialSession] AddAssemblies([HashTable] $assemblies) {
        foreach ($key in $assemblies.Keys) {
            [SessionStateAssemblyEntry]$entry = [SessionStateAssemblyEntry]::new($key, $assemblies.$key)
            $this._session.Assemblies.Add($entry)
        }
        return $this
    }
}