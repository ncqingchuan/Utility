using namespace Microsoft.SqlServer.TransactSql.ScriptDom
using namespace System
using namespace System.Collections.Generic
using namespace System.IO
using namespace Management.Automation
using namespace System.Reflection

class CustomParser {

    hidden [TSqlParser] $TSqlParser
    hidden [TSqlFragment]$Tree
    hidden $AnalysisCodeSummary = [PSCustomObject]([ordered]@{
            ResponseCode      = [ResponseCode]::Success;
            ResponseMessage   = "Success";
            FileName          = $null;
            DocumentName      = $null;
            Code              = $null;
            IsDocument        = $true;
            ParseErrors       = [List[ParseError]]::new();
            ValidationResults = [List[psobject]]::new();
            Batches           = [string[]]@()
        })

    hidden [bool] $IsDocument
    hidden [string] $FileName
    hidden [string] $Code


    hidden CustomParser([SqlVersion]$version, [SqlEngineType]$engineType) {
        switch ($version) {
            [SqlVersion]::Sql120 { $this.TSqlParser = [TSql120Parser]::new($true) }
            [SqlVersion]::Sql130 { $this.TSqlParser = [TSql130Parser]::new($true, $engineType) }
            [SqlVersion]::Sql140 { $this.TSqlParser = [TSql140Parser]::new($true, $engineType) }
            [SqlVersion]::Sql150 { $this.TSqlParser = [TSql150Parser]::new($true, $engineType) }
            Default { $this.TSqlParser = [TSql160Parser]::new($true, $engineType) }
        }
    }

    hidden [void] Parse() {
        $this.AnalysisCodeSummary.FileName = $this.FileName
        $this.AnalysisCodeSummary.IsDocument = $this.IsDocument 
        $this.AnalysisCodeSummary.DocumentName = [Path]::GetFileName($this.FileName)

        [StringReader]$reader = $null
        [ParseError[]]$errors = @()      

        try {
            if ($this.IsDocument) { $this.Code = [File]::ReadAllText($this.FileName) }
            $this.AnalysisCodeSummary.Code = $this.Code
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

        if ($null -ne $this.Tree) {
            foreach ($batch in $this.Tree.Batches) {
                $this.AnalysisCodeSummary.Batches += ($batch.ScriptTokenStream[$batch.FirstTokenIndex..$batch.LastTokenIndex].Text -join [string]::Empty)
            }
        }
    }

    hidden [void]Validate([BaseRule] $rule, [bool]$locked) {
        [psobject]$validationResult = [PSCustomObject]([ordered]@{
                ResponseCode        = [ResponseCode]::Success;
                ResponseMessage     = "Success";
                RuleName            = $rule.RuleName;
                Descrtiption        = $rule.Descrtiption;
                Severity            = $rule.Severity;
                Validated           = $true;
                AnalysisCodeResults = [List[psobject]]::new();
            })
        $lockTaken = $false
        try {
            if ($locked) { [Threading.Monitor]::Enter($rule, [ref] $lockTaken) }
            $rule.AnalysisCodeResults = @()
            $this.Tree.Accept($rule)
            $validationResult.AnalysisCodeResults += $rule.AnalysisCodeResults
        }
        catch {
            $validationResult.ResponseCode = [ResponseCode]::Exception
            $validationResult.ResponseMessage = $_.Exception.Message
            return
        }
        finally {
            if ($lockTaken) { [Threading.Monitor]::Exit($rule) }
            $validationResult.Validated = $validationResult.ResponseCode -eq [ResponseCode]::Success `
                -and (( $validationResult.AnalysisCodeResults | Where-Object { -not $_.Validated } ).Count -eq 0)
                
            if (-not $validationResult.Validated) {
                $this.AnalysisCodeSummary.ValidationResults += $validationResult
            }        
        }
    }

    static [psobject] Analysis([string]$codeOrFile, [bool]$isDocumnet, [BaseRule[]]$rules) {
        [CustomParser]$parser = [CustomParser]::new([SqlVersion]::Sql130, [SqlEngineType]::All)
        $parser.Code = if (-not $isDocumnet) { $codeOrFile }else { $null }
        $parser.FileName = if ($isDocumnet) { $codeOrFile }else { $null }
        $parser.IsDocument = $isDocumnet
        $parser.Parse()
        if ($parser.AnalysisCodeSummary.ResponseCode -eq [ResponseCode]::Success) {
            foreach ($rule in $rules) {
                $parser.Validate($rule, $false)
            }
        }
        return $parser.AnalysisCodeSummary
    }

    static [psobject[]] Analysis([string[]]$files, [BaseRule[]]$rules) {
        $result = @()
        foreach ($file in $files) {
            $result += [CustomParser]::Analysis($file, $true, $rules)
        }
        return $result
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

    static  [BaseRule[]] GetAllRules() {
        return [Assembly]::GetAssembly([BaseRule]).GetTypes() | Where-Object { $_ -ne [BaseRule] -and $_.BaseType -eq [BaseRule] } | ForEach-Object { New-Object $_ }
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
