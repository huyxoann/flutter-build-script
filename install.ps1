# ==========================================
# build_script installer for Windows
# ==========================================
# Installs `build_release` CLI and its dependencies.
#
# Usage:
#   .\install.ps1              Install
#   .\install.ps1 --uninstall  Remove

$ErrorActionPreference = 'Stop'

$RepoDir = $PSScriptRoot
$BinDir = Join-Path $env:USERPROFILE ".local\bin"
$CmdPath = Join-Path $BinDir "build_release.cmd"

# ------------------------------------------
# Uninstall
# ------------------------------------------
if ($args.Count -gt 0 -and $args[0] -eq '--uninstall') {
    if (Test-Path $CmdPath) {
        Remove-Item -Path $CmdPath -Force
        Write-Host "✅ Removed $CmdPath"
    } else {
        Write-Host "ℹ️  Nothing to remove — $CmdPath does not exist."
    }
    exit 0
}

# ------------------------------------------
# Install dependencies
# ------------------------------------------
function Install-Dependencies {
    $needRuby = -not (Get-Command ruby -ErrorAction SilentlyContinue)
    $needBundler = -not (Get-Command bundle -ErrorAction SilentlyContinue)
    $needFastlane = -not (Get-Command fastlane -ErrorAction SilentlyContinue)

    if (-not $needRuby -and -not $needBundler -and -not $needFastlane) {
        $rubyVersion = (ruby -e "print RUBY_VERSION")
        Write-Host "✅ Dependencies: ruby $rubyVersion, bundler, fastlane — all present."
        return
    }

    Write-Host ""
    Write-Host "📦 Installing missing dependencies..."

    if ($needRuby) {
        if (Get-Command choco -ErrorAction SilentlyContinue) {
            Write-Host "   Installing Ruby via Chocolatey..."
            choco install ruby -y
            $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
        } else {
            Write-Host "❌ Ruby is not installed and Chocolatey is not available."
            Write-Host "   Please install Ruby manually from https://rubyinstaller.org"
            Write-Host "   or install Chocolatey (https://chocolatey.org) and re-run this installer."
            exit 1
        }
    }

    if (-not (Get-Command bundle -ErrorAction SilentlyContinue)) {
        Write-Host "   Installing Bundler..."
        gem install bundler
    }

    if (-not (Get-Command fastlane -ErrorAction SilentlyContinue)) {
        Write-Host "   Installing Fastlane..."
        gem install fastlane
    }

    Write-Host "✅ Dependencies installed."
}

# ------------------------------------------
# Install CLI
# ------------------------------------------
Write-Host "⚙️  Installing build_release CLI..."
Write-Host ""

Install-Dependencies

Write-Host ""

if (-not (Test-Path $BinDir)) {
    New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
}

$wrapperLines = @(
    '@echo off'
    'powershell -ExecutionPolicy Bypass -NoProfile -File "%USERPROFILE%\.build_script\scripts\build_release.ps1" %*'
)
Set-Content -Path $CmdPath -Value $wrapperLines

Write-Host "✅ Installed: $CmdPath"

# Check & update user PATH
$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
$pathParts = if ($userPath) { $userPath -split ';' } else { @() }
$normalizedBinDir = $BinDir.TrimEnd('\')
$alreadyInPath = $false

foreach ($part in $pathParts) {
    if ($part.Trim().TrimEnd('\') -ieq $normalizedBinDir) {
        $alreadyInPath = $true
        break
    }
}

if (-not $alreadyInPath) {
    $newUserPath = if ([string]::IsNullOrWhiteSpace($userPath)) {
        $BinDir
    } else {
        "$userPath;$BinDir"
    }
    [Environment]::SetEnvironmentVariable('Path', $newUserPath, 'User')
    $env:Path = "$env:Path;$BinDir"
    Write-Host ""
    Write-Host "⚠️  Added $BinDir to your User PATH."
    Write-Host "   Restart your terminal for changes to take effect in other windows."
}

# Ensure standard credential directories exist
$gplayDir = Join-Path $env:USERPROFILE ".config\gplay"
$appstoreDir = Join-Path $env:USERPROFILE ".config\appstore"
if (-not (Test-Path $gplayDir)) { New-Item -ItemType Directory -Path $gplayDir -Force | Out-Null }
if (-not (Test-Path $appstoreDir)) { New-Item -ItemType Directory -Path $appstoreDir -Force | Out-Null }

Write-Host "📁 Credential directories ready:" -ForegroundColor Cyan
Write-Host "   - $gplayDir\    (Place Google Play service-account.json here)"
Write-Host "   - $appstoreDir\ (Place App Store Connect AuthKey_*.p8 here)"

Write-Host ""
Write-Host "🚀 Ready! Run 'build_release --help' from any Flutter project."
