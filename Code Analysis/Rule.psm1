using namespace Microsoft.SqlServer.TransactSql.ScriptDom
using namespace System
using namespace System.Collections.Generic
using namespace System.IO
using namespace Management.Automation
using namespace System.Reflection

class CustomParser {

    hidden [TSqlParser] $TSqlParser
    hidden [TSqlFragment]$Tree
    $AnalysisCodeSummary = [PSCustomObject]([ordered]@{
            ResponseCode      = [ResponseCode]::Success;
            ResponseMessage   = "Success";
            FileName          = $null;
            DocumentName      = $null;
            Code              = $null;
            IsDocument        = $true;
            ParseErrors       = @();
            ValidationResults = @()
        })

    [bool] $IsDocument
    [string] $FileName
    [string] $Code
    hidden[Object]$lockObj = [Object]::new()
    
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

    [void] Parse() {
        $this.AnalysisCodeSummary.FileName = $this.FileName
        $this.AnalysisCodeSummary.IsDocument = $this.IsDocument 
        $this.AnalysisCodeSummary.DocumentName = [Path]::GetFileName($this.FileName)

        [TextReader]$reader = $null
        [ParseError[]]$errors = @()
        if ($this.IsDocument) {
            $this.Code = Get-Content -Path $this.FileName -Encoding utf8 | Out-String
        }
        $this.AnalysisCodeSummary.Code = $this.Code

        try {
            $reader = [StringReader]::new($this.Code) 
            $this.Tree = $this.TSqlParser.Parse($reader, [ref] $errors)
        }
        catch {
            $this.AnalysisCodeSummary.ResponseCode = [ResponseCode]::Exception
            $this.AnalysisCodeSummary.ResponseMessage = $_.Exception.Message            
            return
        }
        finally {
            if ($null -ne $reader) { $reader.Close() }
        }

        if ($errors.Count -ne 0) {
            $this.AnalysisCodeSummary.ResponseCode = [ResponseCode]::ParseError
            $this.AnalysisCodeSummary.ResponseMessage = "An error occurred while parsing the code."
            $this.AnalysisCodeSummary.ParseErrors = $errors
        }
    }

    [void]Accept([BaseRule]$rule) {
        if ($null -ne $this.Tree) {
            $this.Tree.Accept($rule)
        }
    }

    [void]Validate([BaseRule] $rule) {
        if ( $null -eq $this.Tree ) { return }
        [psobject]$validationResult = [PSCustomObject]([ordered]@{
                ResponseCode        = [ResponseCode]::Success;
                ResponseMessage     = "Success";
                RuleName            = $rule.RuleName;
                Descrtiption        = $rule.Descrtiption;
                Severity            = $rule.Severity;
                Validated           = $true;
                AnalysisCodeResults = @();

            })
        $lockTaken = $false
        try {
            [Threading.Monitor]::Enter($this.lockObj, [ref] $lockTaken)
            $rule.AnalysisCodeResults.Clear()
            $this.Tree.Accept($rule)
            $validationResult.AnalysisCodeResults += $rule.AnalysisCodeResults           
        }
        catch {
            $validationResult.ResponseCode = [ResponseCode]::Exception
            $validationResult.ResponseMessage = $_.Exception.Message
            return
        }
        finally {
            if ($lockTaken) { [Threading.Monitor]::Exit($this.lockObj) }
        }
       
        $validationResult.Validated = ($validationResult.AnalysisCodeResults.Count -eq 0) -or ( $validationResult.AnalysisCodeResults | Where-Object { -not $_.Validated } ).Count -eq 0
        if (-not $validationResult.Validated) {
            $this.AnalysisCodeSummary.ValidationResults += $validationResult
        } 
    }
    
    static  [BaseRule[]] GetAllRules() {
        return [Assembly]::GetAssembly([BaseRule]).GetTypes() | Where-Object { $_ -ne [BaseRule] -and $_.BaseType -eq [BaseRule] } | ForEach-Object { New-Object $_ }
    }
}
class BaseRule:TSqlFragmentVisitor {

    [string]$Descrtiption
    [Severity]$Severity = [Severity]::Information
    $AnalysisCodeResults = @()

    hidden [string] $Additional

    BaseRule() {
        $this | Add-Member -Name "RuleName" -MemberType ScriptProperty -Value {
            return  $this.GetType().Name
        } -SecondValue {
            throw "The RuleName property is readonly."
        }
    }

    hidden [void] Validate([TSqlFragment] $node, [bool] $validated , [string] $addtional) {
        $AnalysisCodeResult = [PSCustomObject]([ordered]@{
                StartLine   = $node.StartLine;
                EndLine     = $node.ScriptTokenStream[$node.LastTokenIndex].Line;
                StartColumn = $node.StartColumn;
                Validated   = $validated;
                Text        = $node.ScriptTokenStream[$node.FirstTokenIndex..$node.LastTokenIndex].Text -join [string]::Empty;
                Additional  = $addtional     
            })
        $this.AnalysisCodeResults += $AnalysisCodeResult
    }
}

class PDE001: BaseRule {
    PDE001() {
        $this.Descrtiption = "Asterisk in select list."
        $this.Severity = [Severity]::Warning
    }

    [void] Visit([SelectStarExpression] $node) {
        $this.Validate($node, $false, $null)
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
        $this.Validate($node, $false, $null)
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
            $this.Validate($node, $false, $null)
        }
    }
}

class PDE004:BaseRule {
    PDE004() {
        $this.Descrtiption = "statement with drop table or drop database clause."
        $this.Severity = [Severity]::Fault
    }

    [void]Visit([DropTableStatement]$node) {       
        if ( ($node.Objects | Where-Object { $_.BaseIdentifier.Value -inotmatch "^#{1,2}" }).Count -gt 0) {
            $this.Validate($node, $false, $null)
        }       
    }

    [void] Visit([DropDatabaseStatement]$node) {
        $this.Validate($node, $false, $null)
    }
}
class PDE005:BaseRule {
    PDE005() {
        $this.Descrtiption = "SELECT statement with INTO clause."
        $this.Severity = [Severity]::Warning
    }

    [void]Visit([SelectStatement]$node) {
        if ($null -ne $node.Into) {
            $this.Validate($node, $false, $null)
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

enum ResponseCode {
    Success = 0
    Exception = 10001
    ParseError = 10002
}
