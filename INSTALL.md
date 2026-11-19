# Adding omz-git to the Chris Titus PowerShell profile

The [Chris Titus Tech PowerShell profile](https://github.com/ChrisTitusTech/powershell-profile)
overwrites `Microsoft.PowerShell_profile.ps1` every time you run `Update-Profile`, so don't edit
that file. Your own additions go in **`CTTcustom.ps1`**, in the same folder: the profile runs it
on every start, and updates leave it alone.

This is for PowerShell 7 (`pwsh`). Windows PowerShell 5.1 has its own profile folder and its own
`CTTcustom.ps1`; omz-git doesn't support it.

## 1. Put the files somewhere permanent

Clone or copy this folder. The examples below use `$HOME\projects\omz-git-pwsh`; use your own
path if you put it somewhere else.

```powershell
git clone <url of this repository> "$HOME\projects\omz-git-pwsh"
```

## 2. Open CTTcustom.ps1

In PowerShell 7:

```powershell
$custom = Join-Path (Split-Path $PROFILE) 'CTTcustom.ps1'
if (-not (Test-Path $custom)) { New-Item -ItemType File -Path $custom | Out-Null }
notepad $custom          # or: code $custom
```

## 3. Load omz-git from it

Add this at the end of `CTTcustom.ps1`:

```powershell
# oh-my-zsh git aliases (omz-git-pwsh). The Chris Titus profile runs this file *before* its own
# git shortcuts, and one of them (Set-Alias gp gpush) would replace omz-git's gp. So load
# omz-git once the whole profile has run: the first moment the prompt is idle.
$null = Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -MaxTriggerCount 1 -Action {
    . "$HOME\projects\omz-git-pwsh\omz-git.ps1" 6> $null
}
```

The aliases load a split second after the prompt appears. `6> $null` hides the
`omz git: 215 aliases` line, which would otherwise be printed in the middle of your prompt.

### Older versions of the profile: a plain line works too

Older versions of the Chris Titus profile run `CTTcustom.ps1` at the very end, with `&`. To see
which one you have:

```powershell
Select-String -Path $PROFILE -Pattern 'CTTcustom'
```

- `. $script:CustomProfile` near the top (line 17 or so): the current profile. Use the snippet
  above.
- `& (Join-Path ... 'CTTcustom.ps1')` near the end: an older profile. Nothing runs after
  `CTTcustom.ps1`, so you can load omz-git right away instead:

  ```powershell
  . "$HOME\projects\omz-git-pwsh\omz-git.ps1"
  ```

  This loads during startup (you'll see the `omz git: 215 aliases` line), and the aliases also
  exist in non-interactive shells, where the idle event never fires. If you later run
  `Update-Profile` you'll get the current profile, so switch to the snippet above then.

Not sure? Use the snippet: it works with both.

## 4. Check it

Open a new terminal, then:

```powershell
galias gco            # what gco, gcor, ... run
Get-Alias gp          # should point at ...\omz-git-run.ps1, not at gpush
gco <part of a branch name><Tab>
```

The profile already binds Tab to `MenuComplete`, so you get the menu. To run the tests:

```powershell
pwsh -NoProfile -File "$HOME\projects\omz-git-pwsh\omz-git.tests.ps1"
```

## What happens to the profile's own git shortcuts

The Chris Titus profile defines a few git shortcuts of its own. omz-git aliases take precedence
over the functions with the same name:

| You type | Chris Titus profile | With omz-git |
|---|---|---|
| `gs` | `git status` | Still the profile's `git status`: omz has no `gs` (use `gst`). |
| `ga` | `git add .` | `git add <paths>`. Use `gaa` to add everything. |
| `gc msg` | `git commit -m msg` | `git commit --verbose`, which opens your editor. Use `gcmsg msg`. |
| `gp` | `git push` | `git push`, and a failure stops `&&` chains. |
| `gcl` | `git clone` | `git clone --recurse-submodules`. |
| `gpush`, `gpull`, `gcom`, `lazyg`, `g` | | Unchanged: omz-git doesn't define them. |

## Updating and removing

- **Update:** `git -C "$HOME\projects\omz-git-pwsh" pull`, then open a new terminal.
- **Remove:** delete the lines you added to `CTTcustom.ps1` and open a new terminal.
