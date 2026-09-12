# PowerShell Scripts

A collection of PowerShell utility scripts.

## Scripts

### `scripts/Get-BrowserFavorites.ps1`

Detects installed browsers (Chrome, Edge, Brave, Vivaldi, Opera, Firefox), lets you
choose which one(s) to pull Favorites/Bookmarks Bar entries from (or all of them),
and exports the compiled results to `BrowserFavorites.json` and `BrowserFavorites.csv`.

**Parameters**

- `-OutputPath <string>` — Directory to save results to. If omitted or the path
  doesn't exist, a new timestamped folder under the system Temp directory is used.
- `-All` — Skip the interactive prompt and pull favorites from every detected browser.

**Examples**

```powershell
./scripts/Get-BrowserFavorites.ps1
./scripts/Get-BrowserFavorites.ps1 -OutputPath C:\Reports\Favorites -All
```

**Notes**

- Chromium-based browsers (Chrome, Edge, Brave, Vivaldi, Opera) are read directly
  from their `Bookmarks` JSON file across all detected profiles.
- Firefox bookmarks are read from `places.sqlite` and require the `sqlite3` CLI
  to be available on `PATH`. Without it, Firefox profiles are skipped with a warning.
