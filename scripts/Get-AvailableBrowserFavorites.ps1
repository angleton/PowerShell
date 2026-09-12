<#
.SYNOPSIS
    Reports the number of browser favorites available to export.
.DESCRIPTION
    Detects supported browser profiles and counts their bookmark-bar entries
    without creating JSON or CSV output files.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Get-BrowserFavorites.ps1')

$detectedBrowsers = @(Find-InstalledBrowser)
if ($detectedBrowsers.Count -eq 0) {
    Write-Warning 'No supported browsers with exportable bookmark data were detected.'
    return
}

$totalFavoriteCount = 0

foreach ($browser in $detectedBrowsers) {
    $browserEntries = [System.Collections.Generic.List[object]]::new()

    foreach ($browserProfile in $browser.Profiles) {
        if ($browser.Type -eq 'Chromium') {
            $entries = Get-ChromiumBookmarkBarEntry -BookmarksFile $browserProfile.BookmarksFile -BrowserName $browser.Name -ProfileName $browserProfile.ProfileName
        }
        else {
            $entries = Get-FirefoxBookmarkBarEntry -PlacesDb $browserProfile.PlacesDb -ProfileName $browserProfile.ProfileName
        }

        foreach ($entry in $entries) {
            $browserEntries.Add($entry)
        }
    }

    $totalFavoriteCount += $browserEntries.Count
    Write-Host "$($browser.Name): $($browserEntries.Count) favorite(s) available to export." -ForegroundColor Cyan
}

Write-Host "Total favorites available to export: $totalFavoriteCount" -ForegroundColor Cyan