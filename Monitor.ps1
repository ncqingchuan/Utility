using namespace System.Threading
param(
    [string] $Path, 
    [int] $Number) 

[bool]$b = $false
try {
    [Monitor]::Enter($Path, [ref] $b)
    Add-Content -Path $Path -Value $Number
}
catch [System.Exception] {
    throw $_
}
finally {
    if ($b -eq $true) {
        [Monitor]::Exit($Path)
    }
}