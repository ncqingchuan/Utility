using namespace Microsoft.SqlServer.TransactSql.ScriptDom
using namespace System
using namespace System.Collections.Generic
using namespace System.IO
using namespace Management.Automation
using namespace System.Reflection


class ValidationResult {
    [AnalysisCodeResult[]]$AnalysisCodeResults = @()
    [string] $RuleName
    [string] $Descrtiption

    ValidationResult() {
        $this | Add-Member -Name "Validated" -MemberType ScriptProperty -Value {
            ($this.AnalysisCodeResults.Count -eq 0) -or ($this.AnalysisCodeResults | Where-Object {
                    -not $_.$Validated
                }).Count -eq 0
        } -SecondValue {
            throw "The Validated property is readonly."
        }
    }   
}

class AnalysisCodeResult {
    [int]$StartLine
    [int] $EndLine
    [bool]$Validated
    [string]$Text
    [string]$Additional
    [int] $StartColumn
}

class BaseRule:TSqlFragmentVisitor {

    [string]$Descrtiption
    [Severity]$Severity = [Severity]::Information
    hidden [AnalysisCodeResult[]] $AnalysisCodeResults
    hidden [string] $Additional

    BaseRule() {
        $this | Add-Member -Name "RuleName" -MemberType ScriptProperty -Value {
            return  $this.GetType().Name
        } -SecondValue {
            throw "The RuleName property is readonly."
        }
    }

    hidden [void] Validate([TSqlFragment] $node, [bool] $Validated) {
        $AnalysisCodeResult = [AnalysisCodeResult]::new()
        $AnalysisCodeResult.StartLine = $node.StartLine
        $AnalysisCodeResult.EndLine = $node.ScriptTokenStream[$node.LastTokenIndex].Line
        $AnalysisCodeResult.Text = $node.ScriptTokenStream[$node.FirstTokenIndex..$node.LastTokenIndex].Text -join [string]::Empty
        $AnalysisCodeResult.StartColumn = $node.StartColumn
        $AnalysisCodeResult.Additional = $this.Additional
        $this.AnalysisCodeResults += $AnalysisCodeResult
    }

    [void]Validate([CustomParser]$parser) {
        $this.AnalysisCodeResults = @()
        $parser.ValidationResult = [ValidationResult]::new()
        $parser.ValidationResult.RuleName = $this.RuleName
        $parser.ValidationResult.Descrtiption = $this.Descrtiption        
        $parser.Accept($this)
        $parser.ValidationResult.AnalysisCodeResults = $this.AnalysisCodeResults
    }
}

class PDE001: BaseRule {
    PDE001() {
        $this.Descrtiption = "Asterisk in select list."
        $this.Severity = [Severity]::Warning
    }

    [void] Visit([SelectStarExpression] $node) {
        $this.Validate($node, $false)
    }
}

class PDE002 :BaseRule {    
    PDE002() {
        $this.Descrtiption = "Delete or Update statement without Where or INNER JOIN clause."
        $this.Severity = [Severity]::Exception
    }
   
    [void] Visit([UpdateDeleteSpecificationBase] $node) {
        [ChildVisitor]$childVisitor = [ChildVisitor]::new()
        $target = $node.Target

        if ($null -ne $node.WhereClause) { return }

        if ($target -is [VariableTableReference]) { return }
        
        [NamedTableReference] $namedTableReference = $target -as [NamedTableReference]
        $targetTable = $namedTableReference.SchemaObject.BaseIdentifier.Value
        if ($targetTable -imatch "^#{1,2}") { return }

        $fromClause = $node.FromClause
        if ($null -ne $fromClause) {
            $fromClause.AcceptChildren($childVisitor)
            $destTable = $childVisitor.TableAlias | Where-Object { $_.Alias -eq $targetTable } | Select-Object -First 1
            if ($destTable.TableName -imatch "^(@|#{1,2}){1}") { return }
            foreach ($tableReference in $fromClause.TableReferences) {
                if ($tableReference -is [QualifiedJoin]) { return }
            }
        }
        $this.Validate($node, $false)
    }
}

class PDE003:BaseRule {
    PDE003() {
        $this.Descrtiption = "You should use batch operations in statements."
        $this.Severity = [Severity]::Exception
    }

    hidden [int]$start = 0
    hidden [int]$end = 0

    [void] Visit([UpdateDeleteSpecificationBase]$node) {
        [ChildVisitor]$childVisitor = [ChildVisitor]::new()

        $target = $node.Target

        if ($target -is [VariableTableReference]) { return }

        [NamedTableReference] $namedTableReference = $target -as [NamedTableReference]
        $targetTable = $namedTableReference.SchemaObject.BaseIdentifier.Value
        
        if ($targetTable -imatch "^#{1,2}") { return }

        $fromClause = $node.FromClause
        if ($null -ne $fromClause) {
            $fromClause.Accept($childVisitor)
            $destTable = $childVisitor.TableAlias | Where-Object { $_.Alias -eq $targetTable } | Select-Object -First 1
            if ($destTable.TableName -imatch "^(@|#{1,2}){1}") { return }
        }
        $this.CheckWhile($node)
    }

    [void] Visit([InsertSpecification]$node) {
        $target = $node.Target
        if ($target -is [VariableTableReference]) { return }

        $namedTableReference = $target -as [NamedTableReference]
        if ($namedTableReference.SchemaObject.BaseIdentifier.Value -imatch "^#{1,2}") { return }
        $valuesInsertSource = $node.InsertSource -as [ValuesInsertSource]
        if ($null -ne $valuesInsertSource) { return }

        $this.CheckWhile($node)
    }

