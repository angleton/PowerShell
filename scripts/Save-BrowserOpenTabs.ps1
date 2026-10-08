<#
.SYNOPSIS
    Saves the URLs of all open tabs in running Chromium browsers and Firefox to a text file.
.DESCRIPTION
    Firefox: reads each in-use profile's live session file
    (sessionstore-backups\recovery.jsonlz4, refreshed about every 15 seconds)
    and records the current URL of every tab. No special launch flags needed.

    Chromium: browsers don't expose open tabs on disk while running, so this
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
    Optional. Limits the capture to one browser by name ('Google Chrome',
    'Microsoft Edge', 'Brave', 'Vivaldi', 'Opera', or 'Mozilla Firefox').
    Defaults to all running supported browsers.
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

if (-not ('MozLz4Decoder' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
public static class MozLz4Decoder
{
    // Decodes Mozilla's mozLz4 container: "mozLz40\0", 4-byte LE size, raw LZ4 block.
    public static byte[] Decode(byte[] input)
    {
        if (input == null || input.Length < 12 ||
            input[0] != 'm' || input[1] != 'o' || input[2] != 'z' || input[3] != 'L' ||
            input[4] != 'z' || input[5] != '4' || input[6] != '0' || input[7] != 0)
            throw new InvalidOperationException("Not a mozLz4 file.");

        int outSize = BitConverter.ToInt32(input, 8);
        if (outSize < 0) throw new InvalidOperationException("Invalid mozLz4 size.");
        byte[] output = new byte[outSize];
        int ip = 12, op = 0;

        while (ip < input.Length)
        {
            int token = input[ip++];
            int litLen = token >> 4;
            if (litLen == 15)
            {
                int b;
                do { b = input[ip++]; litLen += b; } while (b == 255);
            }
            if (op + litLen > outSize || ip + litLen > input.Length) throw new InvalidOperationException("Corrupt LZ4 data.");
            Buffer.BlockCopy(input, ip, output, op, litLen);
            ip += litLen; op += litLen;
            if (ip >= input.Length) break;

            int offset = input[ip] | (input[ip + 1] << 8);
            ip += 2;
            if (offset == 0 || offset > op) throw new InvalidOperationException("Corrupt LZ4 data.");
            int matchLen = token & 15;
            if (matchLen == 15)
            {
                int b;
                do { b = input[ip++]; matchLen += b; } while (b == 255);
            }
            matchLen += 4;
            if (op + matchLen > outSize) throw new InvalidOperationException("Corrupt LZ4 data.");
            // Byte-wise copy: matches may overlap their own output.
            for (int i = 0; i < matchLen; i++, op++) output[op] = output[op - offset];
        }
        return output;
    }
}
'@
}

function Get-FirefoxSessionTabUrl {
    <# Returns the current URL of every open tab in a Firefox session file. #>
    param([Parameter(Mandatory)][string]$SessionFile)

    $bytes = [System.IO.File]::ReadAllBytes($SessionFile)
    $json = [System.Text.Encoding]::UTF8.GetString([MozLz4Decoder]::Decode($bytes)) | ConvertFrom-Json

    $urls = foreach ($window in @($json.windows)) {
        foreach ($tab in @($window.tabs)) {
            $entries = @($tab.entries)
            if ($entries.Count -eq 0) { continue }
            # 'index' is 1-based; fall back to the last entry if it is missing or out of range.
            $position = if ($tab.PSObject.Properties['index'] -and $tab.index -ge 1 -and $tab.index -le $entries.Count) { $tab.index - 1 } else { $entries.Count - 1 }
            $url = $entries[$position].url
            if ($url) { $url }
        }
    }
    return @($urls)
}

function Get-FirefoxSessionFile {
    param([Parameter(Mandatory)][string]$ProfilePath)

    # recovery.jsonlz4 is the live session, refreshed every ~15 seconds while Firefox runs.
    foreach ($relative in 'sessionstore-backups\recovery.jsonlz4', 'sessionstore.jsonlz4') {
        $path = Join-Path $ProfilePath $relative
        if (Test-Path -LiteralPath $path) { return $path }
    }
    return $null
}

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
    $candidateNames = @($candidates | ForEach-Object { $_.Name }) + 'Mozilla Firefox'
    if ($Browser -and $candidateNames -notcontains $Browser) {
        throw "Unknown browser '$Browser'. Valid values: $($candidateNames -join ', ')."
    }

    $installed = @(Find-InstalledBrowser)
    if ($Browser) { $installed = @($installed | Where-Object { $_.Name -eq $Browser }) }

    $lines = [System.Collections.Generic.List[string]]::new()

    foreach ($b in $installed) {
        if (-not (Get-Process -Name $b.ProcessName -ErrorAction SilentlyContinue)) {
            Write-Verbose "$($b.Name) is not running; skipping."
            continue
        }

        $urls = [System.Collections.Generic.List[string]]::new()

        if ($b.Type -eq 'Firefox') {
            foreach ($browserProfile in $b.Profiles) {
                $sessionFile = Get-FirefoxSessionFile -ProfilePath $browserProfile.ProfilePath
                if (-not $sessionFile) { continue }
                # Only profiles in use have a fresh session file; skip stale ones from idle profiles.
                if (-not (Test-Path -LiteralPath (Join-Path $browserProfile.ProfilePath 'parent.lock')) -and
                    -not (Test-Path -LiteralPath (Join-Path $browserProfile.ProfilePath 'lock'))) { continue }
                try {
                    foreach ($url in (Get-FirefoxSessionTabUrl -SessionFile $sessionFile)) { $urls.Add($url) }
                }
                catch {
                    Write-Warning "Could not read $($b.Name) profile '$($browserProfile.ProfileName)': $($_.Exception.Message)"
                }
            }
        }
        else {
            $root = ($candidates | Where-Object { $_.Name -eq $b.Name }).Root
            $ports = @(Get-DebugPort -ProcessName $b.ProcessName -DefaultUserDataDir $root)
            if ($ports.Count -eq 0) {
                Write-Warning "$($b.Name) is running without --remote-debugging-port; its tabs can't be read. Restart it with the flag to capture them."
                continue
            }

            foreach ($port in $ports) {
                try {
                    foreach ($url in (Get-OpenTabUrl -Port $port)) { $urls.Add($url) }
                }
                catch {
                    Write-Warning "Could not query $($b.Name) on port ${port}: $($_.Exception.Message)"
                }
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
