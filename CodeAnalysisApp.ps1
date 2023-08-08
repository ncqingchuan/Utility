using module '.\Code Analysis\Rule.psm1'

$files = Get-ChildItem -Path "E:\BackupE\QueryFile" -Filter "*.sql" -File
$rules = [BaseRule]::GetAllRules()
$result = [CustomParser]::Analysis($files.FullName, $rules)
$result.Where({ $_.ResponseCode -eq [ResponseCode]::Success -and $_.ValidationResults.Where({ -not $_.Validated }).Count -gt 0 }) |`
    Select-Object -Property FileName, DocumentName -ExpandProperty ValidationResults |`
    Select-Object -ExpandProperty AnalysisCodeResults -ExcludeProperty Validated , AnalysisCodeResults