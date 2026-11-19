# =============================================================================
# omz-git.ps1 - the oh-my-zsh "git" plugin for PowerShell 7
#   https://github.com/ohmyzsh/ohmyzsh/blob/master/plugins/git/git.plugin.zsh
#
# Dot-source it from your profile: see INSTALL.md (plain profile or Chris Titus profile).
# Everything is declared global, so it also works when loaded from a child scope (the Chris
# Titus profile runs CTTcustom.ps1 with &). Tests: pwsh -NoProfile -File omz-git.tests.ps1
#
#   galias [text]   list the aliases, filtered by any part of the name or the command
#
# How it works
#   * Every alias is a PowerShell *alias* pointing at omz-git-run.ps1. Running git from a script
#     (a function can't do this) lets git's exit code reach $?, so `gaa && gcmsg 'x' && gp`
#     stops at the first failure like in zsh.
#   * Plain aliases are data ($aliases below). <main>, <develop> and <branch> are filled in when
#     the alias runs. An expansion ending in --message takes the message from the words you type:
#     gcmsg fix login bug --no-verify
#   * Aliases that need logic are OmzGit_<name> functions ($custom below).
#   * Tab completion offers branches, tags and changed files that *contain* what you typed.
#
# Differences from omz, all forced by PowerShell:
#   * Names are case-insensitive: gbD -> gbd!, gcB -> gcb!, gbgD -> gbgd! (gbd is the safe one).
#   * gcm, gcs, gpv and g are not defined: they would hide Get-Command, Get-PSCallStack,
#     Get-ItemPropertyValue and the profile's `g`. gc/gl/gm/gp/gcb *are* git, but `$x | gm`,
#     `ls *.log | gc` and `ls | gp` still run the PowerShell command when given pipeline input.
#   * `@{u}` can't be typed unquoted in PowerShell: write '@{u}' or use gdup.
#     `stash@{1}` / `HEAD@{1}` and a bare `--` do work (PowerShell mangles them; we repair them).
#   * gdv uses git's pager (no `view` on Windows); gpristine/gwipe ask before deleting files.
# =============================================================================

if ($PSVersionTable.PSVersion.Major -lt 7) {
    Write-Warning 'omz-git needs PowerShell 7 (pwsh); not loaded.'
    return
}

#region -- helpers -------------------------------------------------------------

function global:Write-OmzMessage {
    param([string]$Message, [int]$ExitCode = 1)
    Write-Host "omz-git: $Message" -ForegroundColor $(if ($ExitCode) { 'Yellow' } else { 'DarkGray' })
    $global:LASTEXITCODE = $ExitCode
}

# omz: the branch name, a short SHA when detached, '' outside a repository.
function global:git_current_branch {
    $ref = git symbolic-ref --quiet HEAD 2>$null
    if ($LASTEXITCODE -eq 0) { return $ref -replace '^refs/heads/', '' }
    if ($LASTEXITCODE -eq 128) { return '' }
    git rev-parse --short HEAD 2>$null
}

# For aliases that act on "the current branch": stop with a clear message when there isn't one.
function global:Get-OmzRequiredBranch {
    $ref = git symbolic-ref --quiet HEAD 2>$null
    switch ($LASTEXITCODE) {
        0 { return $ref -replace '^refs/heads/', '' }
        128 { Write-OmzMessage 'not a git repository' }
        default { Write-OmzMessage 'not on a branch (detached HEAD)' }
    }
}

# omz: the first of main/trunk/mainline/default/stable/master found in local branches, then
# origin, then upstream; then origin/HEAD or upstream/HEAD; then 'master'. Nothing outside a repo.
function global:git_main_branch {
    $refs = foreach ($namespace in 'heads', 'remotes/origin', 'remotes/upstream') {
        foreach ($name in 'main', 'trunk', 'mainline', 'default', 'stable', 'master') { "refs/$namespace/$name" }
    }
    $found = @(git for-each-ref '--format=%(refname)' @refs 2>$null)
    if ($LASTEXITCODE) { return }
    foreach ($ref in $refs) {
        if ($found -ccontains $ref) { return $ref.Substring($ref.LastIndexOf('/') + 1) }
    }
    foreach ($remote in 'origin', 'upstream') {
        $head = git rev-parse --abbrev-ref "$remote/HEAD" 2>$null
        if ($LASTEXITCODE -eq 0 -and $head -like "$remote/*") { return $head.Substring($remote.Length + 1) }
    }
    'master'
}

# omz: the first of dev/devel/develop/development that exists locally, else 'develop'.
function global:git_develop_branch {
    $names = 'dev', 'devel', 'develop', 'development'
    $refs = @($names | ForEach-Object { "refs/heads/$_" })
    $found = @(git for-each-ref '--format=%(refname)' @refs 2>$null)
    if ($LASTEXITCODE) { return }
    foreach ($name in $names) { if ($found -ccontains "refs/heads/$name") { return $name } }
    'develop'
}

# omz: prints WIP!! when the last commit is a gwip commit (handy in a prompt).
function global:work_in_progress {
    if ((git -c log.showSignature=false log -n 1 2>$null) -match '--wip--') { 'WIP!!' }
}

