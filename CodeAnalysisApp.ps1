using module '.\Code Analysis\Rule.psm1'
using namespace Microsoft.SqlServer.TransactSql.ScriptDom

$files = Get-ChildItem -Path "E:\BackupE\QueryFile" -Filter "*.sql" -File
$results = @()
foreach ($file in $files) {
    [CustomParser]$parser = [CustomParser]::new([SqlVersion]::Sql130, [SqlEngineType]::Standalone)
    $parser.FileName = $file.FullName
    $parser.IsDocument = $true  
    $parser.Parse()
    foreach ($rule in [CustomParser]::GetAllRules()) {
        if ($parser.AnalysisCodeSummary.ResponseCode -eq [ResponseCode]::Success) { $parser.Validate($rule) } 
    }
    $results += $parser.AnalysisCodeSummary
}

$report = $results | Where-Object { $_.ResponseCode -eq [ResponseCode]::ParseError -or ($_.validationResults | Where-Object { -not $_.Validated }).Count -gt 0 }
$report | Select-Object  -Property  FileName, DocumentName -ExpandProperty ValidationResults 

