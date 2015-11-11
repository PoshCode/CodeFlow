function Confirm-RestrictedLanguage {
   param(
      # The scriptblock to test against the restricted language rules
      [Parameter(Mandatory=$True)]
      [ScriptBlock]$Script,
      # Commands to allow
      [String[]]$AllowedCommands,
      # Variables to allow
      [String[]]$AllowedVariables,
      # If set, allows Environment Variables in the scriptblock
      [Switch]$AllowEnvironmentVariables
   )

   $Script.CheckRestrictedLanguage($AllowedCommands, $AllowedVariables, $AllowEnvironmentVariables)
}

function Invoke-Parser {
   param(
      # The script or file path to parse
      [Parameter(Mandatory=$true, ValueFromPipeline=$True, ValueFromPipelineByPropertyName=$True)]
      [Alias("Path","PSPath")]
      $Script
   )
   begin { 
      $ScriptContent = New-Object Text.StringBuilder 
   }
   process {
      $ParseErrors = $null
      $Tokens = $null
      if(Test-Path "$Script" -ErrorAction SilentlyContinue) {
         $Script = Convert-Path $Script
         $AST = [System.Management.Automation.Language.Parser]::ParseFile($Script, [ref]$Tokens, [ref]$ParseErrors)

         New-Object PSObject -Property @{
            Path = $Script
            ParseErrors = $ParseErrors
            Tokens = $Tokens
            AST = $AST
         } | % { $_.PSTypeNames.Insert(0, "System.Management.Automation.Language.ParseResults"); $_ }
      } else {
         $ScriptContent.AppendLine($Script.ToString())
      }
   }
   end {
      $AST = [System.Management.Automation.Language.Parser]::ParseInput($ScriptContent.ToString(), [ref]$Tokens, [ref]$ParseErrors)
      New-Object PSObject -Property @{
         Path = $null
         ParseErrors = $ParseErrors
         Tokens = $Tokens
         AST = $AST
      } | % { $_.PSTypeNames.Insert(0, "System.Management.Automation.Language.ParseResults"); $_ }
   }
}

function Select-Ast { 
   [CmdletBinding(DefaultParameterSetName="FromAST")]
   param(
      # test case (in the original FilterScript format used by Where-Object)
      [Parameter(Position=1)]
      [ScriptBlock]$FilterScript,

      # The AST to search for tokens
      [Parameter(ParameterSetName="FromAST", Mandatory=$True, ValueFromPipeline=$true, ValueFromPipelineByPropertyName= $True, Position=0)]
      [System.Management.Automation.Language.Ast]$AST,

      [Parameter(ParameterSetName="FromScript", Mandatory=$True, ValueFromPipeline=$true, ValueFromPipelineByPropertyName= $True, Position=0)]
      [Alias("Path","PSPath")]
      [string]$Script,

      [Switch]$Recurse,

      [Object[]]$Sort,

      [Switch]$Descending
   )

   process {
      if(!$AST) {
         $Results = Invoke-Parser $Script
         $AST = $Results.AST
         foreach($parseError in $Results.ParseErrors) {
            Write-Error $parseError
         }
      }

      if($Sort) {
         $AST.FindAll({param($ast) Where-Object -Input $ast -FilterScript $FilterScript }, $Recurse) | Sort-Object $Sort -Descending:$Descending
      } else {
         $AST.FindAll({param($ast) Where-Object -Input $ast -FilterScript $FilterScript }, $Recurse)
      }
   }
}
