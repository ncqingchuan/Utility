using module '.\Code Analysis\Rule.psm1'
using namespace Microsoft.SqlServer.TransactSql.ScriptDom

$files = Get-ChildItem -Path "E:\BackupE\QueryFile" -Filter "*.sql" -File
$results = @()
$parserrors = @()
foreach ($file in $files) {
    [CustomParser]$parser = [CustomParser]::new([SqlVersion]::Sql130, [SqlEngineType]::All)
    $parseError = $parser.Parse($file.FullName)
    if ($parseError.Count -gt 0) {
        $parserrors += ($parseError | Select-Object -Property *, @{name = "File"; expression = { $file.FullName } })
    }
    else {
        $ValidationResults = @()
        foreach ($rule in [CustomParser]::GetAllRules()) {
            $rule.Validate($parser)
            if (-not $parser.ValidationResult.Validated) {
                $ValidationResults += $parser.ValidationResult
            }
        }
        $results += [PSCustomObject]@{  File = $file.FullName; ValidationResults = $ValidationResults }
    }
}

$results | Where-Object { $_.ValidationResults.Count -gt 0 } |  ConvertTo-Json -Depth 5