# omz-git runner. Every alias defined by omz-git.ps1 (gco, gcmsg, gp, ...) points at this file.
#
# Running git from a *script* is what lets git's exit code reach the caller: a script that ends
# with `exit N` (N -ne 0) sets $? to $false, so `gaa && gcmsg 'x' && gp` stops at the first
# failure like it does in zsh. A PowerShell function can't do that.

$global:LASTEXITCODE = 0
$name = Get-OmzGitAliasName $MyInvocation

# `$obj | gm`, `ls *.log | gc`, `ls | gp` keep their PowerShell meaning: git never reads the pipeline.
if ($MyInvocation.ExpectingInput -and $global:OmzGitPipelineFallback.Contains($name)) {
    $input | & $global:OmzGitPipelineFallback[$name] @args
    exit 0
}

Invoke-OmzGitAlias -Name $name -Invocation $MyInvocation -ArgumentList $args
exit $global:LASTEXITCODE
