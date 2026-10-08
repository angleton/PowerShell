<#
.SYNOPSIS
    Shared browser detection helpers. Dot-source this file to use them.
#>

function Get-ChromiumBrowserCandidate {
    [CmdletBinding()]
    param()

    @(
        @{ Name = 'Google Chrome'; ProcessName = 'chrome'; Root = Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data' }
        @{ Name = 'Microsoft Edge'; ProcessName = 'msedge'; Root = Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data' }
        @{ Name = 'Brave'; ProcessName = 'brave'; Root = Join-Path $env:LOCALAPPDATA 'BraveSoftware\Brave-Browser\User Data' }
        @{ Name = 'Vivaldi'; ProcessName = 'vivaldi'; Root = Join-Path $env:LOCALAPPDATA 'Vivaldi\User Data' }
        @{ Name = 'Opera'; ProcessName = 'opera'; Root = Join-Path $env:APPDATA 'Opera Software\Opera Stable' }
    )
}

function Find-InstalledBrowser {
    [CmdletBinding()]
    param()

    $browsers = @()

    $chromiumCandidates = Get-ChromiumBrowserCandidate

    foreach ($candidate in $chromiumCandidates) {
        if (-not (Test-Path -LiteralPath $candidate.Root)) { continue }

        $profiles = @()
        if ($candidate.Name -eq 'Opera') {
            # Opera keeps a single profile directly under the root.
            $bookmarksFile = Join-Path $candidate.Root 'Bookmarks'
            if (Test-Path -LiteralPath $bookmarksFile) {
                $profiles += [pscustomobject]@{ ProfileName = 'Default'; ProfilePath = $candidate.Root; BookmarksFile = $bookmarksFile }
            }
        }
        else {
            Get-ChildItem -LiteralPath $candidate.Root -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' } |
                ForEach-Object {
                    $bookmarksFile = Join-Path $_.FullName 'Bookmarks'
                    if (Test-Path -LiteralPath $bookmarksFile) {
                        $profiles += [pscustomobject]@{ ProfileName = $_.Name; ProfilePath = $_.FullName; BookmarksFile = $bookmarksFile }
                    }
                }
        }

        if ($profiles.Count -gt 0) {
            $browsers += [pscustomobject]@{
                Name        = $candidate.Name
                Type        = 'Chromium'
                ProcessName = $candidate.ProcessName
                Profiles    = $profiles
            }
        }
    }

    # Firefox keeps its profile list in profiles.ini rather than well-known folder names.
    $ffProfilesIni = Join-Path $env:APPDATA 'Mozilla\Firefox\profiles.ini'
    if (Test-Path -LiteralPath $ffProfilesIni) {
        $ffRoot = Join-Path $env:APPDATA 'Mozilla\Firefox'
        $sectionData = @{}
        $currentSection = $null
        $props = @{}

        foreach ($profileLine in Get-Content -LiteralPath $ffProfilesIni) {
            $line = $profileLine.Trim()
            if ($line -match '^\[(.+)\]$') {
                $nextSection = $matches[1]
                if ($currentSection -and $currentSection -match '^Profile\d+$') {
                    $sectionData[$currentSection] = $props
                }
                $currentSection = $nextSection
                $props = @{}
            }
            elseif ($currentSection -and $line -match '^(.+?)=(.*)$') {
                $props[$matches[1]] = $matches[2]
            }
        }
        if ($currentSection -and $currentSection -match '^Profile\d+$') {
            $sectionData[$currentSection] = $props
        }

        $ffProfiles = @()
        foreach ($section in $sectionData.Keys) {
            $sectionProps = $sectionData[$section]
            if (-not $sectionProps.ContainsKey('Path')) { continue }
            $profilePath = if ($sectionProps['IsRelative'] -eq '0') { $sectionProps['Path'] } else { Join-Path $ffRoot $sectionProps['Path'] }
            $placesDb = Join-Path $profilePath 'places.sqlite'
            if (Test-Path -LiteralPath $placesDb) {
                $profileName = if ($sectionProps.ContainsKey('Name')) { $sectionProps['Name'] } else { $section }
                $ffProfiles += [pscustomobject]@{ ProfileName = $profileName; ProfilePath = $profilePath; PlacesDb = $placesDb }
            }
        }

        if ($ffProfiles.Count -gt 0) {
            $browsers += [pscustomobject]@{
                Name        = 'Mozilla Firefox'
                Type        = 'Firefox'
                ProcessName = 'firefox'
                Profiles    = $ffProfiles
            }
        }
    }

    return $browsers
}
