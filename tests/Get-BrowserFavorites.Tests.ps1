$scriptPath = Join-Path $PSScriptRoot '..\scripts\Get-BrowserFavorites.ps1'
. $scriptPath

Describe 'Find-InstalledBrowser' {
  $detectedBrowsers = @(Find-InstalledBrowser)
  $favorites = @(
    foreach ($browser in $detectedBrowsers) {
      foreach ($browserProfile in $browser.Profiles) {
        if ($browser.Type -eq 'Chromium') {
          Get-ChromiumBookmarkBarEntry -BookmarksFile $browserProfile.BookmarksFile -BrowserName $browser.Name -ProfileName $browserProfile.ProfileName
        }
        else {
          Get-FirefoxBookmarkBarEntry -PlacesDb $browserProfile.PlacesDb -ProfileName $browserProfile.ProfileName
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

Describe 'Save-BrowserOpenTabs' {
    . (Join-Path $PSScriptRoot '..\scripts\Save-BrowserOpenTabs.ps1')

    Context 'MozLz4Decoder' {
        It 'decodes literals followed by an overlapping match' {
            # 3 literals "abc", then a match of offset 3 and length 6.
            $header = [byte[]](0x6D, 0x6F, 0x7A, 0x4C, 0x7A, 0x34, 0x30, 0x00, 9, 0, 0, 0)
            $block = [byte[]](0x32, 0x61, 0x62, 0x63, 0x03, 0x00)
            $decoded = [MozLz4Decoder]::Decode([byte[]]($header + $block))
            [System.Text.Encoding]::ASCII.GetString($decoded) | Should Be 'abcabcabc'
        }

        It 'rejects data without the mozLz4 header' {
            $message = try { [MozLz4Decoder]::Decode([byte[]](1..20)); '' } catch { $_.Exception.Message }
            $message | Should Match 'Not a mozLz4 file'
        }
    }

    Context 'New-UniqueFile' {
        It 'appends an incrementing number when the name already exists' {
            $first = New-UniqueFile -Directory $TestDrive -BaseName 'tabs'
            $second = New-UniqueFile -Directory $TestDrive -BaseName 'tabs'
            $third = New-UniqueFile -Directory $TestDrive -BaseName 'tabs'
            (Split-Path $first -Leaf) | Should Be 'tabs.txt'
            (Split-Path $second -Leaf) | Should Be 'tabs_1.txt'
            (Split-Path $third -Leaf) | Should Be 'tabs_2.txt'
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