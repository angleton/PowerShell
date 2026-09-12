$scriptPath = Join-Path $PSScriptRoot '..\scripts\Get-BrowserFavorites.ps1'
. $scriptPath

Describe 'Find-InstalledBrowser' {
  $detectedBrowsers = @(Find-InstalledBrowser)
  $favorites = @(
    foreach ($browser in $detectedBrowsers) {
      foreach ($profile in $browser.Profiles) {
        if ($browser.Type -eq 'Chromium') {
          Get-ChromiumBookmarkBarEntry -BookmarksFile $profile.BookmarksFile -BrowserName $browser.Name -ProfileName $profile.ProfileName
        }
        else {
          Get-FirefoxBookmarkBarEntry -PlacesDb $profile.PlacesDb -ProfileName $profile.ProfileName
        }
      }
    }
  )

  $skipReason = $null
  if ($detectedBrowsers.Count -eq 0) {
    $skipReason = 'No supported browser profiles were detected on this computer.'
  }
  elseif ($favorites.Count -eq 0) {
    $skipReason = 'No favorites detected; there is nothing to test.'
  }

  if ($skipReason) {
    Write-Warning $skipReason
  }

  Context 'when browser profiles with favorites are available' {
    It 'detects installed browsers and finds favorites the script can pull' -Skip:($null -ne $skipReason) {
      $detectedBrowsers.Count | Should BeGreaterThan 0
      $favorites.Count | Should BeGreaterThan 0
    }
  }
}

Describe 'Get-ChromiumBookmarkBarEntry' {
    Context 'when a bookmark bar contains bookmarks and folders' {
        It 'returns each bookmark with its browser, profile, and folder path' {
            $bookmarksFile = Join-Path $TestDrive 'Bookmarks'
            @'
{
  "roots": {
    "bookmark_bar": {
      "children": [
        { "type": "url", "name": "Copilot", "url": "https://github.com/features/copilot" },
        {
          "type": "folder",
          "name": "Work",
          "children": [
            { "type": "url", "name": "Docs", "url": "https://learn.microsoft.com" },
            {
              "type": "folder",
              "name": "PowerShell",
              "children": [
                { "type": "url", "name": "Pester", "url": "https://pester.dev" }
              ]
            }
          ]
        }
      ]
    }
  }
}
'@ | Set-Content -LiteralPath $bookmarksFile -Encoding UTF8

            $entries = @(Get-ChromiumBookmarkBarEntry -BookmarksFile $bookmarksFile -BrowserName 'Google Chrome' -ProfileName 'Default')

            $entries.Count | Should Be 3
            $entries[0].Name | Should Be 'Copilot'
            $entries[0].Folder | Should Be ''
            $entries[0].Browser | Should Be 'Google Chrome'
            $entries[0].Profile | Should Be 'Default'
            $entries[1].Folder | Should Be 'Work'
            $entries[2].Folder | Should Be 'Work\PowerShell'
        }
    }

    Context 'when the bookmark bar is absent' {
        It 'returns no entries' {
            $bookmarksFile = Join-Path $TestDrive 'Bookmarks'
            '{ "roots": {} }' | Set-Content -LiteralPath $bookmarksFile -Encoding UTF8

            $entries = @(Get-ChromiumBookmarkBarEntry -BookmarksFile $bookmarksFile -BrowserName 'Google Chrome' -ProfileName 'Default')

            $entries.Count | Should Be 0
        }
    }
}