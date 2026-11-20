#!/bin/bash
# macOS setup for neovimRC + weztermRC. Safe to run again: it only installs
# what is missing and fast-forwards the configs.
#
#   ./install.sh           install what's missing, clone/update configs, sync plugins
#   ./install.sh --check   only report what's missing, change nothing
#
# Your own settings repo (~/.config/kazrc), cloned before anything starts:
#   KAZRC_REPO=git@github.com:<you>/kazRC.git ./install.sh
#
# On a fresh Mac, without cloning this repo first:
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/KazHakiStan/setupRC/master/install.sh)"

set -u

REPO_RAW="https://raw.githubusercontent.com/KazHakiStan/setupRC/master"
GITHUB_USER="KazHakiStan"
MIN_NVIM="0.12"
# repo:target
CONFIGS="neovimRC:$HOME/.config/nvim weztermRC:$HOME/.config/wezterm"

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

ok=0 added=0 missing=0 failed=0
say()  { printf '%s\n' "$*"; }
good() { printf '  \033[32m✔\033[0m %-16s %s\n' "$1" "$2"; ok=$((ok + 1)); }
new()  { printf '  \033[36m+\033[0m %-16s %s\n' "$1" "$2"; added=$((added + 1)); }
miss() { printf '  \033[33m✗\033[0m %-16s %s\n' "$1" "$2"; missing=$((missing + 1)); }
bad()  { printf '  \033[31m✗\033[0m %-16s %s\n' "$1" "$2"; failed=$((failed + 1)); }
step() { printf '\n\033[1m%s\033[0m\n' "$*"; }

[ "$(uname -s)" = "Darwin" ] || { say "install.sh is for macOS; on Windows run install.ps1"; exit 1; }

# packages.txt next to this script, or from GitHub when piped through curl
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
if [ -n "$here" ] && [ -f "$here/packages.txt" ]; then
    manifest="$(cat "$here/packages.txt")"
else
    manifest="$(curl -fsSL "$REPO_RAW/packages.txt")" || { say "can't download packages.txt"; exit 1; }
fi

# ── Xcode ───────────────────────────────────────────────────────────────────
step "Xcode"
if xcode-select -p >/dev/null 2>&1; then
    good "clt" "$(xcode-select -p)"
elif [ $CHECK = 1 ]; then
    miss "clt" "Command Line Tools: xcode-select --install"
else
    say "  installing Command Line Tools: finish the dialog, then run this script again"
    xcode-select --install
    exit 1
fi
if lldb=$(xcrun -f lldb-dap 2>/dev/null); then
    good "lldb-dap" "$lldb"
else
    miss "lldb-dap" "full Xcode from the App Store (for <leader>xr debugging), then: sudo xcode-select -s /Applications/Xcode.app"
fi

# ── Homebrew ────────────────────────────────────────────────────────────────
step "Homebrew"
for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$b" ] && eval "$("$b" shellenv)" && break
done
if command -v brew >/dev/null; then
    good "brew" "$(brew --prefix)"
elif [ $CHECK = 1 ]; then
    miss "brew" "https://brew.sh"
else
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    for b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
        [ -x "$b" ] && eval "$("$b" shellenv)" && break
    done
    command -v brew >/dev/null && new "brew" "$(brew --prefix)" || { bad "brew" "install failed"; exit 1; }
fi
have_brew=0
command -v brew >/dev/null && have_brew=1

# ── packages ────────────────────────────────────────────────────────────────
step "Packages (packages.txt)"
brew_has() { # cask:name | formula
    case "$1" in
        cask:*) brew list --cask "${1#cask:}" >/dev/null 2>&1 ;;
        *)      brew list --formula "$1" >/dev/null 2>&1 ;;
    esac
}
brew_add() {
    case "$1" in
        cask:*) brew install --cask "${1#cask:}" ;;
        *)      brew install "$1" ;;
    esac
}
while read -r check pkg _ why; do
    case "$check" in ''|'#'*) continue ;; esac
    [ "$pkg" = "-" ] && continue
    name="${pkg#cask:}"
    if [ "$check" != "-" ] && command -v "$check" >/dev/null; then
        good "$name" "$why"
    elif [ $have_brew = 1 ] && brew_has "$pkg"; then
        good "$name" "$why"
    elif [ $CHECK = 1 ] || [ $have_brew = 0 ]; then
        miss "$name" "$why"
    elif printf '  … installing %s\n' "$name" && brew_add "$pkg" </dev/null >/dev/null 2>&1; then
        new "$name" "$why"
    else
        bad "$name" "brew install failed: brew install ${pkg/cask:/--cask }"
    fi
done <<EOF
$manifest
EOF

if command -v nvim >/dev/null; then
    v=$(nvim --version | sed -n '1s/^NVIM v\([0-9]*\.[0-9]*\).*/\1/p')
    if [ "$(printf '%s\n%s\n' "$MIN_NVIM" "$v" | sort -t. -k1,1n -k2,2n | head -1)" != "$MIN_NVIM" ]; then
        bad "nvim" "version $v, config needs $MIN_NVIM+ (brew upgrade neovim)"
    fi
