<#
.SYNOPSIS
    Saves the URLs of all open tabs in running Chromium browsers to a text file.
.DESCRIPTION
    Chromium browsers don't expose open tabs on disk while running, so this
    queries each browser's DevTools endpoint (/json/list). A browser is only
    captured if it was started with --remote-debugging-port (or
    --remote-debugging-port=0, in which case the port is read from the
    DevToolsActivePort file). Running browsers without it are reported with a
    warning. Note: Chromium 136+ ignores the flag for the default user data
    directory; also pass --user-data-dir=<non-default path>.

    The output is a tab-delimited text file (Browser, Url), one tab per line,
    named OpenTabs_yyyyMMdd_HHmmss_fffffff.txt using the run time at
    100-nanosecond precision. If that name already exists, _1, _2, ... is
    appended before the extension.
.PARAMETER Browser
    Optional. Limits the capture to one browser by name, matching the Chromium
    candidate names (e.g. 'Google Chrome', 'Microsoft Edge', 'Brave', 'Vivaldi',
    'Opera'). Defaults to all running Chromium browsers.
.PARAMETER OutputPath
    Directory to save the file to. Defaults to the current directory; created if
    missing.
.EXAMPLE
    ./Save-BrowserOpenTabs.ps1
.EXAMPLE
    ./Save-BrowserOpenTabs.ps1 -Browser 'Microsoft Edge' -OutputPath C:\Temp\Tabs
#>

[CmdletBinding()]
param(
    [string]$Browser,
    [string]$OutputPath = (Get-Location).Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Common\Find-InstalledBrowser.ps1')

function Get-DebugPort {
    <# Returns the distinct DevTools ports of a running browser's main processes. #>
    param(
        [Parameter(Mandatory)][string]$ProcessName,
        [Parameter(Mandatory)][string]$DefaultUserDataDir
    )

    $ports = [System.Collections.Generic.List[int]]::new()
    $mainProcesses = @(Get-CimInstance Win32_Process -Filter "Name = '$ProcessName.exe'" |
            Where-Object { $_.CommandLine -and $_.CommandLine -notmatch '--type=' })

    foreach ($process in $mainProcesses) {
        if ($process.CommandLine -notmatch '--remote-debugging-port=(\d+)') { continue }
        $port = [int]$matches[1]

        if ($port -eq 0) {
            $userDataDir = if ($process.CommandLine -match '--user-data-dir=(?:"([^"]+)"|(\S+))') { if ($matches[1]) { $matches[1] } else { $matches[2] } } else { $DefaultUserDataDir }
            $portFile = Join-Path $userDataDir 'DevToolsActivePort'
            if (-not (Test-Path -LiteralPath $portFile)) { continue }
            $port = [int](Get-Content -LiteralPath $portFile -TotalCount 1)
        }

        if (-not $ports.Contains($port)) { $ports.Add($port) }
    }

    return @($ports)
}

function Get-OpenTabUrl {
    param([Parameter(Mandatory)][int]$Port)

    $targets = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/list" -TimeoutSec 5
    return @($targets | Where-Object { $_.type -eq 'page' -and $_.url -and $_.url -notlike 'devtools://*' } | ForEach-Object { $_.url })
}

function New-UniqueFile {
    <# Atomically creates the file, appending _1, _2, ... on a name collision. #>
    param(
        [Parameter(Mandatory)][string]$Directory,
        [Parameter(Mandatory)][string]$BaseName,
        [string]$Extension = '.txt'
    )

    $suffix = 0
    while ($true) {
        $name = if ($suffix -eq 0) { "$BaseName$Extension" } else { "${BaseName}_$suffix$Extension" }
        $path = Join-Path $Directory $name
        try {
            $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            $stream.Dispose()
            return $path
        }
        catch [System.IO.IOException] {
            if (-not (Test-Path -LiteralPath $path)) { throw }
            $suffix++
        }
    }
}

function Save-BrowserOpenTab {
    [CmdletBinding()]
    param(
        [string]$Browser,
        [string]$OutputPath
    )

    # Captured first so the file name reflects when the script was run.
    $runTime = Get-Date

    $candidates = @(Get-ChromiumBrowserCandidate)
    $candidateNames = @($candidates | ForEach-Object { $_.Name })
    if ($Browser -and $candidateNames -notcontains $Browser) {
        throw "Unknown browser '$Browser'. Valid values: $($candidateNames -join ', ')."
    }

    $installed = @(Find-InstalledBrowser | Where-Object { $_.Type -eq 'Chromium' })
    if ($Browser) { $installed = @($installed | Where-Object { $_.Name -eq $Browser }) }

    $lines = [System.Collections.Generic.List[string]]::new()

    foreach ($b in $installed) {
        if (-not (Get-Process -Name $b.ProcessName -ErrorAction SilentlyContinue)) {
            Write-Verbose "$($b.Name) is not running; skipping."
            continue
        }

        $root = ($candidates | Where-Object { $_.Name -eq $b.Name }).Root
        $ports = @(Get-DebugPort -ProcessName $b.ProcessName -DefaultUserDataDir $root)
        if ($ports.Count -eq 0) {
            Write-Warning "$($b.Name) is running without --remote-debugging-port; its tabs can't be read. Restart it with the flag to capture them."
            continue
        }

        $urls = [System.Collections.Generic.List[string]]::new()
        foreach ($port in $ports) {
            try {
                foreach ($url in (Get-OpenTabUrl -Port $port)) { $urls.Add($url) }
            }
            catch {
                Write-Warning "Could not query $($b.Name) on port ${port}: $($_.Exception.Message)"
            }
        }

        foreach ($url in $urls) { $lines.Add("$($b.Name)`t$url") }
        Write-Host "$($b.Name): $($urls.Count) open tab(s)." -ForegroundColor Cyan
    }

    if ($lines.Count -eq 0) {
        Write-Warning 'No open tabs were captured; no file was written.'
        return
    }

    if (-not (Test-Path -LiteralPath $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    }

    $baseName = 'OpenTabs_' + $runTime.ToString('yyyyMMdd_HHmmss_') + ($runTime.Ticks % 10000000).ToString('0000000')
    $file = New-UniqueFile -Directory (Resolve-Path -LiteralPath $OutputPath).ProviderPath -BaseName $baseName
    [System.IO.File]::WriteAllLines($file, $lines, [System.Text.UTF8Encoding]::new($false))

    Write-Host "Saved $($lines.Count) tab(s) to $file" -ForegroundColor Green
    return $file
}

# Allows dot-sourcing for tests without running the capture.
if ($MyInvocation.InvocationName -ne '.') {
    Save-BrowserOpenTab -Browser $Browser -OutputPath $OutputPath
}
