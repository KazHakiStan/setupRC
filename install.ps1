# Windows setup for neovimRC + weztermRC. Safe to run again: it only installs
# what is missing and fast-forwards the configs. Works in Windows PowerShell 5.1
# (a fresh Windows) and in pwsh. No admin needed (Scoop installs per user).
#
#   .\install.ps1          install what's missing, clone/update configs, sync plugins
#   .\install.ps1 -Check   only report what's missing, change nothing
#
# Your own settings repo (~\.config\kazrc), cloned before anything starts:
#   $env:KAZRC_REPO = "git@github.com:<you>/kazRC.git"; .\install.ps1
#
# On a fresh machine, without cloning this repo first:
#   irm https://raw.githubusercontent.com/KazHakiStan/setupRC/master/install.ps1 | iex
#   & ([scriptblock]::Create((irm https://raw.githubusercontent.com/KazHakiStan/setupRC/master/install.ps1))) -Check

param([switch]$Check)

$ErrorActionPreference = "Continue"
$RepoRaw = "https://raw.githubusercontent.com/KazHakiStan/setupRC/master"
$GithubUser = "KazHakiStan"
$MinNvim = [version]"0.12"
$Configs = @(
    @{ Repo = "neovimRC";  Dir = Join-Path $env:LOCALAPPDATA "nvim" },
    @{ Repo = "weztermRC"; Dir = Join-Path $HOME ".config\wezterm" }
)

$script:n = @{ ok = 0; added = 0; missing = 0; failed = 0 }
function Line($mark, $color, $name, $text) { Write-Host ("  {0} " -f $mark) -ForegroundColor $color -NoNewline; Write-Host ("{0,-16} {1}" -f $name, $text) }
function Good($name, $text) { Line "[ok]" Green  $name $text; $script:n.ok++ }
function New($name, $text)  { Line "[+] " Cyan   $name $text; $script:n.added++ }
function Miss($name, $text) { Line "[ ] " Yellow $name $text; $script:n.missing++ }
function Bad($name, $text)  { Line "[x] " Red    $name $text; $script:n.failed++ }
function Step($text) { Write-Host ""; Write-Host $text -ForegroundColor White }
function Has($cmd) { [bool](Get-Command $cmd -ErrorAction SilentlyContinue) }

# packages.txt next to this script, or from GitHub when run through iex
if ($PSScriptRoot -and (Test-Path (Join-Path $PSScriptRoot "packages.txt"))) {
    $manifest = Get-Content (Join-Path $PSScriptRoot "packages.txt")
} else {
    $manifest = (Invoke-RestMethod "$RepoRaw/packages.txt") -split "`r?`n"
}

# ---- Scoop -------------------------------------------------------------------
Step "Scoop"
$scoopRoot = if ($env:SCOOP) { $env:SCOOP } else { Join-Path $HOME "scoop" }
if (Has scoop) {
    Good "scoop" $scoopRoot
} elseif ($Check) {
    Miss "scoop" "https://scoop.sh"
} else {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
    Invoke-RestMethod get.scoop.sh | Invoke-Expression
    $env:PATH = "$scoopRoot\shims;$env:PATH"
    if (Has scoop) { New "scoop" $scoopRoot } else { Bad "scoop" "install failed"; exit 1 }
}
$haveScoop = Has scoop

# ---- packages ----------------------------------------------------------------
Step "Packages (packages.txt)"
function ScoopHas($app) { Test-Path (Join-Path $scoopRoot "apps\$app\current") }

# scoop itself needs git and 7zip to add buckets and unpack: those go first
$rows = foreach ($l in $manifest) {
    if ($l -match '^\s*(#|$)') { continue }
    $f = $l.Trim() -split '\s+', 4
    if ($f[2] -eq "-") { continue }
    [pscustomobject]@{ Check = $f[0]; Pkg = $f[2]; Why = $(if ($f.Count -gt 3) { $f[3] } else { "" }) }
}
$rows = @($rows | Where-Object { $_.Pkg -in "git", "7zip" }) + @($rows | Where-Object { $_.Pkg -notin "git", "7zip" })

foreach ($r in $rows) {
    $bucket = $null; $app = $r.Pkg
    if ($r.Pkg -like "*/*") { $bucket, $app = $r.Pkg -split "/", 2 }
    if (($r.Check -ne "-" -and (Has $r.Check)) -or ($haveScoop -and (ScoopHas $app))) {
        Good $app $r.Why
    } elseif ($Check -or -not $haveScoop) {
        Miss $app $r.Why
    } else {
        Write-Host "  ... installing $app"
        if ($bucket -and -not (Test-Path (Join-Path $scoopRoot "buckets\$bucket"))) { scoop bucket add $bucket *> $null }
        scoop install $r.Pkg *> $null
        if (ScoopHas $app) { New $app $r.Why } else { Bad $app "scoop install $($r.Pkg) failed" }
    }
}
$env:PATH = "$scoopRoot\shims;$env:PATH"

