using module '.\Code Analysis\Rule.psm1'
using namespace Microsoft.SqlServer.TransactSql.ScriptDom

$files = Get-ChildItem -Path "E:\BackupE\QueryFile" -Filter "*.sql" -File
$rules = [BaseRule]::GetAllRules()
$results = [CustomParser]::Analysis($files, $rules)
$report = $results | Where-Object { $_.ResponseCode -eq [ResponseCode]::Success -and ($_.validationResults | Where-Object { -not $_.Validated }).Count -ne 0 }
$report | Select-Object  -Property  FileName, DocumentName -ExpandProperty ValidationResults