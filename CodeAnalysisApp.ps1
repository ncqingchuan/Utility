using module '.\Code Analysis\Rule.psm1'
using namespace Microsoft.SqlServer.TransactSql.ScriptDom
$code = @"
USE DB
GO
Select * from Test;
DELETE A FROM TEST A ;
go
SELECT A INTO RD FROM M;
"@

[CustomParser]$parser = [CustomParser]::new([SqlEngineVersion]::SQL2016, [SqlEngineType]::All)
$parseResult = $parser.Parse($code)
if ($parseResult.ParseError) {
    $parseResult.Errors
}
if (-not $parseResult.ParseError) {
    $result = $parser.Anlysis()
    $result.Rules
}
