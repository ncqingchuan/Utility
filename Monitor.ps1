using namespace System.Threading
param(
    [string] $Path, 
    [int] $Number) 

[bool]$lockTaken = $false
try {
    [Monitor]::Enter($Path, [ref] $lockTaken)
    Add-Content -Path $Path -Value $Number
}
catch [System.Exception] {
    throw $_
}
finally {
    if ($lockTaken -eq $true) {
        [Monitor]::Exit($Path)
    }
}