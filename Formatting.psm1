$DefaultFormatOptions = @{
   indent = "  "
   bracesOnNewLine = $False
   blanksBeforeBlocks = $True
}

function Format-BlockAst {   
   #.Synopsis
   #  A script that knows how to format blocks (and nothing else)
   [CmdletBinding()]
   param([string]$Script, $Options = $Script:DefaultFormatOptions)
   end {
      # Normalize empty whitespace
      $newScript = $script = $script -replace "([\r\n]+\s*){2,}",'$1' -replace "^[\r\n\s]*" -replace "[\r\n\s]*$"
      $Index = 0

      do {
         $script = $newScript
         # (Re)parse the script (whenever it changes)
         $AllTokens = Select-Ast $Script {($AST -ne $_) -and ($_.GetType().Name -like "*BlockAst") -and ($_.Parent.Extent.Text -ne $_.Parent.Parent.Extent.Text)} -Sort { $_.Extent.EndOffset }, { $_.Extent.StartOffset } -Descending -Recurse -ErrorAction SilentlyContinue
         # But don't reprocess blocks we've already formatted
         $AstTokens = $AllTokens | Select -Skip $Index

         # Starting at the bottom, reformat 
         while ($AstTokens) {
            $Index++
            $Block, $AstTokens = $AstTokens
            $oldScript = $newScript

            $parent = $block.parent
            $Level = 0
            while($parent) {
               if($parent.GetType().Name -like "*BlockAst") {
                  $Level++
               }
               $lastParent = $parent
               $parent = $parent.parent
            }
            # If the last level is just a plain scriptblock, don't indent for that
            if($lastParent.GetType().Name -eq "ScriptBlockAst" -and $Level -gt 1) { $Level = 0 } else { 
               Write-Host $lastParent.GetType().Name -fore cyan
            }

            Write-Debug "LEVEL: $Level $($block.GetType().Name)`n`t$($block.extent)`n`t$($oldScript.SubString($block.Extent.StartOffset,($block.Extent.EndOffset - $block.Extent.StartOffset)) -replace "[\r\n\s]+"," ")"

            $newScript = $oldScript.Remove( 
               $block.Extent.StartOffset, 
               ($block.Extent.EndOffset - $block.Extent.StartOffset) 
            ).Insert( 
               $block.Extent.StartOffset,
               $(  [regex]::replace(
                     $block.Extent,
                     "^[\r\n\s]*([^{]*?)\s*{\s*((?s).*)\s*}\s*$",
                     {
                        $(if($args.Groups[1].Value) {
                           "`n$($Options.indent * ($level-1))" + 
                           $args.Groups[1].Value + " " # TODO: Options.SpaceBeforeBrace
                        }) +
                        $(if($Options.bracesOnNewLine) { "`n$($Options.indent * ($level-1))" } ) +
                        "{`n" + ($args.Groups[2].Value -replace "(^|[\r\n]+)\s*","`$1$($Options.indent * $level)") +
                        "`n$($Options.indent * ($level-1))}"
                     }, 
                     [System.Text.RegularExpressions.RegexOptions]::MultiLine
                  )
               )
            )
            # Normalize empty whitespace
            $newScript = $newScript -replace "([\r\n]+\s*){2,}",'$1' -replace "^[\r\n\s]*" -replace "[\r\n\s]*$","`n"
            $same = $newScript -eq $oldScript

            # If this "fix" changed the script, we should reparse. 
            # Otherwise, we keep checking each block
            if(!$same) { break }
         } 

         # Write-Debug $Script
         Write-Verbose $NewScript
      } while("$newScript" -ne "$script")
      
      $EnsureSpacing = "FunctionDefinitionAst"
      if($Options.blanksBeforeBlocks) {
         $EnsureSpacing = "NamedBlockAst|FunctionDefinitionAst"
      }

      $lines = $newScript -split "`n"
      $lk = 0
      foreach($block in Select-Ast $newScript { $_.GetType().Name -match $EnsureSpacing } -Recurse | Sort { $_.Extent.StartLineNumber } -Descending -Unique ) {
         Write-Debug "Inject Newline before $($block.Extent)   "
         $line = $block.Extent.StartLineNumber - 1

         $pre = if($line -gt 0) { $lines[0..($line-1)] } else { @() }
         $post = $lines[$line..$lines.Length]

         $blank = "" # <#$(($lk++)) $($block.GetType().Name + ' ' + ($block.Extent -split ' ')[0] + $line)#>"

         $lines = @($pre) + $blank + $post
      }
      $newScript = $lines -join "`n"
   
      $newScript
   }
}


