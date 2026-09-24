# ==========================================
# Remote installer — PowerShell one-liner entry point
# ==========================================
# irm https://raw.githubusercontent.com/huyxoann/flutter-build-script/main/setup.ps1 | iex

$ErrorActionPreference = 'Stop'

$InstallDir = Join-Path $env:USERPROFILE ".build_script"
$RepoUrl = "https://github.com/huyxoann/flutter-build-script.git"

Write-Host "⚙️  Flutter Build Script — Remote Setup"
Write-Host ""

if (Test-Path (Join-Path $InstallDir ".git")) {
    Write-Host "📥 Updating existing installation..."
    git -C "$InstallDir" pull --quiet
} else {
    Write-Host "📥 Cloning to $InstallDir..."
    if (Test-Path $InstallDir) { Remove-Item -Path $InstallDir -Recurse -Force }
    git clone --quiet "$RepoUrl" "$InstallDir"
}

Write-Host ""
& (Join-Path $InstallDir "install.ps1") @args