fi

# ── configs ─────────────────────────────────────────────────────────────────
# ── your settings (optional) ────────────────────────────────────────────────
# before the configs: a WezTerm already running reloads as soon as weztermRC
# lands and would fill ~/.config/kazrc with templates first
if [ -n "${KAZRC_REPO:-}" ]; then
    step "Your settings"
    kdir="$HOME/.config/kazrc"
    kname="$(basename "$KAZRC_REPO" .git)"
    # run by hand: ssh may ask for the key's passphrase (no agent holding it);
    # unattended: fail at once instead of waiting for an answer
    if [ -t 0 ]; then
        export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new"
    else
        export GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new"
    fi
    if git -C "$kdir" remote get-url origin 2>/dev/null | grep -qi "/$kname"; then
        if [ $CHECK = 1 ]; then
            good "kazrc" "$kdir"
        elif git -C "$kdir" pull -q --ff-only 2>/dev/null; then
            good "kazrc" "$kdir"
        else
            bad "kazrc" "$kdir: pull failed (local changes?), left as is"
        fi
    elif [ $CHECK = 1 ]; then
        miss "kazrc" "$KAZRC_REPO -> $kdir"
    else
        theme=""
        if [ -e "$kdir" ]; then
            [ -f "$kdir/theme.json" ] && theme="$(cat "$kdir/theme.json")"
            backup="$kdir.bak-$(date +%Y%m%d-%H%M%S)"
            mv "$kdir" "$backup" && say "  moved the old $kdir to $backup"
        fi
        kclone() { git clone -q "$KAZRC_REPO" "$kdir" 2>/dev/null; }
        # no access yet (a new machine): log in with gh, which can create and
        # upload an SSH key, then try once more
        gh_login() {
            [ -t 0 ] && command -v gh >/dev/null && ! gh auth status >/dev/null 2>&1 || return 1
            say "  no access to $KAZRC_REPO yet: log in to GitHub (pick SSH and let gh add a key)"
            gh auth login -h github.com -p ssh && gh auth setup-git >/dev/null 2>&1
        }
        if kclone || { gh_login && kclone; }; then
            [ -n "$theme" ] && printf '%s' "$theme" > "$kdir/theme.json"
            new "kazrc" "$kdir"
        else
            bad "kazrc" "can't clone $KAZRC_REPO: no GitHub access (gh auth login), run again"
        fi
    fi
    unset GIT_SSH_COMMAND
fi

step "Configs"
clone_url() { # ssh when GitHub accepts this machine's key, https otherwise
    if ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
        echo "git@github.com:$GITHUB_USER/$1.git"
    else
        echo "https://github.com/$GITHUB_USER/$1.git"
    fi
}
for pair in $CONFIGS; do
    repo="${pair%%:*}" dir="${pair#*:}"
    if git -C "$dir" remote get-url origin 2>/dev/null | grep -q "/$repo"; then
        if [ $CHECK = 1 ]; then
            good "$repo" "$dir"
        elif out=$(git -C "$dir" pull --ff-only 2>&1); then
            good "$repo" "$dir ($(echo "$out" | tail -1))"
        else
            bad "$repo" "$dir: pull failed (local changes?), left as is"
        fi
    elif [ $CHECK = 1 ]; then
        miss "$repo" "$dir"
    else
        if [ -e "$dir" ]; then
            backup="$dir.bak-$(date +%Y%m%d-%H%M%S)"
            mv "$dir" "$backup" && say "  moved the old $dir to $backup"
        fi
        mkdir -p "$(dirname "$dir")"
        if git clone -q "$(clone_url "$repo")" "$dir"; then new "$repo" "$dir"; else bad "$repo" "clone failed"; fi
    fi
done

# ── nvim plugins ────────────────────────────────────────────────────────────
if [ $CHECK = 0 ] && command -v nvim >/dev/null && [ -d "$HOME/.config/nvim" ]; then
    step "Neovim plugins"
    say "  plugins at the versions in lazy-lock.json…"
    nvim --headless "+Lazy! restore" "+quitall" >/dev/null 2>&1
    say "  treesitter parsers (building them takes a few minutes)…"
    left="$(nvim --headless "+lua local ts = require('kazhakistan.treesitter') local t = ts.install() if t then t:wait(1800000) end io.stdout:write('missing:' .. table.concat(ts.missing(), ' '))" "+quitall" 2>/dev/null)"
    case "$left" in
        "missing:") good "parsers" "built" ;;
        missing:*) bad "parsers" "not built: ${left#missing:} (nvim retries on the next start)" ;;
        *) bad "parsers" "couldn't check (open nvim: they build on start)" ;;
    esac
    say "  language servers install by Mason on the first nvim start (:Mason shows progress)"
fi

# ── summary ─────────────────────────────────────────────────────────────────
step "Summary"
say "  ✔ $ok present   + $added installed   ✗ $missing missing   ✗ $failed failed"
[ $CHECK = 1 ] && [ $missing -gt 0 ] && say "  run without --check to install"
[ $((missing + failed)) -eq 0 ]
