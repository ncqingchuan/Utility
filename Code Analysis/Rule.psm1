using namespace Microsoft.SqlServer.TransactSql.ScriptDom
using namespace System
using namespace System.Collections.Generic
using namespace System.IO
using namespace Management.Automation
using namespace System.Reflection
class BaseRule:TSqlFragmentVisitor {

    [string]$RuleName
    [string]$Descrtiption
    [Severity]$Severity = [Severity]::Information
    $AnalysisResults = @()

    [Object] $Additional = $null
    BaseRule() {
        $this | Add-Member -MemberType ScriptProperty -Name "Validated" -Value {
            return $this.AnalysisResults.Count -eq 0 
        } -SecondValue {
            throw "The Validated property is readonly."
        }
    }

    [void] Validate([TSqlFragment] $node, [bool] $Validated) {
        if ($Validated) { return }

        $text = $node.ScriptTokenStream[$node.FirstTokenIndex..$node.LastTokenIndex].Text -join [string]::Empty
        $endLine = $node.ScriptTokenStream[$node.LastTokenIndex].Line
        $this.AnalysisResults += [PSCustomObject]([ordered]@{
                StartLine   = $node.StartLine;
                StartColumn = $node.StartColumn;
                EndLine     = $endLine;
                Text        = $text;
                Additional  = $this.Additional
            })
    }
}

class PDE001: BaseRule {
    PDE001() {
        $this.RuleName = [PDE001].Name
        $this.Descrtiption = "Asterisk in select list."
        $this.Severity = [Severity]::Warning
    }

    [void] Visit([SelectStarExpression] $node) {
        $this.Validate($node, $false)
    }
}

class PDE002 :BaseRule {    
    PDE002() {
        $this.RuleName = [PDE002].Name
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
        $this.RuleName = [PDE003].Name
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
        $this.Validate($node)
    }

    [void] Visit([InsertSpecification]$node) {
        $target = $node.Target

        $variableTableReference = $target -as [VariableTableReference]
        if ($null -ne $variableTableReference) { return }
        $namedTableReference = $target -as [NamedTableReference]
        if ($namedTableReference.SchemaObject.BaseIdentifier.Value -imatch "^#{1,2}") { return }
        $valuesInsertSource = $node.InsertSource -as [ValuesInsertSource]
        if ($null -ne $valuesInsertSource) { return }

        $this.Validate($node)
    }

    [void] Visit([MergeSpecification]$node) {
        $target = $node.Target

        $variableTableReference = $target -as [VariableTableReference]
        if ($null -ne $variableTableReference) { return }
        $namedTableReference = $target -as [NamedTableReference]
        if ($namedTableReference.SchemaObject.BaseIdentifier.Value -imatch "^#{1,2}") { return }

        $this.Validate($node)   
    }

    [void] Visit([WhileStatement]$node) {
        $this.start = $node.StartLine
        $this.end = $node.ScriptTokenStream[$node.LastTokenIndex].Line
    }
    hidden [void] Validate([TSqlFragment] $node) {
        if (-not ($node.StartLine -ge $this.start -and $node.StartLine -le $this.end)) {            
            $this.Validate($node, $false)
        }
        $this.start = $this.end = 0
    }
}

class PDE004:BaseRule {
    PDE004() {
        $this.RuleName = [PDE004].Name
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
        $this.RuleName = [PDE005].Name
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
enum SqlEngineVersion {
    SQL2014 = 120
    SQL2016 = 130
    SQL2017 = 140
    SQL2019 = 150
    SQL2022 = 160
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
    hidden [string] $File
    hidden [AnalysisType] $AnalysisType
    hidden static [BaseRule[]]$rules = [CustomParser]::GetAllRules()
    
    CustomParser([SqlEngineVersion]$version, [SqlEngineType]$engineType) {
        switch ($version) {
            SQL2014 { $this.TSqlParser = [TSql120Parser]::new($true) }
            SQL2016 { $this.TSqlParser = [TSql130Parser]::new($true, $engineType) }
            SQL2017 { $this.TSqlParser = [TSql140Parser]::new($true, $engineType) }
            SQL2019 { $this.TSqlParser = [TSql150Parser]::new($true, $engineType) }
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
        [TextReader]$reader = $null;
        $this.File = [string]::Empty
        if ([File]::Exists($codeOrFile)) {
            $reader = [StreamReader]::new($codeOrFile)
            $this.File = $codeOrFile
            $this.AnalysisType = [AnalysisType]::File
        }
        else {
            $reader = [StringReader]::new($codeOrFile)
            $this.AnalysisType = [AnalysisType]::Code
        }
        return $reader
    }

    [psobject] Parse([string] $codeOrFile) {
        [TextReader]$reader = $null
        [List[ParseError]]$errors = @()
        try {
            $reader = $this.GetReader($codeOrFile)
            $this.Tree = $this.TSqlParser.Parse($reader, [ref] $errors)
            return [PSCustomObject]([ordered]@{
                    File       = $this.File; 
                    Errors     = $errors; 
                    ParseError = ($errors.Count -gt 0) 
                }
            )
        }
        catch {
            throw $_
        }
        finally {
            if ($null -ne $reader) { $reader.Close() }
        }

    }

    [psobject] Anlysis([BaseRule]$rule) {
        $rule.AnalysisResults = @()
        $this.Tree.Accept($rule)
        return [PSCustomObject]([ordered]@{
                RuleName        = $rule.RuleName;
                Descrtiption    = $rule.Descrtiption;
                Severity        = $rule.Severity;
                Validated       = $rule.Validated;
                AnalysisType    = $this.AnalysisType;
                AnalysisResults = $rule.AnalysisResults
            })
    }

    [psobject] Anlysis() {
        $results = @()        
        foreach ($rule in [CustomParser]::rules) {
            $result = $this.Anlysis($rule)
            if (-not $result.Validated) {
                $results += $result
            }
        }
        return [PSCustomObject]([ordered]@{
                File      = $this.File; 
                Validated = ($results.Count -eq 0 -or ($results | Where-Object { -not $_.Validated }).Count -eq 0); 
                Rules     = $results; 
            })
    }

    hidden static  [BaseRule[]] GetAllRules() {
        return [Assembly]::GetAssembly([BaseRule]).GetTypes() | Where-Object { $_ -ne [BaseRule] -and $_.BaseType -eq [BaseRule] } | ForEach-Object { New-Object $_ }
    }
}