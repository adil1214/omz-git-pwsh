# omz-git-pwsh

The [oh-my-zsh git plugin](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/git) for
PowerShell 7: its 215 short git aliases (`gst`, `gco`, `gcmsg`, `gpsup`, ...) behaving like real
commands, plus Tab completion that finds branches, tags and changed files by any part of their
name.

```powershell
gco 124<Tab>                                  # -> gco fix/PROJ-124-login-redirect
ga login<Tab>                                 # -> ga src/screens/LoginScreen.tsx (changed files only)
gaa && gcmsg fix the login redirect && gpsup  # stops at the first failure, like in zsh
```

## Features

- **The whole omz git plugin**: every alias from the current plugin except `gcm`, `gcs`,
  `gpv` and `g`, which would hide PowerShell commands or your profile's own `g` (see
  [Differences from oh-my-zsh](#differences-from-oh-my-zsh)). Nothing that isn't in omz.
- **Real exit codes.** A failing git command sets `$?` to `$false`, so `&&` stops and `||`
  runs, and `$LASTEXITCODE` holds git's code. Plain PowerShell functions can't do that; see
  [How it works](#how-it-works).
- **Tab completion by any part of a name**, case-insensitive, newest first. Each alias offers
  what fits it: `gbd` local branches only, `gm` remote branches as `origin/x`, `grst` staged
  files only.
- **Clear messages instead of git errors when an argument is missing.** `gcb` alone prints
  `usage: gcb <new-branch> [start-point]`, and `gam`/`gap` never sit waiting on stdin.
- **Commit messages without quotes:** `gcmsg fix the login redirect --no-verify`.
- **PowerShell quirks handled:** a bare `--` (`gco -- file.txt`) and `stash@{1}` / `HEAD@{1}`
  reach git as typed. PowerShell would otherwise drop the `--` and split the others in two.
- **`galias [text]`** lists the aliases whose name or command contains `text`.

## Requirements

- PowerShell 7 (`pwsh`), tested on 7.6. Windows PowerShell 5.1 is not supported.
- git 2.30 or newer (`gpf` uses `--force-if-includes`).
- For the Tab menu: PSReadLine with Tab bound to `MenuComplete`. The Chris Titus profile already
  does this; otherwise add `Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete` to your
  profile.

## Install

- **Chris Titus PowerShell profile:** follow [INSTALL.md](INSTALL.md).
- **Any other profile:** put this folder somewhere permanent, add this line at the end of your
  profile (`notepad $PROFILE`) and open a new terminal:

  ```powershell
  . "$HOME\projects\omz-git-pwsh\omz-git.ps1"
  ```

  You'll see `omz git: 215 aliases - galias to list them` at startup.

## Using it

### Tab completion

Type any part of a name and press Tab. With `MenuComplete` you get a menu: Tab or the arrow keys
move through it, Enter accepts. Typing while the menu is open narrows it down by the start of the
name.

- Matching ignores case and works anywhere in the name. `*` and `?` are wildcards:
  `gco 124*login`.
- Names that start with what you typed (or whose last `/` part does) come first, then local
  branches, remote branches, tags; newest commit first. The tooltip shows the date and the
  commit subject.
- When nothing matches, PowerShell falls back to its usual file-name completion.
- Files are relative to the current folder and limited to it, like git's own completion.

| Typed | Offers |
|---|---|
| `gco`, `gcor` | Local branches, then remote-only branches under the name git creates them with (`--track origin/x` if several remotes have one), then tags. `origin/x` itself once you type `origin/`. After `--`: modified files. After `-b`/`-B`: nothing, you're naming a new branch. |
| `gsw` | Local and remote-only branches (no tags). |
| `gcb`, `gcb!`, `gswc` | 2nd argument: any revision. |
| `gb`, `gbd`, `gbd!`, `gbm`, `grename` | Local branches only. |
| `gm`, `grb`, `grbi`, `gcp`, `glo`, `glol`, `gsh`, `grh`, `grev`, ... | Revisions: local branches, remote branches as `origin/x`, tags. |
| `gd`, `gdw`, `gdv`, `gdnolock` | Modified files, then revisions. |
| `gds`, `gdca`, `gdcw` | Staged files, then revisions. |
| `ga`, `gaa`, `gav` | Modified, deleted and untracked files. |
| `gau`, `gapa`, `grs` | Modified tracked files. |
| `grst`, `gru` | Staged files. |
| `gp`, `gpd`, `gpf`, `gpf!` | From the 2nd argument on (the 1st is the remote): local branches and tags. |
| `ggp`, `ggf`, `ggfl`, `gpu` | Local branches and tags (the remote is built in). |
| `gl`, `gpr`, `gprv`, `gpra`, `gprav`, `gf` | From the 2nd argument on: that remote's branches. |
| `ggl`, `ggu`, `ggpur`, `ggpnp`, `gfo`, `gpod` | origin's branches. |
| `glp` | Pretty formats (`oneline`, `short`, `full`, ...). |

### Branch placeholders

Some aliases look a branch up when they run. They show up in the tables below as:

- `<branch>`: the current branch. On a detached HEAD or outside a repository the alias stops
  with a message instead of running git with the wrong name.
- `<main>`: the first of main, trunk, mainline, default, stable and master found locally, then
  on origin, then on upstream; then whatever origin/HEAD points at; then master. Same rules as
  omz.
- `<develop>`: the first of dev, devel, develop and development that exists, else develop.

### Exit codes and chains

```powershell
gaa && gcmsg wip && gp     # nothing is pushed if the commit fails
grbc || grba               # abort the rebase if continuing it fails
```

### PowerShell syntax to watch out for

- `@{u}` means a hash table to PowerShell and can't be typed unquoted. Write `'@{u}'`, or use
  `gdup` for `git diff @{upstream}`. `stash@{1}`, `HEAD@{1}` and `main@{upstream}` work as
  typed.
- For the commit aliases, the message ends at the first word that starts with `-`:
  `gcmsg fix it -n` commits "fix it" with `-n`.
- `gc`, `gl`, `gm`, `gp` and `gcb` run git, not Get-Content, Get-Location, Get-Member,
  Get-ItemProperty and Get-Clipboard. Use `cat`, `pwd` or the full cmdlet names. Piping into
  `gc`, `gm` or `gp` still runs the PowerShell command: `$x | gm` works as before.

## Commands

<!-- commands:start -->
215 aliases. `<branch>` is the current branch, `<main>` and `<develop>` the detected main and develop branches (see [Branch placeholders](#branch-placeholders)). Anything you type after an alias is passed on to git.

### Add, apply, am

| Alias | Runs | Notes |
|---|---|---|
| `ga` | `git add` |  |
| `gaa` | `git add --all` |  |
| `gapa` | `git add --patch` |  |
| `gau` | `git add --update` |  |
| `gav` | `git add --verbose` |  |
| `gam` | `git am <mbox-or-patch>...` |  |
| `gama` | `git am --abort` |  |
| `gamc` | `git am --continue` |  |
| `gamscp` | `git am --show-current-patch` |  |
| `gams` | `git am --skip` |  |
| `gap` | `git apply <patch>...` |  |
| `gapt` | `git apply --3way <patch>...` |  |
| `gwip` | `git add --all + commit --no-verify --no-gpg-sign -m "--wip-- [skip ci]"` |  |

### Bisect and blame

| Alias | Runs | Notes |
|---|---|---|
| `gbs` | `git bisect` |  |
| `gbsb` | `git bisect bad` |  |
| `gbsg` | `git bisect good` |  |
| `gbsn` | `git bisect new` |  |
| `gbso` | `git bisect old` |  |
| `gbsr` | `git bisect reset` |  |
| `gbss` | `git bisect start` |  |
| `gbl` | `git blame -w <file>` |  |

### Branch

| Alias | Runs | Notes |
|---|---|---|
| `gb` | `git branch` |  |
| `gba` | `git branch --all` |  |
| `gbd` | `git branch --delete <branch>...` |  |
| `gbd!` | `git branch --delete --force <branch>...` | omz `gbD` |
| `gbm` | `git branch --move [old-branch] <new-branch>` |  |
| `gbnm` | `git branch --no-merged` |  |
| `gbr` | `git branch --remotes` |  |
| `ggsup` | `git branch --set-upstream-to=origin/<branch>` |  |
| `gbda` | `git branch --delete: every branch merged into HEAD (keeps current, main, develop)` |  |
| `gbds` | `git branch -D: every branch squash-merged into main (keeps current, main, develop)` |  |
| `gbg` | `git branch -vv: branches whose upstream is gone` |  |
| `gbgd` | `git branch --delete: branches whose upstream is gone` |  |
| `gbgd!` | `git branch -D: branches whose upstream is gone (omz gbgD)` | omz `gbgD` |
| `gbcopy` | `copy the current branch name to the clipboard` |  |
| `grename` | `git branch --move <old> <new> + rename it on origin` |  |

### Checkout and switch

| Alias | Runs | Notes |
|---|---|---|
| `gco` | `git checkout` |  |
| `gcor` | `git checkout --recurse-submodules` |  |
| `gcb` | `git checkout -b <new-branch> [start-point]` | Replaces PowerShell's `gcb` (Get-Clipboard). |
| `gcb!` | `git checkout -B <branch> [start-point]` | omz `gcB` |
| `gcd` | `git checkout <develop>` |  |
| `gsw` | `git switch` |  |
| `gswc` | `git switch --create <new-branch> [start-point]` |  |
| `gswd` | `git switch <develop>` |  |
| `gswm` | `git switch <main>` |  |

### Cherry-pick and revert

| Alias | Runs | Notes |
|---|---|---|
| `gcp` | `git cherry-pick <commit>...` |  |
| `gcpa` | `git cherry-pick --abort` |  |
| `gcpc` | `git cherry-pick --continue` |  |
| `grev` | `git revert` |  |
| `greva` | `git revert --abort` |  |
| `grevc` | `git revert --continue` |  |

### Clean and clone

| Alias | Runs | Notes |
|---|---|---|
| `gclean` | `git clean --interactive -d` |  |
| `gcl` | `git clone --recurse-submodules <repo> [dir]` |  |
| `gclf` | `git clone --recursive --shallow-submodules --filter=blob:none --also-filter-submodules <repo> [dir]` |  |
| `gccd` | `git clone --recurse-submodules <repo> [dir], then cd into it` |  |

### Commit

| Alias | Runs | Notes |
|---|---|---|
| `gcam` | `git commit --all --message <message> [git commit options]` | The words you type (up to the first `-option`) become the message. |
| `gcas` | `git commit --all --signoff` |  |
| `gcasm` | `git commit --all --signoff --message <message> [git commit options]` | The words you type (up to the first `-option`) become the message. |
| `gcss` | `git commit --gpg-sign --signoff` |  |
| `gcssm` | `git commit --gpg-sign --signoff --message <message> [git commit options]` | The words you type (up to the first `-option`) become the message. |
| `gcmsg` | `git commit --message <message> [git commit options]` | The words you type (up to the first `-option`) become the message. |
| `gcsm` | `git commit --signoff --message <message> [git commit options]` | The words you type (up to the first `-option`) become the message. |
| `gc` | `git commit --verbose` | Replaces PowerShell's `gc` (Get-Content); piping into it still runs Get-Content. |
| `gca` | `git commit --verbose --all` |  |
| `gca!` | `git commit --verbose --all --amend` |  |
| `gcan!` | `git commit --verbose --all --no-edit --amend` |  |
| `gcans!` | `git commit --verbose --all --signoff --no-edit --amend` |  |
| `gcann!` | `git commit --verbose --all --date=now --no-edit --amend` |  |
| `gc!` | `git commit --verbose --amend` |  |
| `gcn` | `git commit --verbose --no-edit` |  |
| `gcn!` | `git commit --verbose --no-edit --amend` |  |
| `gcfu` | `git commit --fixup <commit>` |  |

### Diff

| Alias | Runs | Notes |
|---|---|---|
| `gd` | `git diff` |  |
| `gdca` | `git diff --cached` |  |
| `gdcw` | `git diff --cached --word-diff` |  |
| `gds` | `git diff --staged` |  |
| `gdw` | `git diff --word-diff` |  |
| `gdv` | `git diff -w` | omz pipes this into `view -`; here it uses git's pager. |
| `gdup` | `git diff @{upstream}` | Saves you quoting `'@{upstream}'` in PowerShell. |
| `gdt` | `git diff-tree --no-commit-id --name-only -r <commit>` |  |
| `gdnolock` | `git diff, without package-lock.json and *.lock` |  |

### Fetch and pull

| Alias | Runs | Notes |
|---|---|---|
| `gf` | `git fetch` |  |
| `gfa` | `git fetch --all --tags --prune --jobs=10` |  |
| `gfo` | `git fetch origin` |  |
| `gl` | `git pull` | Replaces PowerShell's `gl` (Get-Location). |
| `gpr` | `git pull --rebase` |  |
| `gprv` | `git pull --rebase -v` |  |
| `gpra` | `git pull --rebase --autostash` |  |
| `gprav` | `git pull --rebase --autostash -v` |  |
| `gprom` | `git pull --rebase origin <main>` |  |
| `gpromi` | `git pull --rebase=interactive origin <main>` |  |
| `gprum` | `git pull --rebase upstream <main>` |  |
| `gprumi` | `git pull --rebase=interactive upstream <main>` |  |
| `ggpull` | `git pull origin <branch>` |  |
| `gluc` | `git pull upstream <branch>` |  |
| `glum` | `git pull upstream <main>` |  |
| `ggl` | `git pull origin <branch> (default: current)` |  |
| `ggu` | `git pull --rebase origin <branch> (default: current)` |  |
| `ggpur` | `git pull --rebase origin <branch> (default: current)` |  |
| `ggpnp` | `git pull origin <branch> && git push origin <branch> (default: current)` |  |

### Log and history

| Alias | Runs | Notes |
|---|---|---|
| `glgg` | `git log --graph` |  |
| `glgga` | `git log --graph --decorate --all` |  |
| `glgm` | `git log --graph --max-count=10` |  |
| `glods` | `git log --graph --pretty=<lol-date> --date=short` |  |
| `glod` | `git log --graph --pretty=<lol-date>` |  |
| `glola` | `git log --graph --pretty=<lol> --all` |  |
| `glols` | `git log --graph --pretty=<lol> --stat` |  |
| `glol` | `git log --graph --pretty=<lol>` |  |
| `glolm` | `git log <main> --graph --pretty=<lol>` |  |
| `glo` | `git log --oneline --decorate` |  |
| `glog` | `git log --oneline --decorate --graph` |  |
| `gloga` | `git log --oneline --decorate --graph --all` |  |
| `glom` | `git log --oneline --decorate --color <main>..` |  |
| `glg` | `git log --stat` |  |
| `glgp` | `git log --stat --patch` |  |
| `gwch` | `git log --patch --abbrev-commit --pretty=medium --raw` |  |
| `grf` | `git reflog` |  |
| `gdct` | `git describe --tags <newest tag>` |  |
| `glp` | `git log --pretty=<format>` |  |
| `gcount` | `git shortlog --summary --numbered` | Adds `HEAD` when you give no revision, so it never waits on stdin. |

`<lol>` is `%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ar) %C(bold blue)<%an>%Creset`; `<lol-date>` is the same with `%ad` (author date) instead of `%ar`.

### Merge

| Alias | Runs | Notes |
|---|---|---|
| `gm` | `git merge` | Replaces PowerShell's `gm` (Get-Member); `$x \| gm` still runs Get-Member. |
| `gma` | `git merge --abort` |  |
| `gmc` | `git merge --continue` |  |
| `gms` | `git merge --squash` |  |
| `gmff` | `git merge --ff-only` |  |
| `gmom` | `git merge origin/<main>` |  |
| `gmum` | `git merge upstream/<main>` |  |
| `gmtl` | `git mergetool --no-prompt` |  |
| `gmtlvim` | `git mergetool --no-prompt --tool=vimdiff` |  |

### Push

| Alias | Runs | Notes |
|---|---|---|
| `gp` | `git push` | Replaces PowerShell's `gp` (Get-ItemProperty); piping into it still runs Get-ItemProperty. |
| `gpd` | `git push --dry-run` |  |
| `gpf!` | `git push --force` |  |
| `gpf` | `git push --force-with-lease --force-if-includes` |  |
| `gpsup` | `git push --set-upstream origin <branch>` |  |
| `gpsupf` | `git push --set-upstream origin <branch> --force-with-lease --force-if-includes` |  |
| `gpod` | `git push origin --delete <branch>...` |  |
| `ggpush` | `git push origin <branch>` |  |
| `gpu` | `git push upstream` |  |
| `ggp` | `git push origin <branch> (default: current)` |  |
| `ggf` | `git push --force origin <branch> (default: current)` |  |
| `ggfl` | `git push --force-with-lease origin <branch> (default: current)` |  |
| `gpoat` | `git push origin --all && git push origin --tags` |  |

### Rebase

| Alias | Runs | Notes |
|---|---|---|
| `grb` | `git rebase` |  |
| `grba` | `git rebase --abort` |  |
| `grbc` | `git rebase --continue` |  |
| `grbi` | `git rebase --interactive` |  |
| `grbo` | `git rebase --onto` |  |
| `grbs` | `git rebase --skip` |  |
| `grbd` | `git rebase <develop>` |  |
| `grbm` | `git rebase <main>` |  |
| `grbom` | `git rebase origin/<main>` |  |
| `grbum` | `git rebase upstream/<main>` |  |
| `grbmi` | `git rebase <main> --interactive` |  |
| `grbmia` | `git rebase <main> --interactive --autosquash` |  |

### Remote

| Alias | Runs | Notes |
|---|---|---|
| `gr` | `git remote` |  |
| `grv` | `git remote --verbose` |  |
| `gra` | `git remote add <name> <url>` |  |
| `grrm` | `git remote remove <name>` |  |
| `grmv` | `git remote rename <old> <new>` |  |
| `grset` | `git remote set-url <name> <url>` |  |
| `grup` | `git remote update` |  |

### Reset, restore, rm

| Alias | Runs | Notes |
|---|---|---|
| `grh` | `git reset` |  |
| `gru` | `git reset --` |  |
| `grhh` | `git reset --hard` |  |
| `grhk` | `git reset --keep` |  |
| `grhs` | `git reset --soft` |  |
| `groh` | `git reset origin/<branch> --hard` |  |
| `grs` | `git restore` |  |
| `grss` | `git restore --source` |  |
| `grst` | `git restore --staged` |  |
| `grm` | `git rm <path>...` |  |
| `grmc` | `git rm --cached <path>...` |  |
| `gunwip` | `git reset HEAD~1 when the last commit is a --wip-- commit` |  |
| `gunwipall` | `git reset to the newest commit that is not --wip--` |  |
| `gpristine` | `git reset --hard && git clean -d -x --force (asks first)` |  |
| `gwipe` | `git reset --hard && git clean -d --force (asks first)` |  |

### Show and status

| Alias | Runs | Notes |
|---|---|---|
| `gsh` | `git show` |  |
| `gshs` | `git show --stat` |  |
| `gsps` | `git show --pretty=short --show-signature` |  |
| `gst` | `git status` |  |
| `gss` | `git status --short` |  |
| `gsb` | `git status --short --branch` |  |
| `gsnut` | `git status --untracked-files=no` |  |

### Stash

| Alias | Runs | Notes |
|---|---|---|
| `gstall` | `git stash --all` |  |
| `gstaa` | `git stash apply` |  |
| `gstc` | `git stash clear` |  |
| `gstd` | `git stash drop` |  |
| `gstl` | `git stash list` |  |
| `gstp` | `git stash pop` |  |
| `gsta` | `git stash push` |  |
| `gsts` | `git stash show --patch` |  |
| `gstu` | `git stash push --include-untracked` |  |

### Submodule

| Alias | Runs | Notes |
|---|---|---|
| `gsi` | `git submodule init` |  |
| `gsu` | `git submodule update` |  |
| `gsuri` | `git submodule update --recursive --init` |  |

### Tag

| Alias | Runs | Notes |
|---|---|---|
| `gta` | `git tag --annotate <tag> [commit]` |  |
| `gts` | `git tag --sign <tag> [commit]` |  |
| `gtv` | `git tag --sort=version:refname` | Same order as omz's `git tag \| sort -V`. |
| `gtl` | `git tag --sort=-v:refname -n --list "<prefix>*"` |  |

### Tracked files

| Alias | Runs | Notes |
|---|---|---|
| `gignore` | `git update-index --assume-unchanged <file>...` |  |
| `gunignore` | `git update-index --no-assume-unchanged <file>...` |  |
| `gfg` | `git ls-files, filtered by a regex` |  |
| `gignored` | `git ls-files -v: assume-unchanged files` |  |

### Worktree

| Alias | Runs | Notes |
|---|---|---|
| `gwt` | `git worktree` |  |
| `gwta` | `git worktree add <path> [commit-ish]` |  |
| `gwtls` | `git worktree list` |  |
| `gwtmv` | `git worktree move <worktree> <new-path>` |  |
| `gwtrm` | `git worktree remove <worktree>` |  |

### Config, help, GUI

| Alias | Runs | Notes |
|---|---|---|
| `gcf` | `git config --list` |  |
| `gg` | `git gui citool` |  |
| `gga` | `git gui citool --amend` |  |
| `ghh` | `git help` |  |

### Other

| Alias | Runs | Notes |
|---|---|---|
| `gk` | `gitk --all --branches, in the background` |  |
| `gke` | `gitk --all <reflog commits>, in the background` |  |
| `grt` | `cd $(git rev-parse --show-toplevel)` |  |
<!-- commands:end -->

## Differences from oh-my-zsh

- PowerShell names ignore case, so the omz aliases that differ only by case use `!` instead,
  the plugin's own mark for the forceful variant:

  | omz | here | Runs |
  |---|---|---|
  | `gbD` | `gbd!` | `git branch --delete --force` |
  | `gcB` | `gcb!` | `git checkout -B` |
  | `gbgD` | `gbgd!` | `git branch -D` on branches whose upstream is gone |

  `gbd`, `gcb` and `gbgd` keep their omz meaning, so typing `gbD` runs the *safe* delete.
- Not defined, because they would hide common PowerShell commands:
  - `gcm`: Get-Command. Use `gswm` or `gco <main>`.
  - `gcs`: Get-PSCallStack. Use `gc -S`.
  - `gpv`: Get-ItemPropertyValue. Use `gp -v`.
  - `g`: many profiles already use it, the Chris Titus one included.

  The git-svn aliases (`gsd`, `gsr`, `git-svn-dcommit-push`) are not ported.
- `gdv` uses git's pager; omz pipes it into `view -`, which Windows doesn't have.
- `gpristine` and `gwipe` list what `git clean` would delete and ask `[y/N]` first, because
  deleted untracked files can't be recovered, not even from the reflog.
- `ggl`, `ggp`, `ggu`, `ggf` and `ggfl` pass several arguments on separately; omz joins them into
  one string, which git rejects. Given only options (`ggp --force-with-lease`), they still use
  the current branch.
- `gbg` and `gbgd` read the upstream state with `git for-each-ref`, whose output is never
  translated, so they work whatever language git speaks. omz forces `LANG=C` for the same
  reason.

## How it works

| File | |
|---|---|
| `omz-git.ps1` | The alias table, the aliases that need logic (`OmzGit_<name>` functions), Tab completion and `galias`. |
| `omz-git-run.ps1` | Every alias points at this script. A script ending in `exit N` sets `$?` for the caller (a function can't), which is what makes `&&` and `||` work. |
| `omz-git.tests.ps1` | The tests. |
| `tools/Update-Readme.ps1` | Rebuilds the command tables in this README from `omz-git.ps1`. |
| `INSTALL.md` | Setup in the Chris Titus PowerShell profile. |

To add an alias, add a line to `$aliases` in `omz-git.ps1` (`name = 'git words'`), then run
`pwsh -NoProfile -File tools\Update-Readme.ps1` to update this README.

## Tests

```powershell
pwsh -NoProfile -File omz-git.tests.ps1
```

They build a throwaway repository in `%TEMP%` and check what each alias runs, missing arguments,
exit codes and Tab completion. A stand-in `git` records the commands that would change something
instead of running them, so nothing outside the temp folder is touched.

## Credits

The alias names and what they do come from the
[oh-my-zsh git plugin](https://github.com/ohmyzsh/ohmyzsh/tree/master/plugins/git)
(MIT License).
