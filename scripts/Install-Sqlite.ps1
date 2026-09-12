<#
.SYNOPSIS
    Installs the SQLite command-line tool required for Firefox bookmark extraction.
.DESCRIPTION
    Uses winget when available and falls back to Chocolatey. If sqlite3 is
    already available on PATH, no installation is performed.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Get-SqliteCommand {
    Get-Command -Name 'sqlite3' -ErrorAction SilentlyContinue
}

$sqlite3 = Get-SqliteCommand
if ($sqlite3) {
    Write-Host "sqlite3 is already available: $(& $sqlite3.Source --version)"
    return
}

if (Get-Command -Name 'winget' -ErrorAction SilentlyContinue) {
    Write-Host 'Installing SQLite with winget...'
    & winget install --id SQLite.SQLite --exact --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "winget failed to install SQLite (exit code $LASTEXITCODE)."
    }
}
elseif (Get-Command -Name 'choco' -ErrorAction SilentlyContinue) {
    Write-Host 'Installing SQLite with Chocolatey...'
    & choco install sqlite -y
    if ($LASTEXITCODE -ne 0) {
        throw "Chocolatey failed to install SQLite (exit code $LASTEXITCODE)."
    }
}
else {
    throw 'Neither winget nor Chocolatey is available. Install SQLite manually, then ensure sqlite3 is on PATH.'
}

$sqlite3 = Get-SqliteCommand
if (-not $sqlite3) {
    throw 'SQLite was installed, but sqlite3 is not available in this PowerShell session. Open a new terminal, then run this script again to verify the installation.'
}

Write-Host "sqlite3 installed successfully: $(& $sqlite3.Source --version)"