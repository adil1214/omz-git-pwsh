# Rebuilds the command tables in README.md (between the commands:start and commands:end
# markers) from omz-git.ps1, so the list always matches the code.
#
#   pwsh -NoProfile -File tools\Update-Readme.ps1          rewrite README.md
#   pwsh -NoProfile -File tools\Update-Readme.ps1 -Check   exit 1 if README.md is out of date

param([switch]$Check)

$root = Split-Path $PSScriptRoot -Parent
$readme = Join-Path $root 'README.md'
. (Join-Path $root 'omz-git.ps1') 6> $null

# README sections, in order, and the git subcommands that go in each.
$sections = [ordered]@{
    'Add, apply, am'         = 'add', 'apply', 'am'
    'Bisect and blame'       = 'bisect', 'blame'
    'Branch'                 = 'branch'
    'Checkout and switch'    = 'checkout', 'switch'
    'Cherry-pick and revert' = 'cherry-pick', 'revert'
    'Clean and clone'        = 'clean', 'clone'
    'Commit'                 = 'commit'
    'Diff'                   = 'diff', 'diff-tree'
    'Fetch and pull'         = 'fetch', 'pull'
    'Log and history'        = 'log', 'shortlog', 'reflog', 'describe'
    'Merge'                  = 'merge', 'mergetool'
    'Push'                   = 'push'
    'Rebase'                 = 'rebase'
    'Remote'                 = 'remote'
    'Reset, restore, rm'     = 'reset', 'restore', 'rm'
    'Show and status'        = 'show', 'status'
    'Stash'                  = 'stash'
    'Submodule'              = 'submodule'
    'Tag'                    = 'tag'
    'Tracked files'          = 'ls-files', 'update-index'
    'Worktree'               = 'worktree'
    'Config, help, GUI'      = 'config', 'help', 'gui'
    'Other'                  = @()
}
# Aliases whose description doesn't start with "git <subcommand>".
$sectionOf = @{ gbcopy = 'branch' }

$notes = @{
    gc       = 'Replaces PowerShell''s `gc` (Get-Content); piping into it still runs Get-Content.'
    gl       = 'Replaces PowerShell''s `gl` (Get-Location).'
    gm       = 'Replaces PowerShell''s `gm` (Get-Member); `$x | gm` still runs Get-Member.'
    gp       = 'Replaces PowerShell''s `gp` (Get-ItemProperty); piping into it still runs Get-ItemProperty.'
    gcb      = 'Replaces PowerShell''s `gcb` (Get-Clipboard).'
    'gbd!'   = 'omz `gbD`'
    'gcb!'   = 'omz `gcB`'
    'gbgd!'  = 'omz `gbgD`'
    gdv      = 'omz pipes this into `view -`; here it uses git''s pager.'
    gdup     = 'Saves you quoting `''@{upstream}''` in PowerShell.'
    gtv      = 'Same order as omz''s `git tag | sort -V`.'
    gcount   = 'Adds `HEAD` when you give no revision, so it never waits on stdin.'
}

# The two long --pretty formats get short names in the tables.
$lol = $OmzGitSpec['glol'].Git[2]
$lolDate = $OmzGitSpec['glod'].Git[2]

function ConvertTo-Cell([string]$Text) { $Text -replace '\|', '\|' }

$rows = @{}
foreach ($name in $sections.Keys) { $rows[$name] = [System.Collections.Generic.List[string]]::new() }
foreach ($spec in $OmzGitSpec.Values) {
    $subcommand = if ($sectionOf[$spec.Name]) { $sectionOf[$spec.Name] } elseif ($spec.Runs -match '^git ([a-z-]+)') { $Matches[1] } else { '' }
    $section = @($sections.Keys | Where-Object { $sections[$_] -contains $subcommand })[0]
    if (-not $section) { $section = 'Other' }

    $runs = if ($spec.Usage -and -not $spec.Function) { "$($spec.Runs) $($spec.Usage)" } else { $spec.Runs }
    $runs = $runs.Replace($lol, '--pretty=<lol>').Replace($lolDate, '--pretty=<lol-date>')
    $note = $notes[$spec.Name]
    if ($spec.Message) { $note = 'The words you type (up to the first `-option`) become the message.' }
    $rows[$section].Add("| ``$($spec.Name)`` | ``$(ConvertTo-Cell $runs)`` | $(ConvertTo-Cell $note) |")
}

$out = [System.Collections.Generic.List[string]]::new()
$out.Add("$($OmzGitSpec.Count) aliases. ``<branch>`` is the current branch, ``<main>`` and ``<develop>`` the detected main and develop branches (see [Branch placeholders](#branch-placeholders)). Anything you type after an alias is passed on to git.")
foreach ($name in $sections.Keys) {
    if (-not $rows[$name].Count) { continue }
    $out.Add('')
    $out.Add("### $name")
    $out.Add('')
    $out.Add('| Alias | Runs | Notes |')
    $out.Add('|---|---|---|')
    $out.AddRange($rows[$name])
    if ($name -eq 'Log and history') {
        $out.Add('')
        $out.Add("``<lol>`` is ``$($lol.Substring(9))``; ``<lol-date>`` is the same with ``%ad`` (author date) instead of ``%ar``.")
    }
}

$text = [IO.File]::ReadAllText($readme)
$newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
$start = '<!-- commands:start -->'
$end = '<!-- commands:end -->'
$from = $text.IndexOf($start)
$to = $text.IndexOf($end)
if ($from -lt 0 -or $to -lt $from) { throw "README.md needs the $start and $end markers" }
$updated = $text.Substring(0, $from + $start.Length) + $newline + ($out -join $newline) + $newline + $text.Substring($to)

if ($Check) {
    if ($updated -ne $text) { Write-Host 'README.md is out of date: run tools\Update-Readme.ps1' -ForegroundColor Yellow; exit 1 }
    Write-Host 'README.md is up to date' -ForegroundColor Green
    exit 0
}
[IO.File]::WriteAllText($readme, $updated)
Write-Host "README.md: $($OmzGitSpec.Count) aliases written" -ForegroundColor Green