# Which alias started omz-git-run.ps1. `& 'gco'` reports '&' as the InvocationName, so fall back
# to the command text, then follow your own aliases that point at ours (Set-Alias co gco).
function global:Get-OmzGitAliasName {
    param([System.Management.Automation.InvocationInfo]$Invocation)
    $name = $Invocation.InvocationName
    if (-not $global:OmzGitSpec.Contains($name) -and $Invocation.Statement) {
        try {
            $ast = [System.Management.Automation.Language.Parser]::ParseInput($Invocation.Statement, [ref]$null, [ref]$null)
            $command = $ast.Find({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)
            if ($command -and $command.GetCommandName()) { $name = $command.GetCommandName() }
        }
        catch { }
    }
    for ($hop = 0; $hop -lt 5 -and $name -and -not $global:OmzGitSpec.Contains($name); $hop++) {
        $alias = Get-Alias -Name $name -ErrorAction Ignore
        if (-not $alias) { break }
        $name = $alias.Definition
    }
    $name
}

# PowerShell drops a bare `--` before a command sees it, and splits `stash@{1}` into 'stash@'
# plus a script block. Rebuild both from the command's text; every other argument keeps the
# value PowerShell gave it (quotes, $variables, expressions). Give up if anything doesn't line up.
function global:Repair-OmzArguments {
    param([System.Management.Automation.InvocationInfo]$Invocation, [object[]]$ArgumentList)
    $text = $Invocation.Statement
    if (-not $text -or $text -notmatch '(^|\s)--(\s|$)|@\{') { return , $ArgumentList }
    try {
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$null, [ref]$null)
        $command = $ast.Find({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true)
        if (-not $command) { return , $ArgumentList }
        $elements = @($command.CommandElements | Select-Object -Skip 1)
        $fixed = [System.Collections.Generic.List[object]]::new()
        $used = 0
        $changed = $false
        for ($e = 0; $e -lt $elements.Count; $e++) {
            $element = $elements[$e]
            $next = if ($e + 1 -lt $elements.Count) { $elements[$e + 1] }
            if ($element -is [System.Management.Automation.Language.CommandParameterAst] -and $element.Extent.Text -eq '--') {
                $fixed.Add('--')
                $changed = $true
                continue
            }
            if ($next -is [System.Management.Automation.Language.ScriptBlockExpressionAst] -and
                $next.Extent.StartOffset -eq $element.Extent.EndOffset) {
                $fixed.Add($element.Extent.Text + $next.Extent.Text)   # 'stash@' + '{1}'
                $used += 2
                $e++
                $changed = $true
                continue
            }
            if ($element -is [System.Management.Automation.Language.VariableExpressionAst] -and $element.Splatted) {
                return , $ArgumentList   # @splat: unknown number of arguments
            }
            # -name:value arrives as two arguments ('-name:' and the value)
            $take = if ($element -is [System.Management.Automation.Language.CommandParameterAst] -and $element.Argument) { 2 } else { 1 }
            for ($k = 0; $k -lt $take; $k++) {
                if ($used -ge $ArgumentList.Count) { return , $ArgumentList }
                $fixed.Add($ArgumentList[$used++])
            }
        }
        if (-not $changed -or $used -ne $ArgumentList.Count) { return , $ArgumentList }
        return , $fixed.ToArray()
    }
    catch { return , $ArgumentList }
}

# <main>, <develop>, <branch> -> git_main_branch, git_develop_branch, the current branch.
# Returns $null (after saying why) when one can't be resolved.
function global:Expand-OmzTokens {
    param([string[]]$Words)
    $values = @{}
    $out = [System.Collections.Generic.List[string]]::new()
    foreach ($word in $Words) {
        foreach ($token in [regex]::Matches($word, '<(main|develop|branch)>')) {
            $key = $token.Groups[1].Value
            if (-not $values.ContainsKey($key)) {
                $values[$key] = switch ($key) {
                    'main' { git_main_branch }
                    'develop' { git_develop_branch }
                    'branch' { Get-OmzRequiredBranch }
                }
                if (-not $values[$key]) {
                    if ($key -ne 'branch') { Write-OmzMessage 'not a git repository' }
                    return $null
                }
            }
            $word = $word.Replace($token.Value, $values[$key])
        }
        $out.Add($word)
    }
    , $out.ToArray()
}

function global:Write-OmzUsage {
    param($Spec)
    Write-Host "usage: $($Spec.Name) $($Spec.Usage)" -ForegroundColor Yellow -NoNewline
    Write-Host "    # $($Spec.Runs)" -ForegroundColor DarkGray
    $global:LASTEXITCODE = 1
}

# Called by omz-git-run.ps1 for every alias.
function global:Invoke-OmzGitAlias {
    param([string]$Name, [System.Management.Automation.InvocationInfo]$Invocation, [object[]]$ArgumentList = @())
    $spec = if ($Name) { $global:OmzGitSpec[$Name] }
    if (-not $spec) { Write-OmzMessage "'$Name' is not an omz-git alias (galias lists them)"; return }

    $arguments = Repair-OmzArguments $Invocation $ArgumentList
    if ($arguments.Count -lt $spec.Required) { Write-OmzUsage $spec; return }
    if ($spec.Function) { & $spec.Function $arguments; return }

    $git = Expand-OmzTokens $spec.Git
    if ($null -eq $git) { return }

    if ($spec.Message) {
        # The first run of words that don't start with '-' is the message; the rest passes through.
        $message = [System.Collections.Generic.List[string]]::new()
        $other = [System.Collections.Generic.List[object]]::new()
        $state = 0   # 0 = before the message, 1 = inside it, 2 = after it
        foreach ($argument in $arguments) {
            if ($state -lt 2 -and -not "$argument".StartsWith('-')) { $message.Add("$argument"); $state = 1 }
            else { $other.Add($argument); if ($state -eq 1) { $state = 2 } }
        }
        if (-not $message.Count) { Write-OmzUsage $spec; return }
        $otherArguments = $other.ToArray()
        git @git ($message -join ' ') @otherArguments
        return
    }
    git @git @arguments
}

#endregion

#region -- plain aliases --------------------------------------------------------
# name = git arguments. A string is split on spaces; an array is used word for word.
# Anything you type after the alias is appended.

$fmtAr = '--pretty=%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset'
$fmtAd = '--pretty=%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ad) %C(bold blue)<%an>%Creset'

$aliases = [ordered]@{
    # add / am / apply
    ga          = 'add'
    gaa         = 'add --all'
    gapa        = 'add --patch'
    gau         = 'add --update'
    gav         = 'add --verbose'
    gam         = 'am'
    gama        = 'am --abort'
    gamc        = 'am --continue'
    gamscp      = 'am --show-current-patch'
    gams        = 'am --skip'
    gap         = 'apply'
    gapt        = 'apply --3way'
    # bisect / blame
    gbs         = 'bisect'
    gbsb        = 'bisect bad'
    gbsg        = 'bisect good'
    gbsn        = 'bisect new'
    gbso        = 'bisect old'
    gbsr        = 'bisect reset'
    gbss        = 'bisect start'
    gbl         = 'blame -w'
    # branch
    gb          = 'branch'
    gba         = 'branch --all'
    gbd         = 'branch --delete'
    'gbd!'      = 'branch --delete --force'              # omz gbD
    gbm         = 'branch --move'
    gbnm        = 'branch --no-merged'
    gbr         = 'branch --remotes'
    ggsup       = 'branch --set-upstream-to=origin/<branch>'
    # checkout / cherry-pick / clean / clone
    gco         = 'checkout'
    gcor        = 'checkout --recurse-submodules'
    gcb         = 'checkout -b'
    'gcb!'      = 'checkout -B'                          # omz gcB
    gcd         = 'checkout <develop>'
    gcp         = 'cherry-pick'
    gcpa        = 'cherry-pick --abort'
    gcpc        = 'cherry-pick --continue'
    gclean      = 'clean --interactive -d'
    gcl         = 'clone --recurse-submodules'
    gclf        = 'clone --recursive --shallow-submodules --filter=blob:none --also-filter-submodules'
    # commit / config
    gcam        = 'commit --all --message'
    gcas        = 'commit --all --signoff'
    gcasm       = 'commit --all --signoff --message'
    gcss        = 'commit --gpg-sign --signoff'
    gcssm       = 'commit --gpg-sign --signoff --message'
    gcmsg       = 'commit --message'
    gcsm        = 'commit --signoff --message'
    gc          = 'commit --verbose'
    gca         = 'commit --verbose --all'
    'gca!'      = 'commit --verbose --all --amend'
    'gcan!'     = 'commit --verbose --all --no-edit --amend'
    'gcans!'    = 'commit --verbose --all --signoff --no-edit --amend'
    'gcann!'    = 'commit --verbose --all --date=now --no-edit --amend'
    'gc!'       = 'commit --verbose --amend'
    gcn         = 'commit --verbose --no-edit'
    'gcn!'      = 'commit --verbose --no-edit --amend'
    gcfu        = 'commit --fixup'
    gcf         = 'config --list'
    # diff
    gd          = 'diff'
    gdca        = 'diff --cached'
    gdcw        = 'diff --cached --word-diff'
    gds         = 'diff --staged'
    gdw         = 'diff --word-diff'
    gdv         = 'diff -w'                              # omz pipes this into `view -`
    gdup        = 'diff @{upstream}'
    gdt         = 'diff-tree --no-commit-id --name-only -r'
    # fetch / gui / help
    gf          = 'fetch'
    gfa         = 'fetch --all --tags --prune --jobs=10'
    gfo         = 'fetch origin'
    gg          = 'gui citool'
    gga         = 'gui citool --amend'
    ghh         = 'help'
    # log
    glgg        = 'log --graph'
    glgga       = 'log --graph --decorate --all'
    glgm        = 'log --graph --max-count=10'
    glods       = 'log', '--graph', $fmtAd, '--date=short'
    glod        = 'log', '--graph', $fmtAd
    glola       = 'log', '--graph', $fmtAr, '--all'
    glols       = 'log', '--graph', $fmtAr, '--stat'
    glol        = 'log', '--graph', $fmtAr
    glolm       = 'log', '<main>', '--graph', $fmtAr
    glo         = 'log --oneline --decorate'
    glog        = 'log --oneline --decorate --graph'
    gloga       = 'log --oneline --decorate --graph --all'
    glom        = 'log --oneline --decorate --color <main>..'
    glg         = 'log --stat'
    glgp        = 'log --stat --patch'
    gwch        = 'log --patch --abbrev-commit --pretty=medium --raw'
    # merge
    gm          = 'merge'
    gma         = 'merge --abort'
    gmc         = 'merge --continue'
    gms         = 'merge --squash'
    gmff        = 'merge --ff-only'
    gmom        = 'merge origin/<main>'
    gmum        = 'merge upstream/<main>'
    gmtl        = 'mergetool --no-prompt'
    gmtlvim     = 'mergetool --no-prompt --tool=vimdiff'
    # pull
    gl          = 'pull'
    gpr         = 'pull --rebase'
    gprv        = 'pull --rebase -v'
    gpra        = 'pull --rebase --autostash'
    gprav       = 'pull --rebase --autostash -v'
    gprom       = 'pull --rebase origin <main>'
    gpromi      = 'pull --rebase=interactive origin <main>'
    gprum       = 'pull --rebase upstream <main>'
    gprumi      = 'pull --rebase=interactive upstream <main>'
    ggpull      = 'pull origin <branch>'
    gluc        = 'pull upstream <branch>'
    glum        = 'pull upstream <main>'
    # push
    gp          = 'push'
    gpd         = 'push --dry-run'
    'gpf!'      = 'push --force'
    gpf         = 'push --force-with-lease --force-if-includes'
    gpsup       = 'push --set-upstream origin <branch>'
    gpsupf      = 'push --set-upstream origin <branch> --force-with-lease --force-if-includes'
    gpod        = 'push origin --delete'
    ggpush      = 'push origin <branch>'
    gpu         = 'push upstream'
    # rebase
    grb         = 'rebase'
    grba        = 'rebase --abort'
    grbc        = 'rebase --continue'
    grbi        = 'rebase --interactive'
    grbo        = 'rebase --onto'
    grbs        = 'rebase --skip'
    grbd        = 'rebase <develop>'
    grbm        = 'rebase <main>'
    grbom       = 'rebase origin/<main>'
    grbum       = 'rebase upstream/<main>'
    grbmi       = 'rebase <main> --interactive'
    grbmia      = 'rebase <main> --interactive --autosquash'
    # reflog / remote
    grf         = 'reflog'
    gr          = 'remote'
    grv         = 'remote --verbose'
    gra         = 'remote add'
    grrm        = 'remote remove'
    grmv        = 'remote rename'
    grset       = 'remote set-url'
    grup        = 'remote update'
    # reset / restore / revert / rm
    grh         = 'reset'
    gru         = 'reset --'
    grhh        = 'reset --hard'
    grhk        = 'reset --keep'
    grhs        = 'reset --soft'
    groh        = 'reset origin/<branch> --hard'
    grs         = 'restore'
    grss        = 'restore --source'
    grst        = 'restore --staged'
    grev        = 'revert'
    greva       = 'revert --abort'
    grevc       = 'revert --continue'
    grm         = 'rm'
    grmc        = 'rm --cached'
    # show / stash / status
    gsh         = 'show'
    gshs        = 'show --stat'
    gsps        = 'show --pretty=short --show-signature'
    gstall      = 'stash --all'
    gstaa       = 'stash apply'
    gstc        = 'stash clear'
    gstd        = 'stash drop'
    gstl        = 'stash list'
    gstp        = 'stash pop'
    gsta        = 'stash push'
    gsts        = 'stash show --patch'
    gstu        = 'stash push --include-untracked'
    gst         = 'status'
    gss         = 'status --short'
    gsb         = 'status --short --branch'
    gsnut       = 'status --untracked-files=no'
    # submodule / switch
    gsi         = 'submodule init'
    gsu         = 'submodule update'
    gsuri       = 'submodule update --recursive --init'
    gsw         = 'switch'
    gswc        = 'switch --create'
    gswd        = 'switch <develop>'
    gswm        = 'switch <main>'
    # tag / update-index / worktree
    gta         = 'tag --annotate'
    gts         = 'tag --sign'
    gtv         = 'tag --sort=version:refname'           # omz: git tag | sort -V
    gignore     = 'update-index --assume-unchanged'
    gunignore   = 'update-index --no-assume-unchanged'
    gwt         = 'worktree'
    gwta        = 'worktree add'
    gwtls       = 'worktree list'
    gwtmv       = 'worktree move'
    gwtrm       = 'worktree remove'
}

#endregion

#region -- aliases that need logic ----------------------------------------------
# name = 'git words Tab completion should assume', 'what galias shows'

$custom = [ordered]@{
    gwip      = '', 'git add --all + commit --no-verify --no-gpg-sign -m "--wip-- [skip ci]"'
    gunwip    = '', 'git reset HEAD~1 when the last commit is a --wip-- commit'
    gunwipall = '', 'git reset to the newest commit that is not --wip--'
    gbda      = '', 'git branch --delete: every branch merged into HEAD (keeps current, main, develop)'
    gbds      = '', 'git branch -D: every branch squash-merged into main (keeps current, main, develop)'
    gbg       = '', 'git branch -vv: branches whose upstream is gone'
    gbgd      = '', 'git branch --delete: branches whose upstream is gone'
    'gbgd!'   = '', 'git branch -D: branches whose upstream is gone (omz gbgD)'
    gbcopy    = '', 'copy the current branch name to the clipboard'
    grename   = 'branch --move', 'git branch --move <old> <new> + rename it on origin'
    gccd      = '', 'git clone --recurse-submodules <repo> [dir], then cd into it'
    gdct      = '', 'git describe --tags <newest tag>'
    gdnolock  = 'diff', 'git diff, without package-lock.json and *.lock'
    glp       = 'log --pretty', 'git log --pretty=<format>'
    gfg       = '', 'git ls-files, filtered by a regex'
    gignored  = '', 'git ls-files -v: assume-unchanged files'
    gcount    = 'shortlog', 'git shortlog --summary --numbered'
    gtl       = '', 'git tag --sort=-v:refname -n --list "<prefix>*"'
    ggl       = 'pull origin', 'git pull origin <branch> (default: current)'
    ggu       = 'pull origin', 'git pull --rebase origin <branch> (default: current)'
    ggpur     = 'pull origin', 'git pull --rebase origin <branch> (default: current)'
    ggp       = 'push origin', 'git push origin <branch> (default: current)'
    ggf       = 'push origin', 'git push --force origin <branch> (default: current)'
    ggfl      = 'push origin', 'git push --force-with-lease origin <branch> (default: current)'
    ggpnp     = 'pull origin', 'git pull origin <branch> && git push origin <branch> (default: current)'
    gpoat     = '', 'git push origin --all && git push origin --tags'
    gpristine = '', 'git reset --hard && git clean -d -x --force (asks first)'
    gwipe     = '', 'git reset --hard && git clean -d --force (asks first)'
    gk        = '', 'gitk --all --branches, in the background'
    gke       = '', 'gitk --all <reflog commits>, in the background'
    grt       = '', 'cd $(git rev-parse --show-toplevel)'
}

# Aliases that need arguments. Each <...> outside [...] counts as one required argument.
$usages = @{
    gcb = '<new-branch> [start-point]'; 'gcb!' = '<branch> [start-point]'; gswc = '<new-branch> [start-point]'
    gbd = '<branch>...'; 'gbd!' = '<branch>...'; gbm = '[old-branch] <new-branch>'
    gcp = '<commit>...'; gcfu = '<commit>'
    gcl = '<repo> [dir]'; gclf = '<repo> [dir]'; gccd = '<repo> [dir]'
    gam = '<mbox-or-patch>...'; gap = '<patch>...'; gapt = '<patch>...'
    gbl = '<file>'; gdt = '<commit>'
    gra = '<name> <url>'; grmv = '<old> <new>'; grrm = '<name>'; grset = '<name> <url>'
    grm = '<path>...'; grmc = '<path>...'
    gta = '<tag> [commit]'; gts = '<tag> [commit]'; gpod = '<branch>...'
    gignore = '<file>...'; gunignore = '<file>...'
    gwta = '<path> [commit-ish]'; gwtmv = '<worktree> <new-path>'; gwtrm = '<worktree>'
    grename = '<old-branch> <new-branch>'
    glp = '<oneline|short|medium|full|fuller|reference|email|raw|format:...>'
}

function global:OmzGit_gwip {
    param([object[]]$Arguments)
    git add --all
    if ($LASTEXITCODE -eq 0) { git commit --no-verify --no-gpg-sign '--message=--wip-- [skip ci]' }
}

function global:OmzGit_gunwip {
    param([object[]]$Arguments)
    $subject = git log -1 --format=%s 2>$null
    if ($LASTEXITCODE) { return }
    if ($subject -notmatch '--wip--') { Write-OmzMessage 'the last commit is not a --wip-- commit'; return }
    git reset HEAD~1
}

function global:OmzGit_gunwipall {
    param([object[]]$Arguments)
    $commit = git log --grep=--wip-- --invert-grep --max-count=1 --format=format:%H 2>$null
    if ($LASTEXITCODE) { return }
    if (-not $commit) { Write-OmzMessage 'every commit is a --wip-- commit, nothing to reset to'; return }
    if ($commit -ne (git rev-parse HEAD)) { git reset $commit }
}

function global:OmzGit_gbda {
    param([object[]]$Arguments)
    $merged = git branch --no-color --merged 2>$null
    if ($LASTEXITCODE) { return }
    $keep = @(git_main_branch; git_develop_branch)
    # '*' = the current branch, '+' = checked out in another worktree
    $doomed = @($merged | Where-Object { $_ -notmatch '^[*+]' } | ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and $keep -cnotcontains $_ })
    if (-not $doomed) { Write-OmzMessage 'no merged branches to delete' 0; return }
    git branch --delete @doomed
}

