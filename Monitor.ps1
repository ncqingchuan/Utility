using namespace System.Threading
param(
    [string] $Path, 
    [int] $Number) 


try {
    Lock-Object $($Path) {
        Add-Content -Path $Path -Value $Number -ErrorAction Stop
    }

}
catch [System.Exception] {
    Write-Host -$_.Exception.Message
}