    [void] Visit([MergeSpecification]$node) {
        $target = $node.Target

        if ($target -is [VariableTableReference]) { return }
        $namedTableReference = $target -as [NamedTableReference]
        if ($namedTableReference.SchemaObject.BaseIdentifier.Value -imatch "^#{1,2}") { return }

        $this.CheckWhile($node)   
    }

    [void] Visit([WhileStatement]$node) {
        $this.start = $node.StartLine
        $this.end = $node.ScriptTokenStream[$node.LastTokenIndex].Line
    }

    hidden [void] CheckWhile([TSqlFragment] $node) {
        if (-not ($node.StartLine -ge $this.start -and $node.ScriptTokenStream[$node.LastTokenIndex].Line -le $this.end)) {            
            $this.Validate($node, $false)
        }
        $this.start = $this.end = 0
    }
}

class PDE004:BaseRule {
    PDE004() {
        $this.Descrtiption = "statement with drop table or drop database clause."
        $this.Severity = [Severity]::Fault
    }

    [void]Visit([DropTableStatement]$node) {       
        if ( ($node.Objects | Where-Object { $_.BaseIdentifier.Value -inotmatch "^#{1,2}" }).Count -gt 0) {
            $this.Validate($node, $false)
        }       
    }

    [void] Visit([DropDatabaseStatement]$node) {
        $this.Validate($node, $false)
    }
}
class PDE005:BaseRule {
    PDE005() {
        $this.Descrtiption = "SELECT statement with INTO clause."
        $this.Severity = [Severity]::Warning
    }

    [void]Visit([SelectStatement]$node) {
        if ($null -ne $node.Into) {
            $this.Validate($node, $false)
        }
    }
}
class ChildVisitor:TSqlFragmentVisitor {    
    $TableAlias = @()
    [void] Visit([NamedTableReference]$node) {
        $tableName = $node.SchemaObject.BaseIdentifier.Value
        $alias = $tableName
        if ($null -ne $node.Alias) {
            $alias = $node.Alias.Value
        }
        $this.TableAlias += [PSCustomObject]([ordered]@{
                TableName = $tableName;
                Alias     = $alias
            })
    }

    [void] Visit([VariableTableReference]$node) {
        $tableName = $node.Variable.Name
        $alias = $tableName
        if ($null -ne $node.Alias) {
            $alias = $node.Alias.Value
        }
        $this.TableAlias += [PSCustomObject]([ordered]@{
                TableName = $tableName;
                Alias     = $alias
            })
    }

}

enum Severity {
    Information = 1
    Warning = 2
    Exception = 3
    Fault = 4
}

enum AnalysisType {
    File = 1
    Code = 2
}
class CustomParser {

    hidden [TSqlParser] $TSqlParser
    hidden [TSqlFragment]$Tree
    hidden [AnalysisType] $AnalysisType
    [ValidationResult] $ValidationResult
    
    CustomParser([SqlVersion]$version, [SqlEngineType]$engineType) {
        switch ($version) {
            [SqlVersion]::Sql120 { $this.TSqlParser = [TSql120Parser]::new($true) }
            [SqlVersion]::Sql130 { $this.TSqlParser = [TSql130Parser]::new($true, $engineType) }
            [SqlVersion]::Sql140 { $this.TSqlParser = [TSql140Parser]::new($true, $engineType) }
            [SqlVersion]::Sql150 { $this.TSqlParser = [TSql150Parser]::new($true, $engineType) }
            Default { $this.TSqlParser = [TSql160Parser]::new($true, $engineType) }
        }

        $this | Add-Member -MemberType ScriptProperty -Name "Batches" -Value {
            [string[]] $results = @()
            if ($null -ne $this.Tree) {
                foreach ($batch in $this.Tree.Batches) {
                    $results += ($batch.ScriptTokenStream[$batch.FirstTokenIndex..$batch.LastTokenIndex].Text -join [string]::Empty)
                }
            }
            return $results
        } -SecondValue {
            throw "The Batches property is readonly."
        }
    }

    hidden [TextReader] GetReader([string] $codeOrFile) {
        [TextReader]$reader = if ([File]::Exists($codeOrFile)) {
            [StreamReader]::new($codeOrFile)
        }
        else {
            [StringReader]::new($codeOrFile)
        }
        return $reader
    }

    [ParseError[]] Parse([string] $codeOrFile) {
        [TextReader]$reader = $null
        [List[ParseError]]$errors = @()
        try {
            $reader = $this.GetReader($codeOrFile)
            $this.Tree = $this.TSqlParser.Parse($reader, [ref] $errors)
            return $errors
        }
        catch {
            throw $_
        }
        finally {
            if ($null -ne $reader) { $reader.Close() }
        }

    }

    [void]Accept([BaseRule]$rule) {
        if ($null -ne $this.Tree) {
            $this.Tree.Accept($rule)
        }
    }

    static  [BaseRule[]] GetAllRules() {
        return [Assembly]::GetAssembly([BaseRule]).GetTypes() | Where-Object { $_ -ne [BaseRule] -and $_.BaseType -eq [BaseRule] } | ForEach-Object { New-Object $_ }
    }
}