function global:OmzGit_gbds {
    param([object[]]$Arguments)
    $base = git_main_branch
    if (-not $base) { Write-OmzMessage 'not a git repository'; return }
    git rev-parse --verify --quiet "$base^{commit}" *> $null
    if ($LASTEXITCODE) { $base = git_develop_branch }
    $keep = @(git branch --show-current; git_main_branch; git_develop_branch) +
    @(git worktree list --porcelain | Where-Object { $_ -like 'branch refs/heads/*' } | ForEach-Object { $_.Substring(18) })
    $branches = @(git for-each-ref refs/heads/ '--format=%(refname:short)' | Where-Object { $keep -cnotcontains $_ })
    $deleted = 0
    for ($i = 0; $i -lt $branches.Count; $i++) {
        $branch = $branches[$i]
        Write-Progress -Activity 'gbds: looking for squash-merged branches' -Status $branch -PercentComplete (100 * $i / $branches.Count)
        $mergeBase = git merge-base $base $branch 2>$null
        if (-not $mergeBase) { continue }
        $squashed = git commit-tree (git rev-parse "$branch^{tree}") -p $mergeBase -m _
        if ("$(git cherry $base $squashed)".StartsWith('-')) { git branch -D $branch; $deleted++ }
    }
    Write-Progress -Activity 'gbds: looking for squash-merged branches' -Completed
    if ($deleted) { $global:LASTEXITCODE = 0 } else { Write-OmzMessage 'no squash-merged branches to delete' 0 }
}