if (Has nvim) {
    $v = [version]((nvim --version | Select-Object -First 1) -replace '^NVIM v(\d+\.\d+).*', '$1')
    if ($v -lt $MinNvim) { Bad "nvim" "version $v, config needs $MinNvim+ (scoop update neovim)" }
}

# ---- configs -----------------------------------------------------------------
# ---- your settings (optional) -------------------------------------------------
# before the configs: a WezTerm already running reloads as soon as weztermRC
# lands and would fill ~\.config\kazrc with templates first
if ($env:KAZRC_REPO) {
    Step "Your settings"
    $kdir = Join-Path $HOME ".config\kazrc"
    $kname = [IO.Path]::GetFileNameWithoutExtension(($env:KAZRC_REPO -split "[/:]")[-1])
    $env:GIT_SSH_COMMAND = "ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new"
    $korigin = if (Test-Path (Join-Path $kdir ".git")) { git -C $kdir remote get-url origin 2>$null } else { "" }
    if ($korigin -match "/$kname") {
        if ($Check) { Good "kazrc" $kdir }
        else {
            git -C $kdir pull -q --ff-only 2>$null
            if ($LASTEXITCODE -eq 0) { Good "kazrc" $kdir } else { Bad "kazrc" "${kdir}: pull failed (local changes?), left as is" }
        }
    } elseif ($Check) {
        Miss "kazrc" "$($env:KAZRC_REPO) -> $kdir"
    } else {
        $theme = $null
        if (Test-Path $kdir) {
            $tf = Join-Path $kdir "theme.json"
            if (Test-Path $tf) { $theme = Get-Content $tf -Raw }
            $backup = "$kdir.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
            Move-Item $kdir $backup
            Write-Host "  moved the old $kdir to $backup"
        }
        git clone -q $env:KAZRC_REPO $kdir 2>$null
        if ($LASTEXITCODE -eq 0) {
            if ($theme) { Set-Content -NoNewline -Path (Join-Path $kdir "theme.json") -Value $theme }
            New "kazrc" $kdir
        } else {
            Bad "kazrc" "can't clone $($env:KAZRC_REPO): set up GitHub access (ssh key or gh auth login), run again"
        }
    }
    Remove-Item Env:GIT_SSH_COMMAND
}

Step "Configs"
function CloneUrl($repo) {
    $ssh = (ssh -o BatchMode=yes -o ConnectTimeout=5 -T git@github.com 2>&1) -join " "
    if ($ssh -match "successfully authenticated") { "git@github.com:$GithubUser/$repo.git" } else { "https://github.com/$GithubUser/$repo.git" }
}
foreach ($c in $Configs) {
    $origin = if (Test-Path (Join-Path $c.Dir ".git")) { git -C $c.Dir remote get-url origin 2>$null } else { "" }
    if ($origin -match "/$($c.Repo)") {
        if ($Check) { Good $c.Repo $c.Dir; continue }
        $out = git -C $c.Dir pull --ff-only 2>&1
        if ($LASTEXITCODE -eq 0) { Good $c.Repo "$($c.Dir) ($(@($out)[-1]))" } else { Bad $c.Repo "$($c.Dir): pull failed (local changes?), left as is" }
    } elseif ($Check) {
        Miss $c.Repo $c.Dir
    } else {
        if (Test-Path $c.Dir) {
            $backup = "$($c.Dir).bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
            Move-Item $c.Dir $backup
            Write-Host "  moved the old $($c.Dir) to $backup"
        }
        New-Item -ItemType Directory -Force (Split-Path $c.Dir) | Out-Null
        git clone -q (CloneUrl $c.Repo) $c.Dir
        if ($LASTEXITCODE -eq 0) { New $c.Repo $c.Dir } else { Bad $c.Repo "clone failed" }
    }
}

# ---- nvim plugins ------------------------------------------------------------
if (-not $Check -and (Has nvim) -and (Test-Path $Configs[0].Dir)) {
    Step "Neovim plugins"
    Write-Host "  plugins at the versions in lazy-lock.json..."
    nvim --headless "+Lazy! restore" "+quitall" *> $null
    Write-Host "  treesitter parsers..."
    nvim --headless "+lua local t = require('kazhakistan.treesitter').install() if t then t:wait(600000) end" "+quitall" *> $null
    Write-Host "  language servers install by Mason on the first nvim start (:Mason shows progress)"
}

# ---- summary -----------------------------------------------------------------
Step "Summary"
Write-Host ("  ok {0}   installed {1}   missing {2}   failed {3}" -f $n.ok, $n.added, $n.missing, $n.failed)
if ($Check -and $n.missing -gt 0) { Write-Host "  run without -Check to install" }
