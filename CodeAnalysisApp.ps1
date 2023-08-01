using module '.\Code Analysis\Rule.psm1'
using namespace Microsoft.SqlServer.TransactSql.ScriptDom

$files = Get-ChildItem -Path E:\BackupE\QueryFile -Filter "*.sql"
$results = @()
foreach ($file in $files) {
    [CustomParser]$parser = [CustomParser]::new([SqlVersion]::Sql130, [SqlEngineType]::All)
    $parser.Parse($file.FullName) = $null;
    foreach ($rule in [CustomParser]::GetAllRules()) {
        $rule.Validate($parser)
        if (-not $parser.ValidationResult.Validated) {
            $results += (  $parser.ValidationResult | Select-Object -Property *, @{name = "File"; expression = { $file.FullName } })
        }
    }
}

