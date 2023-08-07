using module '.\Code Analysis\Rule.psm1'

$files = Get-ChildItem -Path "E:\BackupE\QueryFile\delete.sql" -Filter "*.sql" -File
$rules = [BaseRule]::GetAllRules()
$result = [CustomParser]::Analysis($files.FullName, $rules)
