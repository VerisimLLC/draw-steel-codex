# deploy.ps1 - copy changed Lua files from this repo into the Codex's dev-mod
# "git folder", which is where the running app actually reads checked-out mod
# source from (confirmed via Player.log "MOD:: READ CONTENTS FOR MOD ... from"
# lines). Editing the repo alone does NOT change what the app runs. See
# CLAUDE.md ("Deploying Changes to the Running Codex").
#
# The git folder location comes from the app's settings:
#   %USERPROFILE%\AppData\LocalLow\MCDM\Codex\mods\settings.json -> "gitfolder"
# Inside it, each checked-out module is a folder named exactly like the repo's
# module directory (e.g. "Draw Steel V"), holding that module's .lua files.
#
# Usage:
#   .\deploy.ps1                  deploy every git-modified .lua file
#   .\deploy.ps1 -Check           dry run: report what would be deployed
#   .\deploy.ps1 <paths...>       deploy specific repo-relative files

param(
    [switch]$Check,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Paths
)

$ErrorActionPreference = "Stop"

$repo = $PSScriptRoot

# Resolve the app's git folder from its settings; fall back to the known default.
$gitFolder = "C:\Users\theli\codex-dev-mods"
$settingsPath = Join-Path $env:USERPROFILE "AppData\LocalLow\MCDM\Codex\mods\settings.json"
if (Test-Path $settingsPath) {
    try {
        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
        if ($settings.gitfolder) {
            $gitFolder = $settings.gitfolder -replace '/', '\'
        }
    } catch {}
}

if (-not (Test-Path $gitFolder)) {
    Write-Host "Codex git folder not found: $gitFolder" -ForegroundColor Red
    Write-Host "Check the gitfolder setting in $settingsPath"
    exit 1
}

# Gather the files to deploy: explicit paths, or git-modified .lua files.
$files = @()
if ($Paths -and $Paths.Count -gt 0) {
    foreach ($p in $Paths) {
        $rel = $p -replace '\\', '/'
        if (-not (Test-Path (Join-Path $repo $rel))) {
            Write-Host "SKIP (not found): $rel" -ForegroundColor Yellow
            continue
        }
        $files += $rel
    }
} else {
    $status = git -C $repo status --porcelain
    foreach ($line in $status) {
        if ($line.Length -lt 4) { continue }
        $rel = $line.Substring(3).Trim().Trim('"')
        if ($rel -match '\.lua$') {
            $files += $rel
        }
    }
}

if ($files.Count -eq 0) {
    Write-Host "Nothing to deploy (no git-modified .lua files)."
    exit 0
}

$deployed = 0
$upToDate = 0
$newModules = @()

foreach ($rel in $files) {
    if ($rel -eq "main.lua") {
        Write-Host "SKIP: main.lua (module list changes must be made through the app's mod tools)" -ForegroundColor Yellow
        continue
    }

    $src = Join-Path $repo ($rel -replace '/', '\')
    $moduleName = ($rel -split '/')[0]
    $remainder = ($rel -split '/', 2)[1]

    $moduleDir = Join-Path $gitFolder $moduleName
    if (-not (Test-Path $moduleDir)) {
        # A module folder the app has not checked out before. Create it; if the
        # app still loads the module from the cloud, it must be checked out for
        # git editing in the app's mod tools first.
        if (-not $Check) {
            New-Item -ItemType Directory -Force $moduleDir | Out-Null
        }
        if ($newModules -notcontains $moduleName) {
            $newModules += $moduleName
        }
    }

    $dst = Join-Path $moduleDir ($remainder -replace '/', '\')

    $srcContent = [System.IO.File]::ReadAllText($src)
    $existing = $null
    if (Test-Path $dst) {
        $existing = [System.IO.File]::ReadAllText($dst)
    }

    if ($existing -eq $srcContent) {
        $upToDate++
        continue
    }

    if ($Check) {
        Write-Host "WOULD DEPLOY: $rel -> $dst" -ForegroundColor Cyan
    } else {
        $dstDir = Split-Path $dst -Parent
        if (-not (Test-Path $dstDir)) {
            New-Item -ItemType Directory -Force $dstDir | Out-Null
        }
        [System.IO.File]::WriteAllText($dst, $srcContent)
        Write-Host "DEPLOYED: $rel" -ForegroundColor Green
    }
    $deployed++
}

Write-Host ""
if ($Check) {
    Write-Host "$deployed file(s) need deploying, $upToDate already up to date."
} else {
    Write-Host "$deployed file(s) deployed to $gitFolder, $upToDate already up to date."
    if ($deployed -gt 0) {
        Write-Host "Restart or reload the Codex to pick up the changes."
    }
}

if ($newModules.Count -gt 0) {
    Write-Host ""
    Write-Host "NOTE: these modules were not previously checked out in the git folder:" -ForegroundColor Yellow
    foreach ($m in $newModules) {
        Write-Host "  $m" -ForegroundColor Yellow
    }
    Write-Host "If the app still runs the old version of them after a restart, check them" -ForegroundColor Yellow
    Write-Host "out for git editing in the Codex's mod tools, then run this script again." -ForegroundColor Yellow
}
