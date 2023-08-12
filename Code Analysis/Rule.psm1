using namespace Microsoft.SqlServer.TransactSql.ScriptDom
using namespace System
using namespace System.Collections.Generic
using namespace System.IO
using namespace Management.Automation
using namespace System.Reflection

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
    }

    hidden [void]Validate([BaseRule] $rule, [bool]$lockRule) {
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
            if ($lockRule) { [Threading.Monitor]::Enter($rule.AnalysisCodeResults, [ref] $lockTaken) }
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
            if ($lockTaken) { [Threading.Monitor]::Exit($rule.AnalysisCodeResults) }
            $validationResult.Validated = $validationResult.ResponseCode -eq [ResponseCode]::Success `
                -and (( $validationResult.AnalysisCodeResults | Where-Object { -not $_.Validated } ).Count -eq 0)
                
            if (-not $validationResult.Validated) {
                $this.AnalysisCodeSummary.ValidationResults += $validationResult
            }        
        }
    }

    static [psobject] Analysis([string]$codeOrFile, [bool]$isDocumnet, [BaseRule[]]$rules) {
        [CustomParser]$parser = [CustomParser]::new([SqlVersion]::Sql130, [SqlEngineType]::All)
        if (-not $isDocumnet) { $parser.Code = $codeOrFile }else { $parser.FileName = $codeOrFile }
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
        foreach ($file in $files) { $result += [CustomParser]::Analysis($file, $true, $rules) }
        return $result
    }
}
class BaseRule:TSqlFragmentVisitor {

    [string]$Descrtiption
    [Severity]$Severity = [Severity]::Information
    $AnalysisCodeResults = @()
    [string]$RuleName = $this.GetType().Name
    hidden [string] $Additional

    hidden [void] Validate([TSqlFragment] $node, [bool] $validated , [string] $addtional) {
        $this.AnalysisCodeResults += [BaseRule]::GetAnalysisResult($node, $validated, $addtional)
    }

    static  [BaseRule[]] GetAllRules() {
        return [Assembly]::GetAssembly([BaseRule]).GetTypes() `
        | Where-Object { $_ -ne [BaseRule] -and $_.BaseType -eq [BaseRule] } `
        | ForEach-Object { New-Object $_ }
    }

    static [psobject] GetAnalysisResult([TSqlFragment] $node, [bool] $validated , [string] $addtional) {
        return [PSCustomObject]([ordered]@{
                StartLine   = $node.StartLine;
                EndLine     = if ($node.LastTokenIndex -gt 0) { $node.ScriptTokenStream[$node.LastTokenIndex].Line } else { $node.LastTokenIndex }
                StartColumn = $node.StartColumn;
                Validated   = $validated;
                Text        = if ($node.FragmentLength -gt 0) `
                { $node.ScriptTokenStream[$node.FirstTokenIndex..$node.LastTokenIndex].Text -join [string]::Empty } `
                    else { $null }
                Additional  = $addtional     
            })
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

        $target = $node.Target
        if ($null -ne $node.WhereClause) { return }

        if ($target -is [VariableTableReference]) { return }
        
        [NamedTableReference] $namedTableReference = $target -as [NamedTableReference]
        $targetTable = $namedTableReference.SchemaObject.BaseIdentifier.Value
        if ($targetTable -imatch "^#{1,2}") { return }

        $fromClause = $node.FromClause
        if ($null -ne $fromClause) {
            [TemporaryTableVisitor] $tempVisitor = [TemporaryTableVisitor]::new($fromClause, $targetTable)
            $fromClause.AcceptChildren($tempVisitor)
            if ($tempVisitor.Validated) { return }
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
        $target = $node.Target

        if ($target -is [VariableTableReference]) { return }
        if ($this.CheckWhile($node)) { return }
        [NamedTableReference] $namedTableReference = $target -as [NamedTableReference]
        $targetTable = $namedTableReference.SchemaObject.BaseIdentifier.Value
        
        if ($targetTable -imatch "^#{1,2}") { return }

        $fromClause = $node.FromClause
        if ($null -ne $fromClause) {
            [TemporaryTableVisitor]$tempVisitor = [TemporaryTableVisitor]::new($fromClause, $targetTable)
            $fromClause.AcceptChildren($tempVisitor)
            if ($tempVisitor.Validated) { return }
        }
        $this.Validate($node, $false, $null)
    }

    [void] Visit([InsertSpecification]$node) {
        $target = $node.Target
        if ($target -is [VariableTableReference]) { return }
        if ($this.CheckWhile($node)) { return }
        $namedTableReference = $target -as [NamedTableReference]
        if ($namedTableReference.SchemaObject.BaseIdentifier.Value -imatch "^#{1,2}") { return }
        $valuesInsertSource = $node.InsertSource -as [ValuesInsertSource]
        if ($null -ne $valuesInsertSource) { return }

        $this.Validate($node, $false, $null)
    }

    [void] Visit([MergeSpecification]$node) {
        $target = $node.Target
        if ( $this.CheckWhile($node)) { return }
        if ($target -is [VariableTableReference]) { return }
        $namedTableReference = $target -as [NamedTableReference]
        if ($namedTableReference.SchemaObject.BaseIdentifier.Value -imatch "^#{1,2}") { return }
        $this.Validate($node, $false, $null)
        
    }

    [void] Visit([WhileStatement]$node) {
        $this.start = $node.StartLine
        $this.end = $node.ScriptTokenStream[$node.LastTokenIndex].Line
    }

    hidden [bool] CheckWhile([TSqlFragment] $node) {
        return $node.StartLine -ge $this.start -and $node.ScriptTokenStream[$node.LastTokenIndex].Line -le $this.end
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
            $this.Validate($node.Into, $false, $null)
        }
    }
}
class TemporaryTableVisitor:TSqlFragmentVisitor {

    [bool]$Validated = $false
    hidden [string] $pattern = "^(@|#{1,2})"
    hidden [FromClause]$fromClause
    hidden [string]$target

    TemporaryTableVisitor([FromClause]$fromClause, [string]$target) {
        $this.fromClause = $fromClause
        $this.target = $target
        if ($null -eq $fromClause) { $this.Validated = $true }
    }

    [void] Visit([NamedTableReference]$node) {
        $tableName = $node.SchemaObject.BaseIdentifier.Value
        $alias = $node.Alias.Value
        if ($this.target -in $alias, $tableName) {
            $this.Validated = $this.Validated -or ($tableName -imatch $this.pattern)
        }  
    }

    [void] Visit([VariableTableReference]$node) {
        $tableName = $node.Variable.Name
        $alias = $node.Alias.Value
        if ($this.target -in $alias, $tableName) {
            $this.Validated = $this.Validated -or ($tableName -imatch $this.pattern)
        }  
    }
}