# Branches whose upstream was deleted. %(upstream:track) is never translated, unlike the
# "gone" in `git branch -vv` (that's why omz forces LANG=C).
function global:Get-OmzGoneBranches {
    git for-each-ref refs/heads '--format=%(refname:short)%09%(upstream:track)' 2>$null |
        Where-Object { $_ -match '\t\[gone\]$' } |
        ForEach-Object { $_.Substring(0, $_.IndexOf("`t")) }
}

function global:OmzGit_gbg {
    param([object[]]$Arguments)
    $gone = @(Get-OmzGoneBranches)
    if ($LASTEXITCODE) { return }
    if (-not $gone) { Write-OmzMessage 'no branches whose upstream is gone' 0; return }
    git branch -vv --list @gone
}

function global:Remove-OmzGoneBranches {
    param([string]$Flag)
    $gone = @(Get-OmzGoneBranches)
    if ($LASTEXITCODE) { return }
    if (-not $gone) { Write-OmzMessage 'no branches whose upstream is gone' 0; return }
    git branch $Flag @gone
}
function global:OmzGit_gbgd { param([object[]]$Arguments) Remove-OmzGoneBranches '--delete' }
function global:OmzGit_gbgd! { param([object[]]$Arguments) Remove-OmzGoneBranches '-D' }

