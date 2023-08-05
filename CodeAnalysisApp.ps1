using module '.\Code Analysis\Rule.psm1'
using namespace Microsoft.SqlServer.TransactSql.ScriptDom

$files = Get-ChildItem -Path "E:\BackupE\QueryFile\delete.sql" -Filter "*.sql" -File
$results = @()
foreach ($file in $files) {
    [CustomParser]$parser = [CustomParser]::new([SqlVersion]::Sql130, [SqlEngineType]::All)
    $parser.FileName = $file.FullName
    $parser.IsDocument = $true  
    $parser.Parse()
    foreach ($rule in [CustomParser]::GetAllRules()) {
        if ($parser.AnalysisCodeSummary.ResponseCode -eq [ResponseCode]::Success) {
            $rule.Validate($parser)
        } 
    }
    $results += $parser.AnalysisCodeSummary
}

$results |ConvertTo-Json -Depth 5