function Format-IfStatement {   
   #.Synopsis
   #  A script that knows how to format blocks (and nothing else)
   [CmdletBinding()]
   param([string]$Script, $Options = $Script:DefaultFormatOptions)
   end {
      # Normalize empty whitespace
      $newScript = $script = $script -replace "([\r\n]+\s*){2,}",'$1' -replace "^[\r\n\s]*" -replace "[\r\n\s]*$"

      do {
         $script = $newScript

         # (Re)parse the script (whenever it changes)
         $AstStack = Select-AST $NewScript { $_ -is [System.Management.Automation.Language.IfStatementAst] } -Sort { $_.Extent.EndOffset } -Descending -Recurse -ErrorAction SilentlyContinue

         # Starting at the bottom, reformat 
         while ($AstStack) {
            $Block, $AstStack = $AstStack
            $oldScript = $newScript

            $parent = $block.parent
            $Level = 0
            while($parent) {
               if($parent.GetType().Name -like "*BlockAst") {
                  Write-Debug ($parent.GetType().Name + " " + ($parent.extent -replace "[\r\n\s]+"," "))
                  $Level++
               }
               $lastParent = $parent
               $parent = $parent.parent
            }
            # If the last level is just a plain scriptblock, don't indent for that
            if($lastParent.GetType().Name -eq "ScriptBlockAst" -and $Level -gt 1) { $Level-- }

            Write-Debug "Level: $Level $($block.GetType().Name)`n`t$($block.extent -replace "[\r\n\s]+"," ")`n`t$($oldScript.SubString($block.Extent.StartOffset,($block.Extent.EndOffset - $block.Extent.StartOffset)) -replace "[\r\n\s]+"," ")"

            $newScript = $oldScript.Remove( 
               $block.Extent.StartOffset, 
               ($block.Extent.EndOffset - $block.Extent.StartOffset) 
            ).Insert( 
               $block.Extent.StartOffset,
               $(  
                  $clauses = $block.clauses
                  $first, $clauses = $clauses
                  $condition = $first.Item1
                  $clause = $first.Item2
                  $clause = [regex]::replace(
                     $clause.Extent, 
                     "^[\r\n\s]*{\s*(.*)\s*}\s*$",
                     {
                        "{`n" + ($args.Groups[1].Value -replace "(^|[\r\n]+)\s*","`$1$($Options.indent * $level)") + "`n$($Options.indent * ($level-1))}"
                     }
                  )

                  "`n$($Options.indent * ($level-1))if ($condition) $clause"
                  
                  while($clauses) {
                     $first, $clauses = $clauses
                     $condition = $first.Item1
                     $clause = $first.Item2
                     $clause = [regex]::replace(
                        $clause.Extent, 
                        "^[\r\n\s]*{\s*(.*)\s*}\s*$",
                        {
                           "{`n" + ($args.Groups[1].Value -replace "(^|[\r\n]+)\s*","`$1$($Options.indent * $level)") + "`n$($Options.indent * ($level-1))}"
                        }
                     )
                     "`n$($Options.indent * ($level-1))elseif ($condition) $clause"
                  }
                  if($block.ElseClause) {
                     $clause = $block.ElseClause
                     $clause = [regex]::replace(
                        $clause.Extent, 
                        "^[\r\n\s]*{\s*(.*)\s*}\s*$",
                        {
                           "{`n" + ($args.Groups[1].Value -replace "(^|[\r\n]+)\s*","`$1$($Options.indent * $level)") + "`n$($Options.indent * ($level-1))}"
                        }
                     )
                     "`n$($Options.indent * ($level-1))else $clause"
                  }
               )
            )
            # reNormalize empty whitespace
            $newScript = $newScript -replace "([\r\n]+\s*){2,}",'$1' -replace "^[\r\n\s]*" -replace "[\r\n\s]*$","`n"
            $same = $newScript -eq $oldScript

            # If this "fix" changed the script, we should reparse. 
            # Otherwise, we keep checking each block
            if(!$same) { break }
         }

         Write-Debug "BEFORE: $Script"
         Write-Verbose "AFTER: $NewScript"
      } while("$newScript" -ne "$script")
      $newScript
   }
}


<# A test:

$code = 'function glue { begin { $s = ""} end { $s; $_ } process { if ( $maybe ) { Write-Output "true"; write-verbose "testing"; } elseif($else) { "otherwise"} else { "false" } } }
function stick { begin { $s = ""} end {
  $s
 $_ }
 process { foreach ($x in gcm) { Write-Output "true"; write-verbose "testing"; } } }'

$code = 'function glue { begin { $s = ""} end { $s; $_ } process { if ( $maybe ) { Write-Output "true"; write-verbose "testing"; } elseif($else) { "otherwise"} else { "false" } } }'
$r1 = Format-IfStatement (Format-BlockAst $code)
$r2 = Format-BlockAst (Format-IfStatement $code)

if($r1 -eq $r2) { 
   Write-Host "TEST PASS" -Back DarkGreen -Fore White
} else { 
   Write-Host "TEST FAIL" -Back DarkRed -Fore White
   Write-Host $r1 -fore cyan
   Write-Host $r2 -fore yellow
}

#>