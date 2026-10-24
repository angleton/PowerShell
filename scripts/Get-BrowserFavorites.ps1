<#
.SYNOPSIS
    Compiles the Favorites/Bookmarks Bar entries from installed web browsers.
.DESCRIPTION
    Detects installed browsers (Chrome, Edge, Brave, Vivaldi, Opera, Firefox),
    prompts the user to choose which browser(s) to pull bookmarks-bar entries
    from (or all), then exports the compiled results to JSON and CSV files at
    the specified output location.
.PARAMETER OutputPath
    Directory to save the compiled favorites to. If omitted, or the path does
    not exist, a new timestamped folder under the system Temp directory is
    created and used instead.
.PARAMETER All
    Skip the interactive prompt and pull favorites from every detected browser.
.EXAMPLE
    ./Get-BrowserFavorites.ps1
.EXAMPLE
    ./Get-BrowserFavorites.ps1 -OutputPath C:\Reports\Favorites -All
#>

[CmdletBinding()]
param(
    [string]$OutputPath,
    [switch]$All
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([System.Environment]::OSVersion.Platform -ne [System.PlatformID]::Win32NT) {
    Write-Error 'Get-BrowserFavorites.ps1 is supported only on Windows.'
    exit 1
}

#region Browser detection

. (Join-Path $PSScriptRoot 'Common\Find-InstalledBrowser.ps1')

#endregion

#region Bookmark extraction

function Expand-BookmarkNode {
    param(
        [Parameter(Mandatory)] $Node,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$FolderPath,
        [Parameter(Mandatory)] [string]$BrowserName,
        [Parameter(Mandatory)] [string]$ProfileName,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [System.Collections.Generic.List[object]]$Results
    )

    if ($Node.type -eq 'url') {
        $Results.Add([pscustomobject]@{
            Browser = $BrowserName
            Profile = $ProfileName
            Folder  = $FolderPath
            Name    = $Node.name
            Url     = $Node.url
        })
    }
    elseif ($Node.type -eq 'folder') {
        $childPath = if ($FolderPath) { "$FolderPath\$($Node.name)" } else { $Node.name }
        foreach ($child in $Node.children) {
            Expand-BookmarkNode -Node $child -FolderPath $childPath -BrowserName $BrowserName -ProfileName $ProfileName -Results $Results
        }
    }
}

function Get-ChromiumBookmarkBarEntry {
    param(
        [Parameter(Mandatory)] [string]$BookmarksFile,
        [Parameter(Mandatory)] [string]$BrowserName,
        [Parameter(Mandatory)] [string]$ProfileName
    )

    $results = [System.Collections.Generic.List[object]]::new()

    $json = Get-Content -LiteralPath $BookmarksFile -Raw | ConvertFrom-Json
    $barProperty = $json.roots.PSObject.Properties['bookmark_bar']
    if (-not $barProperty) { return $results }
    $bar = $barProperty.Value

    foreach ($child in $bar.children) {
        Expand-BookmarkNode -Node $child -FolderPath '' -BrowserName $BrowserName -ProfileName $ProfileName -Results $results
    }

    return $results
}

function Get-FirefoxBookmarkBarEntry {
    param(
        [Parameter(Mandatory)] [string]$PlacesDb,
        [Parameter(Mandatory)] [string]$ProfileName
    )

    $results = [System.Collections.Generic.List[object]]::new()

    $sqlite3 = Get-Command -Name 'sqlite3' -ErrorAction SilentlyContinue
    if (-not $sqlite3) {
        Write-Warning "sqlite3 command not found in PATH; skipping Firefox profile '$ProfileName'. Install sqlite3 to enable Firefox bookmark extraction."
        return $results
    }

    # Copy the DB because Firefox locks places.sqlite while the browser is running.
    $tempDb = Join-Path ([System.IO.Path]::GetTempPath()) "places_$([guid]::NewGuid()).sqlite"
    Copy-Item -LiteralPath $PlacesDb -Destination $tempDb -Force

    try {
        $query = "SELECT b.title, p.url FROM moz_bookmarks b JOIN moz_places p ON b.fk = p.id WHERE b.parent = (SELECT id FROM moz_bookmarks WHERE guid = 'toolbar_____') AND b.type = 1;"
        $output = & $sqlite3.Source -separator "`t" $tempDb $query
        foreach ($line in $output) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line -split "`t", 2
            $results.Add([pscustomobject]@{
                Browser = 'Mozilla Firefox'
                Profile = $ProfileName
                Folder  = ''
                Name    = $parts[0]
                Url     = if ($parts.Count -gt 1) { $parts[1] } else { '' }
            })
        }
    }
    finally {
        Remove-Item -LiteralPath $tempDb -Force -ErrorAction SilentlyContinue
    }

    return $results
}