function global:OmzGit_gbcopy {
    param([object[]]$Arguments)
    $branch = git_current_branch
    if (-not $branch) { Write-OmzMessage 'not a git repository'; return }
    Set-Clipboard -Value $branch
    Write-Host "copied $branch" -ForegroundColor DarkGray
    $global:LASTEXITCODE = 0
}

function global:OmzGit_grename {
    param([object[]]$Arguments)
    $old, $new = "$($Arguments[0])", "$($Arguments[1])"
    git branch --move $old $new
    if ($LASTEXITCODE) { return }
    git push origin ":$old"                     # delete the old name on origin...
    if ($LASTEXITCODE -eq 0) { git push --set-upstream origin $new }   # ...and push the new one
}

function global:OmzGit_gccd {
    param([object[]]$Arguments)
    git clone --recurse-submodules @Arguments
    if ($LASTEXITCODE) { return }
    $words = @($Arguments | ForEach-Object { "$_" })
    $repo = $words | Where-Object { $_ -match '^(ssh|git|ftps?|https?)://|@' } | Select-Object -First 1
    if (-not $repo) { $repo = $words | Where-Object { -not $_.StartsWith('-') } | Select-Object -First 1 }
    $last = $words[-1]
    $dir = if ($last -ne $repo -and -not $last.StartsWith('-') -and (Test-Path -LiteralPath $last -PathType Container)) { $last }
    else { ($repo.TrimEnd('/', '\') -split '[/\\:]')[-1] -replace '\.git$', '' }
    if ($dir -and (Test-Path -LiteralPath $dir -PathType Container)) { Set-Location -LiteralPath $dir }
}

function global:OmzGit_gdct {
    param([object[]]$Arguments)
    $newest = git rev-list --tags --max-count=1 2>$null
    if ($LASTEXITCODE) { return }
    if (-not $newest) { Write-OmzMessage 'no tags in this repository'; return }
    git describe --tags $newest @Arguments
}

function global:OmzGit_gdnolock {
    param([object[]]$Arguments)
    git diff @Arguments ':(exclude)package-lock.json' ':(exclude)*.lock'
}

function global:OmzGit_glp {
    param([object[]]$Arguments)
    $more = @($Arguments | Select-Object -Skip 1)
    git log "--pretty=$($Arguments[0])" @more
}

function global:OmzGit_gfg {
    param([object[]]$Arguments)
    $files = @(git ls-files)
    if ($LASTEXITCODE -or -not $Arguments) { return $files }
    $pattern = "$($Arguments[0])"
    try { $files -match $pattern } catch { $files | Where-Object { $_.Contains($pattern) } }
}

function global:OmzGit_gignored {
    param([object[]]$Arguments)
    @(git ls-files -v @Arguments) -cmatch '^[a-z]'
}

function global:OmzGit_gcount {
    param([object[]]$Arguments)
    # With no revision, `git shortlog` reads stdin when it isn't a terminal: default to HEAD.
    if (-not @($Arguments | Where-Object { -not "$_".StartsWith('-') }).Count) { $Arguments = @($Arguments) + 'HEAD' }
    git shortlog --summary --numbered @Arguments
}

function global:OmzGit_gtl {
    param([object[]]$Arguments)
    git tag --sort=-v:refname -n --list "$(@($Arguments)[0])*"
}

# ggl/ggp/ggu/ggf/ggfl: no branch given = the current branch. Unlike omz, several arguments are
# passed separately (omz joins them into one string), and options alone still get the current
# branch: `ggp --force-with-lease` pushes the current branch.
function global:Get-OmzBranchArguments {
    param([object[]]$Arguments)
    if (@($Arguments | Where-Object { -not "$_".StartsWith('-') }).Count) { return , @($Arguments) }
    $branch = Get-OmzRequiredBranch
    if ($branch) { , (@($Arguments) + $branch) }
}
function global:OmzGit_ggl { param([object[]]$Arguments) $b = Get-OmzBranchArguments $Arguments; if ($null -ne $b) { git pull origin @b } }
function global:OmzGit_ggu { param([object[]]$Arguments) $b = Get-OmzBranchArguments $Arguments; if ($null -ne $b) { git pull --rebase origin @b } }
function global:OmzGit_ggpur { param([object[]]$Arguments) OmzGit_ggu $Arguments }
function global:OmzGit_ggp { param([object[]]$Arguments) $b = Get-OmzBranchArguments $Arguments; if ($null -ne $b) { git push origin @b } }
function global:OmzGit_ggf { param([object[]]$Arguments) $b = Get-OmzBranchArguments $Arguments; if ($null -ne $b) { git push --force origin @b } }
function global:OmzGit_ggfl { param([object[]]$Arguments) $b = Get-OmzBranchArguments $Arguments; if ($null -ne $b) { git push --force-with-lease origin @b } }
function global:OmzGit_ggpnp {
    param([object[]]$Arguments)
    OmzGit_ggl $Arguments
    if ($LASTEXITCODE -eq 0) { OmzGit_ggp $Arguments }
}

function global:OmzGit_gpoat {
    param([object[]]$Arguments)
    git push origin --all @Arguments
    if ($LASTEXITCODE -eq 0) { git push origin --tags @Arguments }
}

# omz runs `reset --hard && clean` straight away. Deleted untracked files can't be recovered
# (not even from the reflog), so show what would go and ask first.
function global:Invoke-OmzWipe {
    param([string[]]$Clean)
    $tracked = @(git status --porcelain --untracked-files=no 2>$null)
    if ($LASTEXITCODE) { Write-OmzMessage 'not a git repository'; return }
    $untracked = @(git clean --dry-run @Clean | ForEach-Object { $_ -replace '^Would remove ', '' })
    if (-not $tracked -and -not $untracked) { Write-OmzMessage 'nothing to reset or clean' 0; return }
    if ($tracked) { Write-Host "reset --hard discards your changes to $($tracked.Count) tracked file(s)" -ForegroundColor Yellow }
    if ($untracked) {
        Write-Host "clean $($Clean -join ' ') deletes $($untracked.Count) untracked path(s):" -ForegroundColor Yellow
        $untracked | Select-Object -First 15 | ForEach-Object { Write-Host "  $_" }
        if ($untracked.Count -gt 15) { Write-Host "  ... and $($untracked.Count - 15) more" }
    }
    if ((Read-Host 'Continue? [y/N]') -notmatch '^(y|yes)$') { Write-OmzMessage 'aborted'; return }
    git reset --hard
    if ($LASTEXITCODE -eq 0) { git clean --force @Clean }
}
function global:OmzGit_gpristine { param([object[]]$Arguments) Invoke-OmzWipe '-d', '-x' }
function global:OmzGit_gwipe { param([object[]]$Arguments) Invoke-OmzWipe '-d' }

function global:OmzGit_gk {
    param([object[]]$Arguments)
    Start-Process gitk -ArgumentList (@('--all', '--branches') + @($Arguments | ForEach-Object { "$_" })) -NoNewWindow
}

function global:OmzGit_gke {
    param([object[]]$Arguments)
    $reflog = @(git log --walk-reflogs --pretty=%h 2>$null | Select-Object -Unique | Select-Object -First 2000)
    Start-Process gitk -ArgumentList (@('--all') + $reflog + @($Arguments | ForEach-Object { "$_" })) -NoNewWindow
}

function global:OmzGit_grt {
    param([object[]]$Arguments)
    $root = git rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE) { Write-OmzMessage 'not a git repository'; return }
    Set-Location -LiteralPath $root
}

#endregion

#region -- registration ---------------------------------------------------------

if (-not $PSScriptRoot) { throw 'omz-git: dot-source this file by its path (. <folder>\omz-git.ps1)' }

# Each <...> outside [...] in a usage string is one required argument.
function global:Get-OmzRequiredCount {
    param([string]$Usage)
    [regex]::Matches(($Usage -replace '\[[^\]]*\]', ''), '<[^>]+>').Count
}

$global:OmzGitSpec = [ordered]@{}
foreach ($name in $aliases.Keys) {
    $value = $aliases[$name]
    $git = if ($value -is [string]) { [string[]](-split $value) } else { [string[]]$value }
    $isMessage = $git[-1] -ceq '--message'
    $usage = if ($usages.Contains($name)) { $usages[$name] } elseif ($isMessage) { '<message> [git commit options]' }
    $global:OmzGitSpec[$name] = [pscustomobject]@{
        Name     = $name
        Git      = $git
        Function = $null
        Complete = $git
        Message  = $isMessage
        Usage    = $usage
        Required = if ($usage) { Get-OmzRequiredCount $usage } else { 0 }
        Runs     = (@('git') + $git) -join ' '
    }
}
foreach ($name in $custom.Keys) {
    if ($global:OmzGitSpec.Contains($name)) { throw "omz-git: '$name' is defined twice" }
    $completeAs, $runs = $custom[$name]
    $global:OmzGitSpec[$name] = [pscustomobject]@{
        Name     = $name
        Git      = $null
        Function = "OmzGit_$name"
        Complete = [string[]]@(-split $completeAs | Where-Object { $_ })
        Message  = $false
        Usage    = $usages[$name]
        Required = if ($usages[$name]) { Get-OmzRequiredCount $usages[$name] } else { 0 }
        Runs     = $runs
    }
}

# What `$x | gm`, `ls | gc` and `ls | gp` run instead of git.
$global:OmzGitPipelineFallback = @{ gc = 'Get-Content'; gm = 'Get-Member'; gp = 'Get-ItemProperty' }

# Load the module that defines the built-in `gcb` alias (Get-Clipboard) now, so it can't come
# back and replace ours when it auto-loads later.
Import-Module Microsoft.PowerShell.Management
$runner = Join-Path $PSScriptRoot 'omz-git-run.ps1'
foreach ($spec in $global:OmzGitSpec.Values) {
    Set-Alias -Name $spec.Name -Value $runner -Scope Global -Force -Description $spec.Runs
}

#endregion

#region -- Tab completion ---------------------------------------------------------
# Every alias gets one native completer. It rebuilds a "virtual" git command line (the alias's
# git words + what you typed before the cursor) and offers refs or changed files that contain
# the text under the cursor. Returning nothing lets PowerShell fall back to path completion.

# git for completion: stderr dropped, output read as UTF-8 so non-ASCII file names survive.
function global:Invoke-OmzGitQuiet {
    $encoding = [Console]::OutputEncoding
    try { [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false) } catch { }
    try { git @args 2>$null }
    finally { try { [Console]::OutputEncoding = $encoding } catch { } }
}

# Branches and tags, newest first, in one for-each-ref call.
#   checkout  local, then remote-only branches under the name git creates them with, then tags
#   switch    like checkout without tags
#   revision  local, remote (origin/x), tags
#   local     local only;  push: local + tags;  remote: the branches of -Remote, without the prefix
# Rank orders kinds: files 0-1 (see below), local 2, remote 3, tag 4.
function global:Get-OmzRefCandidates {
    param([string]$Kind, [string]$Remote)
    # @(): splatting a single string would pass its characters as separate arguments
    $namespaces = @(switch ($Kind) {
            'local' { 'refs/heads' }
            'push' { 'refs/heads', 'refs/tags' }
            'remote' { "refs/remotes/$Remote/" }
            'switch' { 'refs/heads', 'refs/remotes' }
            default { 'refs/heads', 'refs/remotes', 'refs/tags' }
        })
    $format = '--format=%(refname)%09%(creatordate:relative)%09%(subject)'
    $locals = [System.Collections.Generic.HashSet[string]]::new()
    $remotes = [System.Collections.Generic.List[object]]::new()
    $index = 0
    foreach ($line in (Invoke-OmzGitQuiet for-each-ref --sort=-creatordate $format @namespaces)) {
        $ref, $when, $subject = $line -split "`t", 3
        $about = "$when - $subject"
        if ($ref.StartsWith('refs/heads/')) {
            $name = $ref.Substring(11)
            [void]$locals.Add($name)
            [pscustomobject]@{ Text = $name; Match = $name; Rank = 2; Index = $index++; Tip = "branch - $about"; Raw = $false }
        }
        elseif ($ref.StartsWith('refs/tags/')) {
            $name = $ref.Substring(10)
            [pscustomobject]@{ Text = $name; Match = $name; Rank = 4; Index = $index++; Tip = "tag - $about"; Raw = $false }
        }
        elseif ($ref.StartsWith('refs/remotes/')) {
            $full = $ref.Substring(13)                  # origin/feature/x
            $slash = $full.IndexOf('/')
            if ($slash -lt 0 -or $full.EndsWith('/HEAD')) { continue }
            $remotes.Add([pscustomobject]@{ Full = $full; Remote = $full.Substring(0, $slash); Name = $full.Substring($slash + 1); About = $about; Index = $index++ })
        }
    }
    if ($Kind -in 'checkout', 'switch') {
        # Remote-only branches: `git checkout x` creates x from origin/x, but only when exactly
        # one remote has an x. Otherwise offer `--track <remote>/x`, which always works.
        $remoteOnly = @($remotes | Where-Object { -not $locals.Contains($_.Name) })
        $count = @{}
        foreach ($r in $remoteOnly) { $count[$r.Name] = 1 + [int]$count[$r.Name] }
        foreach ($r in $remoteOnly) {
            $ambiguous = $count[$r.Name] -gt 1
            [pscustomobject]@{
                Text = if ($ambiguous) { "--track $($r.Full)" } else { $r.Name }
                Match = $r.Full; Rank = 3; Index = $r.Index; Tip = "$($r.Full) - $($r.About)"; Raw = $ambiguous
            }
        }
        if ($Kind -eq 'checkout') {
            # origin/x itself (a detached checkout): only offered once you type "origin/..."
            foreach ($r in $remotes) {
                [pscustomobject]@{ Text = $r.Full; Match = $r.Full; Rank = 3.5; Index = $r.Index; Tip = "detached at $($r.Full) - $($r.About)"; Raw = $false; Hidden = $true }
            }
        }
    }
    else {
        foreach ($r in $remotes) {
            $text = if ($Kind -eq 'remote') { $r.Name } else { $r.Full }
            [pscustomobject]@{ Text = $text; Match = $r.Full; Rank = 3; Index = $r.Index; Tip = "$($r.Full) - $($r.About)"; Raw = $false }
        }
    }
}

# Changed files, relative to the current directory (like git's own completion).
#   addable  modified, deleted and untracked;  tracked: modified and deleted;  staged: in the index
function global:Get-OmzFileCandidates {
    param([string]$Kind)
    $entries = if ($Kind -eq 'staged') {
        ((Invoke-OmzGitQuiet diff --cached --name-only --relative -z) -join '') -split "`0" |
            Where-Object { $_ } | ForEach-Object { "S $_" }
    }
    else {
        $which = @(if ($Kind -eq 'addable') { '--modified', '--others', '--exclude-standard' } else { '--modified' })
        ((Invoke-OmzGitQuiet ls-files -z -t @which) -join '') -split "`0" | Where-Object { $_.Length -gt 2 }
    }
    $seen = [System.Collections.Generic.HashSet[string]]::new()
    $index = 0
    foreach ($entry in $entries) {
        $path = $entry.Substring(2)
        if (-not $seen.Add($path)) { continue }
        $what = switch -CaseSensitive ($entry.Substring(0, 1)) {
            'S' { 'staged' } '?' { 'untracked' } 'R' { 'deleted' } 'M' { 'unmerged' } default { 'modified' }
        }
        [pscustomobject]@{ Text = $path; Match = $path; Rank = [int]($what -eq 'untracked'); Index = $index++; Tip = "$what file"; Raw = $false }
    }
}

function global:Get-OmzPrettyFormats {
    $index = 0
    foreach ($format in 'oneline', 'short', 'medium', 'full', 'fuller', 'reference', 'email', 'raw', 'format:') {
        [pscustomobject]@{ Text = $format; Match = $format; Rank = 0; Index = $index++; Tip = "git log --pretty=$format"; Raw = $false }
    }
}

# Keep candidates that contain the word (case-insensitive; * and ? work as wildcards) and order
# them: name or last /segment starts with the word first, then by kind, then newest first.
function global:ConvertTo-OmzCompletionResult {
    param([object[]]$Candidates, [string]$Word)
    $Word = $Word.Trim("'", '"')
    $wildcard = $Word.IndexOfAny([char[]]'*?') -ge 0
    $ignoreCase = [StringComparison]::OrdinalIgnoreCase
    $slash = $Word.IndexOf('/')
    $hits = foreach ($candidate in $Candidates) {
        # Hidden candidates (origin/x for checkout) need the word to start with "<remote>/"
        if ($candidate.Hidden -and ($slash -lt 1 -or -not $candidate.Text.StartsWith($Word.Substring(0, $slash + 1), [StringComparison]::OrdinalIgnoreCase))) { continue }
        $tier = 0
        if ($Word) {
            $found = if ($wildcard) { $candidate.Match -like "*$Word*" } else { $candidate.Match.IndexOf($Word, $ignoreCase) -ge 0 }
            if (-not $found) { continue }
            $leaf = $candidate.Text.Substring($candidate.Text.LastIndexOf('/') + 1)
            if (-not ($candidate.Text.StartsWith($Word, $ignoreCase) -or $leaf.StartsWith($Word, $ignoreCase))) { $tier = 1 }
        }
        [pscustomobject]@{ Tier = $tier; Candidate = $candidate }
    }
    $hits | Sort-Object Tier, { $_.Candidate.Rank }, { $_.Candidate.Index } | Select-Object -First 200 | ForEach-Object {
        $c = $_.Candidate
        $text = if (-not $c.Raw -and $c.Text -match '[\s''"`$@{}();,&|#<>]') { "'" + $c.Text.Replace("'", "''") + "'" } else { $c.Text }
        [System.Management.Automation.CompletionResult]::new($text, $c.Text, 'ParameterValue', $c.Tip)
    }
}

function global:Get-OmzGitCompletion {
    param([string]$WordToComplete, $CommandAst, [int]$CursorPosition)
    $name = $CommandAst.GetCommandName()
    $spec = if ($name) { $global:OmzGitSpec[$name] }
    if (-not $spec -or -not $spec.Complete.Count) { return }

    $words = [System.Collections.Generic.List[string]]::new([string[]]$spec.Complete)
    foreach ($element in @($CommandAst.CommandElements | Select-Object -Skip 1)) {
        if ($element.Extent.EndOffset -ge $CursorPosition) { break }   # the word being completed
        $words.Add($(if ($element -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $element.Value } else { $element.Extent.Text }))
    }
    $command = $words[0]
    $rest = @($words | Select-Object -Skip 1)
    $previous = $words[$words.Count - 1]
    $afterDashDash = $rest -ccontains '--'
    $positional = @($rest | Where-Object { -not $_.StartsWith('-') })
    $has = { foreach ($flag in $args) { if ($rest -ccontains $flag) { return $true } }; $false }

    $candidates = switch -CaseSensitive ($command) {
        'checkout' {
            if ($afterDashDash) { Get-OmzFileCandidates tracked }
            elseif ($previous -cin '-b', '-B', '--orphan') { }                       # naming a new branch
            elseif (& $has '-b' '-B' '--orphan') { Get-OmzRefCandidates revision }    # its start point
            else { Get-OmzRefCandidates checkout }
        }
        'switch' {
            if ($previous -cin '-c', '-C', '--create', '--force-create', '--orphan') { }
            elseif (& $has '-c' '-C' '--create' '--force-create' '-d' '--detach') { Get-OmzRefCandidates revision }
            else { Get-OmzRefCandidates switch }
        }
        'branch' {
            if ($previous -cin '-u', '--set-upstream-to' -or (& $has '--merged' '--no-merged' '--contains' '--no-contains' '--points-at')) {
                Get-OmzRefCandidates revision
            }
            else { Get-OmzRefCandidates local }
        }
        'restore' {
            if ($previous -cin '-s', '--source') { Get-OmzRefCandidates revision }
            elseif (& $has '-s' '--source') { }                     # any file can come from another commit
            elseif ((& $has '-S' '--staged') -and -not (& $has '-W' '--worktree')) { Get-OmzFileCandidates staged }
            else { Get-OmzFileCandidates tracked }
        }
        'add' {
            if (& $has '-u' '--update' '-p' '--patch') { Get-OmzFileCandidates tracked } else { Get-OmzFileCandidates addable }
        }
        'diff' {
            Get-OmzFileCandidates $(if (& $has '--cached' '--staged') { 'staged' } else { 'tracked' })
            if (-not $afterDashDash) { Get-OmzRefCandidates revision }
        }
        'reset' {
            if ($afterDashDash) { Get-OmzFileCandidates staged } else { Get-OmzRefCandidates revision }
        }
        'push' {
            # the first positional is the remote: leave that to normal completion
            if ((& $has '-d' '--delete') -and $positional.Count) { Get-OmzRefCandidates remote $positional[0] }
            elseif ($positional.Count) { Get-OmzRefCandidates push }
        }
        { $_ -cin 'pull', 'fetch' } {
            if ($positional.Count) { Get-OmzRefCandidates remote $positional[0] }
        }
        'commit' {
            if ($previous -cin '--fixup', '--squash', '-c', '-C', '--reuse-message', '--reedit-message') { Get-OmzRefCandidates revision }
        }
        'log' {
            if ($previous -cin '--pretty', '--format') { Get-OmzPrettyFormats }
            elseif (-not $afterDashDash) { Get-OmzRefCandidates revision }
        }
        'tag' {
            if ($positional.Count -and -not (& $has '-l' '--list' '-d' '--delete' '-v' '--verify')) { Get-OmzRefCandidates revision }
        }
        'worktree' {
            if ($positional.Count -ge 2 -and $positional[0] -ceq 'add') { Get-OmzRefCandidates checkout }
        }
        { $_ -cin 'merge', 'rebase', 'cherry-pick', 'show', 'revert', 'reflog', 'diff-tree', 'shortlog', 'describe', 'bisect' } {
            if (-not $afterDashDash) { Get-OmzRefCandidates revision }
        }
    }
    if ($candidates) { ConvertTo-OmzCompletionResult @($candidates) $WordToComplete }
}

Register-ArgumentCompleter -Native -CommandName @($global:OmzGitSpec.Keys) -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    try { Get-OmzGitCompletion $wordToComplete $commandAst $cursorPosition } catch { }
}

#endregion

# galias [text]: the aliases whose name or command contains text.
function global:galias {
    param([string]$Filter)
    foreach ($spec in $global:OmzGitSpec.Values) {
        $runs = if ($spec.Usage -and -not $spec.Function) { "$($spec.Runs) $($spec.Usage)" } else { $spec.Runs }
        if ($Filter -and $spec.Name.IndexOf($Filter, [StringComparison]::OrdinalIgnoreCase) -lt 0 -and
            $runs.IndexOf($Filter, [StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        [pscustomobject]@{ Alias = $spec.Name; Runs = $runs }
    }
}

Write-Host "  omz git: $($global:OmzGitSpec.Count) aliases - galias to list them" -ForegroundColor DarkGray
