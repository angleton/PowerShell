$scriptPath = Join-Path $PSScriptRoot '..\scripts\Get-BrowserFavorites.ps1'
. $scriptPath

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