This module is a combination of a few pieces I have written over the years, put together in what will hopefully become a cohesive set :wink:


# The Expander Module

The primary (and most mature part) of this module are the Expander functions:

## Expand-Alias 

Expand aliases and clean up short parameter names.

The unexpected bonus on this command are a whole bunch of  options to filter the commands and modules which are allowed in the resulting scripts (and throw errors if commands from other modules are used).  I added that functionality when I was trying to sanitize user input to a white list of modules/commands in an existing session (i.e. without using contrained endpoints, this lets you create a constrained language filter for script blocks).

## Protect-Script

A wrapper around Expand-Alias to make it easier to use for the purpose of constraining user input script blocks.

## Resolve-Command

A Get-Command wrapper which resolves aliases to the root command and supports whitelists of allowed modules and commands (primarily to support the previous two commands)



# The Parser Module

The simplest part of this module is the Parser module which contains a few commands wrapped around the PowerShell language parser:

## Confirm-RestrictedLanguage

Verifies that a scriptblock is valid in restricted language mode

## Invoke-Parser

Invokes the language parser and returns a _single_ result object which includes the errors, the output Tokens and the AST.

## Select-Ast

Allows returning a filtered subset of the AST for a specific script (e.g. all IF statements).



# The Formatting Module

Currently under development, these are functions for reformatting code to fix indenting etc.  I've just started this, so it's very error prone, and my next task is to write a few test cases for it to fail.

The goal is to use these functions in conjunction with Expand-Alias to clean up functions to a "standard" syntax format.


# The CodeGen Module

I have a few functions lying around for generating module skeletons and templating advanced functions. Those will go here shortly, but this is "future" work, for now.