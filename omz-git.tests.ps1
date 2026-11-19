# omz-git.tests.ps1 - run:  pwsh -NoProfile -File omz-git.tests.ps1
#
# Builds a throwaway repository in %TEMP%, loads omz-git.ps1 and checks aliases, argument
# handling, exit codes ($? / && / ||) and Tab completion. Nothing outside the temp repo changes:
# a recording `git` function stands in for git; read-only calls are forwarded to the real git,
# everything else is only recorded.

$ErrorActionPreference = 'Continue'
$global:RealGit = (Get-Command git -CommandType Application | Select-Object -First 1).Source
$script:passed = 0
$script:failed = [System.Collections.Generic.List[string]]::new()

function Assert-True([string]$Name, $Condition, [string]$Detail = '') {
    if ($Condition) { $script:passed++ }
    else { $script:failed.Add("$Name  $Detail"); Write-Host "FAIL  $Name  $Detail" -ForegroundColor Red }
}
function Assert-Equal([string]$Name, $Expected, $Actual) {
    $e = @($Expected | ForEach-Object { "$_" }) -join ' ; '
    $a = @($Actual | ForEach-Object { "$_" }) -join ' ; '
    Assert-True $Name ($e -ceq $a) "expected [$e] got [$a]"
}

# --- recording git ---------------------------------------------------------------
$global:GitCalls = [System.Collections.Generic.List[string]]::new()
$global:GitFailOn = $null      # wildcard: a recorded call matching it "fails" (exit 1)
$global:RecordGit = $true
$global:ReadOnlyGit = '^(symbolic-ref|rev-parse|for-each-ref|show-ref|ls-files|rev-list|merge-base|cherry|commit-tree|worktree list|status --porcelain|clean --dry-run|branch --no-color --merged|branch --show-current|log -1 |log --grep|log --walk-reflogs|-c log\.showSignature|diff --cached --name-only|config)'
function global:git {
    $line = @($args | ForEach-Object { "$_" }) -join ' '
    if (-not $global:RecordGit -or $line -match $global:ReadOnlyGit) { & $global:RealGit @args; return }
    $global:GitCalls.Add((@($args | ForEach-Object { "$_" }) -join '|'))
    $global:LASTEXITCODE = if ($global:GitFailOn -and $line -like $global:GitFailOn) { 1 } else { 0 }
}
function Invoke-Recorded([string]$Line) {
    $global:GitCalls.Clear()
    Invoke-Expression $Line *> $null
    , $global:GitCalls.ToArray()
}
function Get-Completions([string]$Line) {
    @((TabExpansion2 -inputScript $Line -cursorColumn $Line.Length).CompletionMatches | ForEach-Object CompletionText)
}

