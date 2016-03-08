#requires -version 3.0
## ResolveAlias Module v2.0
########################################################################################################################
## Version History
## 1.0 - First Version. "It worked on my sample script"
## 1.1 - Now it parses the $(...) blocks inside strings
## 1.2 - Some tweaks to spacing and indenting (I really gotta get some more test case scripts)
## 1.3 - I went back to processing the whole script at once (instead of a line at a time)
##       Processing a line at a time makes it impossible to handle Here-Strings...
##       I'm considering maybe processing the tokens backwards, replacing just the tokens that need it
##       That would mean I could get rid of all the normalizing code, and leave the whitespace as-is
## 1.4 - Now resolves parameters too
## 1.5 - Fixed several bugs with command resolution (the ? => ForEach-Object problem)
##     - Refactored the Resolve-Line filter right out of existence
##     - Created a test script for validation, and 
## 1.6 - Added resolving parameter ALIASES instead of just short-forms
## 1.7 - Minor tweak to make it work in CTP3
## 2.0 - Modularized and v3 compatible
## 2.1 - Added options to Expand-Alias to support generating scripts from your history buffer'
## 2.2 - Update to PowerShell 3  -- add -AllowedModule to Resolve-Command (which)
## 2.3 - Update (for PowerShell 3 only) 
## 2.4 - Update to change "no command ... found in ... allowed modules" warning.
## * *TODO:* Put back the -FullPath option to resolve cmdlets with their snapin path
## * *TODO:* Add an option to put #requires statements at the top for each snapin used
########################################################################################################################
Set-StrictMode -Version latest
function Resolve-Command {
  #.Synopsis
  #   Determine which command is being referred to by the Name
  [CmdletBinding()]
  param( 
    # The name of the command to be resolved
    [Parameter(Mandatory=$true, ValueFromPipeline=$True, ValueFromPipelineByPropertyName=$True)]
    [Alias("Text")]
    [String]$Name, 

    # The name(s) of the modules from which commands are allowed (defaults to modules that are already imported). Pass * to allow any commands.
    [String[]]$AllowedModule=$(@(Microsoft.PowerShell.Core\Get-Module | Select -Expand Name) + 'Microsoft.PowerShell.Core'),

    # A list of commands that are allowed even if they're not in the AllowedModule(s)
    [Parameter()]
    [string[]]$AllowedCommand
  )
  process {
    $Search = $Name -replace '(.)$','[$1]'
    # aliases, functions, cmdlets, scripts, executables, normal files
    $Commands = @(Microsoft.PowerShell.Core\Get-Command $Search -Module $AllowedModule -ErrorAction SilentlyContinue)
    if(!$Commands) {
      if($match = $AllowedCommand -match "^[^-\\]*\\*$([Regex]::Escape($Name))") {
        $OFS = ", "
        Write-Debug "Commands is empty, but AllowedCommand ($AllowedCommand) contains $Name, so:"
        $Commands = @(Microsoft.PowerShell.Core\Get-Command $match)
      }
    }
    $cmd = $null
    
    if($Commands) {
      Write-Debug "Commands $($Commands|% { $_.ModuleName + '\' + $_.Name })"

      if($Commands.Count -gt 1) {
        $cmd = @( $Commands | Where-Object { $_.Name -match "^$([Regex]::Escape($Name))" })[0]
      } else {
        $cmd = $Commands[0]
      }
    }

    if(!$cmd -and !$Search.Contains("-")) {
      $Commands = @(Microsoft.PowerShell.Core\Get-Command "Get-$Search" -ErrorAction SilentlyContinue -Module $AllowedModule | Where-Object { $_.Name -match "^Get-$([Regex]::Escape($Name))" })
      if($Commands) {
        if($Commands.Count -gt 1) {
          $cmd = @( $Commands | Where-Object { $_.Name -match "^$([Regex]::Escape($Name))" })[0]
        } else {
          $cmd = $Commands[0]
        }
      }
    }

    if(!$cmd -or $cmd.CommandType -eq "Alias") {
      if(($FullName = Microsoft.PowerShell.Utility\Get-Alias $Name -ErrorAction SilentlyContinue)) {
        if($FullName = $FullName.ResolvedCommand) {
          $cmd = Resolve-Command $FullName -AllowedModule $AllowedModule -AllowedCommand $AllowedCommand -ErrorAction SilentlyContinue
        }
      }
    }

    if(!$cmd) {
      if($PSBoundParameters.ContainsKey("AllowedModule")) {
        Write-Warning "No command '$Name' found in the allowed modules: $($AllowedModule -join ', ')"
      } else {
        Write-Warning "No command '$Name' found in the allowed modules. Expand-Alias defaults to only loaded modules, specify -AllowedModule `"*`" to allow ANY module. Currently allowed modules: $($AllowedModule -join ', ')"
      }
    }
    return $cmd
  }
}

function Protect-Script {
  #.Synopsis
  #  Expands aliases and validates scripts, preventing embedded script and 
  [CmdletBinding(ConfirmImpact="low",DefaultParameterSetName="Text")]
  param (
    #  The script you want to expand aliases in
    [Parameter(Mandatory=$true, ParameterSetName="Text", Position=0)]
    [Alias("Text")]
    [string]$Script,

    #  A list of modules that are allowed in the scripts we're protecting
    [Parameter(Mandatory=$true)]
    [string[]]$AllowedModule,

    # A list of commands that are allowed even if they're not in the AllowedModule(s)
    [Parameter()]
    [string[]]$AllowedCommand,

    # A list of variables that are allowed even if they're not in the AllowedModule(s)
    [Parameter()]
    [string[]]$AllowedVariable
  )

  $Script = Expand-Alias -Script:$Script -AllowedModule:$AllowedModule -AllowedCommand $AllowedCommand -AllowedVariable $AllowedVariable -WarningVariable ParseWarnings -ErrorVariable ParseErrors -ErrorAction SilentlyContinue
  foreach($e in $ParseErrors | Select-Object -Expand Exception | Select-Object -Expand Errors) {
    Write-Warning $(if($e.Extent.StartLineNumber -eq $e.Extent.EndLineNumber) {
        "{0} (Line {1}, Char {2}-{2})" -f $e.Message, $e.Extent.StartLineNumber, $e.Extent.StartColumnNumber, $e.Extent.EndColumnNumber  
      } else {
        "{0} (l{1},c{2} - l{3},c{4})"  -f $e.Message, $e.Extent.StartLineNumber, $e.Extent.StartColumnNumber, $e.Extent.EndLineNumber, $e.Extent.EndColumnNumber  
      })
  }

  if(![String]::IsNullOrWhiteSpace($Script)) {

    [string[]]$Commands = $AllowedCommand + (Microsoft.PowerShell.Core\Get-Command -Module:$AllowedModule | % { "{0}\{1}" -f $_.ModuleName, $_.Name})
    [string[]]$Variables = $AllowedVariable + (Microsoft.PowerShell.Core\Get-Module $AllowedModule | Select-Object -Expand ExportedVariables | Select-Object -Expand Keys)

    try {
      [ScriptBlock]::Create($Script).CheckRestrictedLanguage($Commands, $Variables, $false)
      return $Script
    } catch [System.Management.Automation.ParseException] {
      $global:ProtectionError = $_.Exception.GetBaseException().Errors

      foreach($e in $ProtectionError) {
        Write-Warning $(if($e.Extent.StartLineNumber -eq $e.Extent.EndLineNumber) {
            "{0} (Line {1}, Char {2}-{2})" -f $e.Message, $e.Extent.StartLineNumber, $e.Extent.StartColumnNumber, $e.Extent.EndColumnNumber  
          } else {
            "{0} (l{1},c{2} - l{3},c{4})"  -f $e.Message, $e.Extent.StartLineNumber, $e.Extent.StartColumnNumber, $e.Extent.EndLineNumber, $e.Extent.EndColumnNumber  
          })
      }
    } catch {
      $global:ProtectionError = $_
      Write-Warning $_      
    }
  }

}

function Expand-Alias {
  #.Synopsis
  #  Expands aliases (optionally adding the fully qualified module name) and short parameters
  #.Description
  #  Expands all aliases (recursively) to actual functions/cmdlets/executables
  #  Expands all short-form parameter names to their full versions
  #  Works on files or strings, and can expand "inplace" on a file
  #.Example
  #  Expand-Alias -Script "gcm help"
  #  
   [CmdletBinding(ConfirmImpact="low",DefaultParameterSetName="Files")]
   param (
      #  The script file you want to expand aliases in
      [Parameter(Position=0, Mandatory=$true, ValueFromPipeline=$true, ParameterSetName="Files")]
      [Alias("FullName","PSChildName","PSPath")]
      [IO.FileInfo]$File,

      #  Enables replacing aliases in-place in files instead of into a new file
      [Parameter(ParameterSetName="Files")] 
      [Switch]$InPlace,

      #  The script you want to expand aliases in
      [Parameter(Mandatory=$true, ValueFromPipeline=$true, ParameterSetName="Text")]
      [Alias("Text")]
      [string]$Script,

      #  The History ID's of commands you want to expand (this supports generating scripts from previous commands, see examples)
      [Parameter(Position=0, Mandatory=$false, ValueFromPipeline=$true, ParameterSetName="History")]
      [Alias("Id")]
      [Int[]]$History,

      #  The count of previous commands (from get-history) to expand (see examples)
      [Parameter(Mandatory=$true, ValueFromPipeline=$true, ParameterSetName="HistoryCount")]
      [Int]$Count,

      #  Allows you to specify a list of modules that are allowed in the scripts we're resolving.
      #  Defaults to the currently loaded modules, but specify "*" to allow ANY module.
      [string[]]$AllowedModule=$(@(Microsoft.PowerShell.Core\Get-Module | Select -Expand Name) + 'Microsoft.PowerShell.Core'),

      # A list of commands that are allowed even if they're not in the AllowedModule(s)
      [Parameter()]
      [string[]]$AllowedCommand,

      # A list of variables that are allowed even if they're not in the AllowedModule(s)
      [Parameter()]
      [string[]]$AllowedVariable,

      #  Allows you to leave the namespace (module name) off of commands
      #  By default Expand-Alias will expand 'gc' to 'Microsoft.PowerShell.Management\Get-Content'
      #  If you specify the Unqualified flag, it will expand to just 'Get-Content' instead.
      [Parameter()]
      [Switch]$Unqualified
   )
   begin {
      Write-Debug $PSCmdlet.ParameterSetName
   }
   process {
      
      switch( $PSCmdlet.ParameterSetName ) {
         "Files" {
            if($File -is [System.IO.FileInfo]){
               $Script = (Get-Content $File -Delim ([char]0))            
            }
         }
         "History" {
            $Script = (Get-History -Id $History | Select-Object -Expand CommandLine) -Join "`n"
         }
         "HistoryCount" {
            $Script = (Get-History -Count $Count | Select-Object -Expand CommandLine) -Join "`n"
         }
         "Text" {}
         default { throw "ParameterSet: $($PSCmdlet.ParameterSetName)" }
      }

      $ParseError = $null
      $Tokens = $null
      $AST = [System.Management.Automation.Language.Parser]::ParseInput($Script, [ref]$Tokens, [ref]$ParseError)
      $Global:Tokens = $Tokens

      if($ParseError) {
         foreach($PEr in $ParseError) { 
            $PSCmdlet.WriteError( 
               (New-Object System.Management.Automation.ErrorRecord (
                  New-Object System.Management.Automation.ParseException $PEr),
                  "Unexpected Exception", "InvalidResult", $_) )
         }
         Write-Warning "There was an error parsing script (See above). We cannot expand aliases until the script parses without errors."
         return
      }
      :token for($t = $Tokens.Count -1; $t -ge 0; $t--) {
         Write-Verbose "Token $t of $($Tokens.Count)"
         $token = $Tokens[$t]
         switch -Regex ($token.Kind) {
            "Generic|Identifier" {
                if($token.TokenFlags -eq 'CommandName') {
                   $OFS = ", "
                   Write-Debug "Resolve-Command -Name $($Token.Text) -AllowedModule $AllowedModule -AllowedCommand @($AllowedCommand)"
                   $Command = Resolve-Command -Name $Token.Text -AllowedModule $AllowedModule -AllowedCommand $AllowedCommand
                   if(!$Command) { return $null }
                   if(!$Unqualified -and $Command.ModuleName) { 
                      $CommandName = '{0}\{1}' -f $Command.ModuleName, $Command.Name
                   } else {
                      $CommandName = $Command.Name
                   }
                   $Script = $Script.Remove( $Token.Extent.StartOffset, ($Token.Extent.EndOffset - $Token.Extent.StartOffset)).Insert( $Token.Extent.StartOffset, $CommandName )
                }
            }
            "Parameter" {
               # Figure out which command they're talking about
               Write-Debug "Parameter: $($Token.Text)"
               # We need to use the AST for this, but ...
               # in the case where a colon instead of a space is used to separate -param:value
               # the token is just -param: but the ast is the -param:value
               $CommandName = $AST.Find( {
                  $args[0].Extent.StartOffset -eq $Token.Extent.StartOffset -and `
                  $args[0] -is [System.Management.Automation.Language.CommandParameterAst] -and `
                  $args[0].Parent -is [System.Management.Automation.Language.CommandAst]
                  }, $true ).Parent.GetCommandName()
               $Command = Resolve-Command -Name $CommandName -AllowedModule $AllowedModule -AllowedCommand $AllowedCommand
               if($Command) {
                  Write-Debug "Command: $CommandName => $($Command.Name)"
               } else { return $null }
            
               $short = "^" + $token.ParameterName
               $parameters = @($Command.ParameterSets | Select-Object -ExpandProperty Parameters | Where-Object {
                                $_.Name -match $short -or $_.Aliases -match $short
                             } | Select-Object -Unique)

               Write-Debug "Parameters: $($parameters | Select -Expand Name)"
               Write-Debug "Parameters: $($Command.ParameterSets | Select-Object -ExpandProperty Parameters | Select -Expand Name) | ? Name -match $short"
               if($parameters.Count -ge 1) {
                  # if("Verbose","Debug","WarningAction","WarningVariable","ErrorAction","ErrorVariable","OutVariable","OutBuffer","WhatIf","Confirm" -contains $parameters[0].Name ) {
                  #    $Script = $Script.Remove( $Token.Extent.StartOffset, ($Token.Extent.EndOffset - $Token.Extent.StartOffset))
                  #    continue
                  # }
                  if($parameters[0].ParameterType -ne [System.Management.Automation.SwitchParameter]) {
                     if($Tokens.Count -ge $t -and ("Parameter","Semi","NewLine" -contains $Tokens[($t+1)].Kind)) {
                        ## $Tokens[($t+1)].Kind -eq "Generic" -and $Tokens[($t+1)].TokenFlags -eq 'CommandName'
                        Write-Warning "No value for parameter: $($parameters[0].Name), the next token is a $($Tokens[($t+1)].Kind) (Flags: $($Tokens[($t+1)].TokenFlags))"
                        $Script = ""
                        break token
                     }
                  }
                  $Replacement = $parameters[0].Name
                  # We need to ensure that if it has ":" instead of space, we preserve that
                  if($Token.Text.EndsWith(":")) { $Replacement += ":" }
                  $Script = $Script.Remove( $Token.Extent.StartOffset, ($Token.Extent.EndOffset - $Token.Extent.StartOffset)).Insert( $Token.Extent.StartOffset, "-$Replacement" )
               } else {
                  Write-Warning "Rejecting Non-Parameter: $($token.ParameterName)"
                  # $Script = $Script.Remove( $Token.Extent.StartOffset, ($Token.Extent.EndOffset - $Token.Extent.StartOffset))
                  $Script = ""
                  break token
               }
               continue
            }
         }
      }


      if($InPlace) {
        if([String]::IsNullOrWhiteSpace($Script)) {
          Write-Warning "Script is empty after Expand-Alias, File ($File) not updated"
        } else {
          Set-Content -Path $File -Value $Script
        }
      } else {
        if([String]::IsNullOrWhiteSpace($Script)) {
          return
        } else {
          return $Script
        }
      }
   }
}


Set-Alias Resolve-Alias Expand-Alias
Export-ModuleMember -Function * -Alias *