#endregion

#region Main

function Invoke-BrowserFavoritesExport {
    [CmdletBinding()]
    param(
        [string]$OutputPath,
        [switch]$All
    )

    $detected = Find-InstalledBrowser

    if ($detected.Count -eq 0) {
        Write-Warning 'No supported browsers were detected.'
        return
    }

    if ($All) {
        $selected = $detected
    }
    else {
        Write-Host 'Detected browsers:' -ForegroundColor Cyan
        for ($i = 0; $i -lt $detected.Count; $i++) {
            Write-Host "  [$($i + 1)] $($detected[$i].Name)"
        }
        Write-Host '  [A] All browsers'

        $choice = Read-Host "Select browser number(s) (comma-separated) or 'A' for all"

        if ($choice.Trim() -in @('A', 'a')) {
            $selected = $detected
        }
        else {
            $indices = $choice -split ',' |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ -match '^\d+$' } |
                ForEach-Object { [int]$_ - 1 }
            $selected = @($indices | Where-Object { $_ -ge 0 -and $_ -lt $detected.Count } | ForEach-Object { $detected[$_] })
        }
    }

    if (-not $selected -or $selected.Count -eq 0) {
        Write-Warning 'No browsers selected. Exiting.'
        return
    }

    # Resolve output path, falling back to a new Temp directory if unset or missing.
    if (-not $OutputPath -or -not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
        if ($OutputPath) {
            Write-Warning "Specified OutputPath '$OutputPath' does not exist. Falling back to a new Temp directory."
        }
        $OutputPath = Join-Path ([System.IO.Path]::GetTempPath()) "BrowserFavorites_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    }

    $totalFavoriteCount = 0

    foreach ($browser in $selected) {
        $browserEntries = [System.Collections.Generic.List[object]]::new()

        foreach ($p in $browser.Profiles) {
            if ($browser.Type -eq 'Chromium') {
                $entries = Get-ChromiumBookmarkBarEntry -BookmarksFile $p.BookmarksFile -BrowserName $browser.Name -ProfileName $p.ProfileName
            }
            else {
                $entries = Get-FirefoxBookmarkBarEntry -PlacesDb $p.PlacesDb -ProfileName $p.ProfileName
            }
            foreach ($entry in $entries) { $browserEntries.Add($entry) }
        }

        $filePrefix = $browser.Name -replace '[<>:"/\\|?*]', '_'
        $jsonPath = Join-Path $OutputPath "$filePrefix-BrowserFavorites.json"
        $csvPath = Join-Path $OutputPath "$filePrefix-BrowserFavorites.csv"

        $browserEntries | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
        $browserEntries | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8

        $totalFavoriteCount += $browserEntries.Count
        Write-Host "$($browser.Name): $($browserEntries.Count) favorite(s) exported." -ForegroundColor Green
        Write-Host 'Saved to:' -ForegroundColor Green
        Write-Host "  $jsonPath"
        Write-Host "  $csvPath"
    }

    Write-Host "Total favorites exported: $totalFavoriteCount" -ForegroundColor Green
}

if ($MyInvocation.InvocationName -ne '.') {
    Invoke-BrowserFavoritesExport -OutputPath $OutputPath -All:$All
}

#endregion