# --- throwaway repository ------------------------------------------------------------
$repo = Join-Path ([IO.Path]::GetTempPath()) ('omz-git-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$notRepo = "$repo-not-a-repo"
New-Item -ItemType Directory -Path $repo, $notRepo | Out-Null
Push-Location $repo
& $RealGit init -q -b master
& $RealGit config user.email test@example.com
& $RealGit config user.name test
& $RealGit config commit.gpgsign false
Set-Content a.txt 'a'; & $RealGit add a.txt; & $RealGit commit -qm init
& $RealGit branch develop
& $RealGit checkout -q -b fix/ABC-124-green; Set-Content b.txt 'b'; & $RealGit add b.txt; & $RealGit commit -qm 'fix 124'
& $RealGit checkout -q master
& $RealGit branch feat/ABC-125-red
& $RealGit branch chore/safe-fix
& $RealGit tag v1.0
& $RealGit remote add origin https://example.invalid/repo.git
$head = & $RealGit rev-parse HEAD
foreach ($r in 'master', 'develop', 'feature/remote-only', 'fix/ABC-124-green') { & $RealGit update-ref "refs/remotes/origin/$r" $head }
Add-Content a.txt 'changed'                                   # modified
Set-Content login-screen.tsx 'x'                              # untracked
Set-Content 'my file.txt' 'x'                                 # untracked, needs quoting
Set-Content staged.txt 's'; & $RealGit add staged.txt         # staged

$loadTime = Measure-Command { . (Join-Path $PSScriptRoot 'omz-git.ps1') *> $null }
$runner = Join-Path $PSScriptRoot 'omz-git-run.ps1'

# --- definitions ---------------------------------------------------------------------
$bad = foreach ($name in $OmzGitSpec.Keys) {
    $c = Get-Command $name -ErrorAction SilentlyContinue
    if (-not $c -or $c.CommandType -ne 'Alias' -or $c.Definition -ne $runner) { $name }
}
Assert-Equal 'every alias resolves to the runner' '' ($bad -join ',')
$missing = foreach ($s in $OmzGitSpec.Values) { if ($s.Function -and -not (Get-Command $s.Function -CommandType Function -ErrorAction SilentlyContinue)) { $s.Name } }
Assert-Equal 'every custom alias has its function' '' ($missing -join ',')
$expected = -split @'
ga gaa gapa gau gav gwip gam gama gamc gamscp gams gap gapt gbs gbsb gbsg gbsn gbso gbsr gbss gbl gb gba gbd gbd! gbda gbds
gbgd gbgd! gbm gbnm gbr ggsup gbg gbcopy gco gcor gcb gcb! gcd gcp gcpa gcpc gclean gcl gclf gccd gcam gcas gcasm gcss gcssm
gcmsg gcsm gc gca gca! gcan! gcans! gcann! gc! gcn gcn! gcf gcfu gdct gd gdca gdcw gds gdw gdv gdup gdnolock gdt gf gfa gfo gg
gga ghh glgg glgga glgm glods glod glola glols glol glolm glo glog gloga glom glp glg glgp gignored gfg gm gma gmc gms gmff
gmom gmum gmtl gmtlvim gl gpr gprv gpra gprav ggu ggpur gprom gpromi gprum gprumi ggpull ggl gluc glum gp gpd ggf gpf! gpf
ggfl gpsup gpsupf gpoat gpod ggpush ggp ggpnp gpu grb grba grbc grbi grbo grbs grbd grbm grbom grbum grbmi grbmia grf gr grv
gra grrm grmv grset grup grh gru grhh grhk grhs gpristine gwipe groh grs grss grst gunwip gunwipall grev greva grevc grm grmc
gcount gsh gshs gsps gstall gstaa gstc gstd gstl gstp gsta gsts gst gss gsb gsnut gsi gsu gsuri gsw gswc gswd gswm gta gts
gtv gtl gignore gunignore gwch gwt gwta gwtls gwtmv gwtrm gstu gk gke grt grename
'@
Assert-Equal 'every omz alias exists' '' (($expected | Where-Object { -not $OmzGitSpec.Contains($_) }) -join ',')
Assert-Equal 'no aliases beyond omz' '' ((@($OmzGitSpec.Keys) | Where-Object { $expected -notcontains $_ }) -join ',')
foreach ($kept in 'gcm', 'gcs', 'gpv') { Assert-True "$kept is still PowerShell's" ((Get-Command $kept).Definition -notlike '*omz-git-run*') }

# --- what each alias runs ----------------------------------------------------------------
# what you type  =>  the git calls it makes (arguments joined by |, calls separated by " ; ")
$cases = @'
gco -- a.txt                       => checkout|--|a.txt
$f = "a.txt"; gco -- $f            => checkout|--|a.txt
gru a.txt                          => reset|--|a.txt
gstd stash@{1}                     => stash|drop|stash@{1}
grh HEAD@{1}                       => reset|HEAD@{1}
gd master@{upstream} -- a.txt      => diff|master@{upstream}|--|a.txt
gdup                               => diff|@{upstream}
gbd foo                            => branch|--delete|foo
gbD foo                            => branch|--delete|foo
gbd! foo                           => branch|--delete|--force|foo
grst a.txt                         => restore|--staged|a.txt
grss master a.txt                  => restore|--source|master|a.txt
gcmsg fix login bug --no-verify    => commit|--message|fix login bug|--no-verify
gcmsg -n fix it                    => commit|--message|fix it|-n
gcam "x y"                         => commit|--all|--message|x y
gcb new-branch                     => checkout|-b|new-branch
gcb! new-branch                    => checkout|-B|new-branch
gmom                               => merge|origin/master
gswd                               => switch|develop
gswm                               => switch|master
glom                               => log|--oneline|--decorate|--color|master..
gpsup                              => push|--set-upstream|origin|master
ggsup                              => branch|--set-upstream-to=origin/master
ggpush                             => push|origin|master
ggp                                => push|origin|master
ggp feat                           => push|origin|feat
ggp --force-with-lease             => push|origin|--force-with-lease|master
ggl                                => pull|origin|master
ggu                                => pull|--rebase|origin|master
ggpnp                              => pull|origin|master ; push|origin|master
gpoat                              => push|origin|--all ; push|origin|--tags
gtv                                => tag|--sort=version:refname
gfa                                => fetch|--all|--tags|--prune|--jobs=10
gpf                                => push|--force-with-lease|--force-if-includes
gsts                               => stash|show|--patch
gbr                                => branch|--remotes
gc                                 => commit|--verbose
gl                                 => pull
gm x                               => merge|x
gp                                 => push
gcb x                              => checkout|-b|x
gc! --no-edit                      => commit|--verbose|--amend|--no-edit
& 'gc!'                            => commit|--verbose|--amend
gco 124                            => checkout|124
gcount                             => shortlog|--summary|--numbered|HEAD
gdnolock                           => diff|:(exclude)package-lock.json|:(exclude)*.lock
glp oneline                        => log|--pretty=oneline
gwip                               => add|--all ; commit|--no-verify|--no-gpg-sign|--message=--wip-- [skip ci]
'@ -split '\r?\n' | Where-Object { $_.Trim() }
foreach ($row in $cases) {
    $line, $expectedCalls = $row -split '\s+=>\s+', 2
    $calls = Invoke-Recorded $line.Trim()
    Assert-Equal "runs: $($line.Trim())" ($expectedCalls.Trim() -split ' ; ') $calls
}
Assert-True 'the alias table above was read' ($cases.Count -eq 48) "rows=$($cases.Count)"
Set-Alias -Name co -Value gco -Scope Global
Assert-Equal 'your own alias pointing at one of ours (co -> gco)' 'checkout|x' (Invoke-Recorded 'co x')

# --- missing arguments: usage line, exit 1, git not called ----------------------------------
foreach ($line in 'gcmsg', 'gcmsg --amend', 'gcam', 'gcb', 'gswc', 'gam', 'gap', 'gra origin', 'glp', 'grename only-one') {
    $calls = Invoke-Recorded $line
    Assert-True "usage instead of git: $line" ($calls.Count -eq 0 -and $LASTEXITCODE -eq 1) "calls=[$($calls -join ';')] exit=$LASTEXITCODE"
}

# --- exit codes: $?, &&, || -----------------------------------------------------------------
$global:GitFailOn = 'status*'
gst *> $null
$ok = $?
Assert-True '$? is false after a failing alias' (-not $ok)
Assert-Equal 'LASTEXITCODE after a failing alias' 1 $LASTEXITCODE
$chain = $null; gst *> $null && ($chain = 'ran') | Out-Null
Assert-True '&& stops after a failing alias' ($null -eq $chain)
$or = $null; gst *> $null || ($or = 'ran') | Out-Null
Assert-True '|| runs after a failing alias' ($or -eq 'ran')
$global:GitFailOn = $null
gst *> $null
Assert-True '$? is true after a succeeding alias' $?
$global:GitFailOn = 'push origin --all*'
Assert-Equal 'gpoat skips --tags when --all fails' 'push|origin|--all' (Invoke-Recorded 'gpoat')
$global:GitFailOn = 'pull*'
Assert-Equal 'ggpnp skips the push when the pull fails' 'pull|origin|master' (Invoke-Recorded 'ggpnp')
$global:GitFailOn = $null

# --- pipeline input keeps the PowerShell meaning ---------------------------------------------
$global:GitCalls.Clear()
$members = @('x' | gm)
Assert-True "'x' | gm runs Get-Member" ($members.Count -gt 0 -and $members[0].TypeName -eq 'System.String')
Assert-Equal "'x' | gm does not call git" 0 $global:GitCalls.Count
$content = @((Get-Item a.txt) | gc)
Assert-Equal 'Get-Item a.txt | gc reads the file' 'a ; changed' $content

# --- no current branch ------------------------------------------------------------------------
& $RealGit checkout -q --detach
foreach ($line in 'ggpush', 'gpsup', 'ggp', 'groh') {
    $calls = Invoke-Recorded $line
    Assert-True "detached HEAD stops $line" ($calls.Count -eq 0 -and $LASTEXITCODE -eq 1) "calls=[$($calls -join ';')]"
}
& $RealGit checkout -q master
Push-Location $notRepo
foreach ($line in 'gpsup', 'gmom', 'grt') {
    $calls = Invoke-Recorded $line
    Assert-True "outside a repo stops $line" ($calls.Count -eq 0 -and $LASTEXITCODE -eq 1) "calls=[$($calls -join ';')]"
}
Pop-Location

# --- asks before deleting files -----------------------------------------------------------------
function global:Read-Host { $global:ReadHostAnswer }
$global:ReadHostAnswer = 'n'
$calls = Invoke-Recorded 'gpristine'
Assert-True 'gpristine: answering n changes nothing' ($calls.Count -eq 0 -and $LASTEXITCODE -eq 1) "calls=[$($calls -join ';')]"
$global:ReadHostAnswer = 'y'
Assert-Equal 'gpristine: answering y resets and cleans' @('reset|--hard', 'clean|--force|-d|-x') (Invoke-Recorded 'gpristine')
Assert-Equal 'gwipe: answering y resets and cleans' @('reset|--hard', 'clean|--force|-d') (Invoke-Recorded 'gwipe')
Remove-Item function:Read-Host

function global:Set-Clipboard { param($Value) $global:Clipboard = $Value }
$null = Invoke-Recorded 'gbcopy'
Assert-Equal 'gbcopy copies the current branch' 'master' $global:Clipboard
Remove-Item function:Set-Clipboard

# --- Tab completion -----------------------------------------------------------------------------
$global:RecordGit = $false
$c = Get-Completions 'gco 124'
Assert-Equal 'gco 124: the branch containing 124' 'fix/ABC-124-green' $c
$c = Get-Completions 'gco 124*green'
Assert-Equal 'gco: * works as a wildcard' 'fix/ABC-124-green' $c
$c = Get-Completions 'gco remote-on'
Assert-Equal 'gco: remote-only branch under the name git creates' 'feature/remote-only' $c
$c = Get-Completions 'gco origin/dev'
Assert-True 'gco origin/dev: origin/develop once "origin/" is typed' ($c -contains 'origin/develop') "got [$($c -join ', ')]"
$c = Get-Completions 'gco '
Assert-True 'gco <nothing>: local branches first' ($c[0] -in 'master', 'develop', 'fix/ABC-124-green', 'feat/ABC-125-red', 'chore/safe-fix') "first=[$($c[0])]"
Assert-True 'gco <nothing>: no origin/x unless typed' (-not ($c -like 'origin/*'))
Assert-True 'gco v1: tags' ((Get-Completions 'gco v1') -contains 'v1.0')
Assert-True 'gsw v1: no tags' (-not ((Get-Completions 'gsw v1') -contains 'v1.0'))
$c = Get-Completions 'gco fe'
Assert-True 'gco fe: names starting with fe before names that only contain it' ([array]::IndexOf($c, 'feat/ABC-125-red') -lt [array]::IndexOf($c, 'chore/safe-fix') -and [array]::IndexOf($c, 'chore/safe-fix') -ge 0) "got [$($c -join ', ')]"
Assert-Equal 'gm: remote branches with their remote' 'origin/feature/remote-only' (Get-Completions 'gm remote-on')
Assert-Equal 'gbd: local branches only' 'fix/ABC-124-green' (Get-Completions 'gbd 124')
Assert-True 'gbd: no remote-only branches' (-not ((Get-Completions 'gbd remote') -contains 'feature/remote-only'))
Assert-True 'gco -b <name>: no refs for a new name' (-not ((Get-Completions 'gco -b ') -contains 'master'))
Assert-Equal 'gco -b x <start>: any revision' 'fix/ABC-124-green' (Get-Completions 'gcb x 124' | Select-Object -First 1)
Assert-Equal 'ga login: changed file containing login' 'login-screen.tsx' (Get-Completions 'ga login')
$c = Get-Completions 'ga '
Assert-True 'ga: modified + untracked, not staged-only' (($c -contains 'a.txt') -and ($c -contains 'login-screen.tsx') -and -not ($c -contains 'staged.txt')) "got [$($c -join ', ')]"
Assert-Equal 'ga my: quoted when needed' "'my file.txt'" (Get-Completions 'ga my')
Assert-Equal 'grst: staged files' 'staged.txt' (Get-Completions 'grst ')
Assert-Equal 'grs: modified files' 'a.txt' (Get-Completions 'grs ')
Assert-Equal 'gco --: modified files' 'a.txt' (Get-Completions 'gco -- ')
$c = Get-Completions 'gd '
Assert-True 'gd: modified files, then refs' ($c[0] -eq 'a.txt' -and $c -contains 'master') "got [$($c -join ', ')]"
Assert-Equal 'gds: staged files first' 'staged.txt' (Get-Completions 'gds ' | Select-Object -First 1)
Assert-Equal 'gp origin <branch>: local branches' 'fix/ABC-124-green' (Get-Completions 'gp origin 124')
Assert-True 'gp <remote>: not completed as a branch' (-not ((Get-Completions 'gp 124') -contains 'fix/ABC-124-green'))
Assert-Equal 'gl origin <branch>: that remote''s branches' 'feature/remote-only' (Get-Completions 'gl origin remote')
Assert-Equal 'ggp: local branches' 'fix/ABC-124-green' (Get-Completions 'ggp 124')
Assert-Equal 'gpu (remote built in): branches from the 1st argument' 'fix/ABC-124-green' (Get-Completions 'gpu 124')
Assert-True 'gpu: tags too' ((Get-Completions 'gpu v1') -contains 'v1.0')
Assert-Equal 'ggpnp: origin''s branches' 'feature/remote-only' (Get-Completions 'ggpnp remote')
Assert-Equal 'gpod: origin''s branches' 'feature/remote-only' (Get-Completions 'gpod remote')
Assert-Equal 'glp: pretty formats' @('full', 'fuller') (Get-Completions 'glp ful')
& $RealGit update-ref refs/remotes/upstream/feature/remote-only $head
$c = Get-Completions 'gco remote-on'
Assert-True 'branch on two remotes: --track <remote>/x' ($c -contains '--track origin/feature/remote-only' -and $c -contains '--track upstream/feature/remote-only') "got [$($c -join ', ')]"
& $RealGit update-ref -d refs/remotes/upstream/feature/remote-only
$sw = [Diagnostics.Stopwatch]::StartNew(); $null = Get-Completions 'gco 124'; $tabMs = $sw.ElapsedMilliseconds
Assert-True 'Tab completion is quick' ($tabMs -lt 250) "$tabMs ms"

# --- real git: helpers that change branches/commits (temp repo only) -------------------------
& $RealGit branch merged-one master
& $RealGit branch gone-one master
& $RealGit config branch.gone-one.remote origin
& $RealGit config branch.gone-one.merge refs/heads/gone-one
$gbg = (gbg 6> $null) -join "`n"
Assert-True 'gbg lists the branch whose upstream is gone' ($gbg -match 'gone-one') "got [$gbg]"
gbgd *> $null
$branches = @(& $RealGit for-each-ref '--format=%(refname:short)' refs/heads)
Assert-True 'gbgd deletes the branch whose upstream is gone' ($branches -notcontains 'gone-one')
gbda *> $null
$branches = @(& $RealGit for-each-ref '--format=%(refname:short)' refs/heads)
Assert-True 'gbda deletes merged branches' ($branches -notcontains 'merged-one')
Assert-True 'gbda keeps develop, master and unmerged branches' (($branches -contains 'develop') -and ($branches -contains 'master') -and ($branches -contains 'fix/ABC-124-green')) "left: $($branches -join ', ')"
Assert-True 'gdct describes the newest tag' ("$(gdct 2>$null)" -like 'v1.0*')
Assert-Equal 'gtv lists tags' 'v1.0' (gtv)
New-Item -ItemType Directory sub | Out-Null
Set-Location sub
grt
Assert-True 'grt goes to the repository root' ((Get-Location).Path.TrimEnd('\') -eq (Resolve-Path $repo).Path.TrimEnd('\')) "at $((Get-Location).Path)"
$before = & $RealGit rev-parse HEAD
gwip *> $null
Assert-Equal 'gwip makes a --wip-- commit' '--wip-- [skip ci]' (& $RealGit log -1 --format=%s)
gunwip *> $null
Assert-Equal 'gunwip undoes it' $before (& $RealGit rev-parse HEAD)
gunwip *> $null
Assert-True 'gunwip without a wip commit fails' ($LASTEXITCODE -eq 1)

# --- clean up -------------------------------------------------------------------------------------
Set-Location $repo
Pop-Location
Remove-Item -Recurse -Force $repo, $notRepo
Remove-Item function:git

$loadMs = [int]$loadTime.TotalMilliseconds
Write-Host ''
Write-Host ("load omz-git.ps1: {0} ms   Tab (gco 124): {1} ms" -f $loadMs, $tabMs) -ForegroundColor DarkGray
$color = if ($script:failed.Count) { 'Red' } else { 'Green' }
Write-Host ("{0} passed, {1} failed" -f $script:passed, $script:failed.Count) -ForegroundColor $color
$script:failed | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
exit $script:failed.Count
