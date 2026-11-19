# setupRC

One script to set up [neovimRC](https://github.com/KazHakiStan/neovimRC) and
[weztermRC](https://github.com/KazHakiStan/weztermRC) on a new machine, or to
check that an existing one has everything they need.

What the configs need lives in [`packages.txt`](packages.txt). Both scripts read
it, install whatever is missing, clone or update the configs, and sync nvim's
plugins. They are safe to run again: present things are skipped.

## macOS

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/KazHakiStan/setupRC/master/install.sh)"
```

Or from a clone: `./install.sh`, or `./install.sh --check` to only report.

Installs Homebrew if needed and checks Xcode (lldb-dap for debugging comes with
the full Xcode from the App Store; the script only reminds about it).

## Windows

In PowerShell (no admin):

```powershell
irm https://raw.githubusercontent.com/KazHakiStan/setupRC/master/install.ps1 | iex
```

Or from a clone: `.\install.ps1`, or `.\install.ps1 -Check` to only report.

Installs Scoop if needed. nvim's config goes to `%LOCALAPPDATA%\nvim`, WezTerm's
to `~\.config\wezterm`.

## Where things go

| | macOS | Windows |
|---|---|---|
| packages | Homebrew | Scoop |
| nvim config | `~/.config/nvim` | `%LOCALAPPDATA%\nvim` |
| WezTerm config | `~/.config/wezterm` | `~\.config\wezterm` |

A config folder that exists but isn't the repo gets moved aside to
`<folder>.bak-<date>` before cloning. Configs are cloned over SSH when GitHub
accepts the machine's key, over HTTPS otherwise.

Language servers are installed by Mason on nvim's first start (`:Mason`).

## Your settings

The configs stay as they are in their repos, so `git pull` always updates them
cleanly. Personal settings live outside, in `~/.config/kazrc/`, created on the
first start with every default commented out:

| file | opens with | what's in it |
|---|---|---|
| `wezterm.lua` | `LEADER e` | shell, font, leader, window, themes and backgrounds, status bar words and glyphs |
| `nvim.lua` | `:KazConfig` | leader, vim options, theme order, completion Tab, projects, LSP servers, parsers, your own plugins and keymaps |
| `themes.lua` | | theme order and default, shared by both |
| `theme.json` | `LEADER t`, `:Theme` | the current theme, shared by both |

Keep them in a private repo of your own, and setupRC clones it first on a new
machine (before nvim or WezTerm could create the templates):

```sh
KAZRC_REPO=git@github.com:<you>/kazRC.git ./install.sh
```
```powershell
$env:KAZRC_REPO = "git@github.com:<you>/kazRC.git"; .\install.ps1
```

A private repo needs GitHub access. On a new machine without it, the script
runs `gh auth login` (pick SSH and gh creates and uploads a key) and tries
again; skip that and the step is reported and skipped. `theme.json` is per machine:
leave it out of the repo.

Uncomment what you change; saving applies it. A typo or a broken file never
breaks anything: those settings stay at their defaults and the problem is
shown (WezTerm's bar, nvim's `:KazProblems`).

## Adding a dependency

Add a line to `packages.txt`: the command to look for, the brew and scoop
package names (`-` where it isn't needed), and what uses it.
