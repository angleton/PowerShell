# PowerShell Scripts

A collection of PowerShell utility scripts.

> [!NOTE]
> Browser favorites scripts in this repository are supported only on Windows.

## Scripts

### `scripts/Get-BrowserFavorites.ps1`

Detects installed browsers (Chrome, Edge, Brave, Vivaldi, Opera, Firefox), lets you
choose which one(s) to pull Favorites/Bookmarks Bar entries from (or all of them),
and exports each browser's results to browser-prefixed JSON and CSV files, such as
`Google Chrome-BrowserFavorites.json` and `Google Chrome-BrowserFavorites.csv`.

**Parameters**

- `-OutputPath <string>` — Directory to save results to. If omitted or the path
  doesn't exist, a new timestamped folder under the system Temp directory is used.
- `-All` — Skip the interactive prompt and pull favorites from every detected browser.

**Examples**

```powershell
./scripts/Get-AvailableBrowserFavorites.ps1
./scripts/Get-BrowserFavorites.ps1
./scripts/Get-BrowserFavorites.ps1 -OutputPath C:\Reports\Favorites -All
```

Run `Get-AvailableBrowserFavorites.ps1` first to see how many favorites were
detected in each browser and are available to export. It does not create any
export files. Then run `Get-BrowserFavorites.ps1` to export those favorites.

**Notes**

- Chromium-based browsers (Chrome, Edge, Brave, Vivaldi, Opera) are read directly
  from their `Bookmarks` JSON file across all detected profiles.
- Firefox bookmarks are read from `places.sqlite` and require the `sqlite3` CLI
  to be available on `PATH`. Without it, Firefox profiles are skipped with a warning.

### Firefox Setup

Set up the SQLite command-line tool required for Firefox bookmark extraction:

```powershell
./scripts/Install-Sqlite.ps1
```

The setup script does nothing when `sqlite3` is already available. Otherwise,
it uses `winget` or, when unavailable, Chocolatey. Open a new PowerShell
terminal if the installation completes but the script reports that `sqlite3`
is not yet on `PATH`.

## Tests

The test suite uses Pester's BDD syntax (`Describe`, `Context`, and `It`).
Run the following commands from the repository root in PowerShell 7 or later.

Check whether Pester is already installed:

```powershell
Get-Module Pester -ListAvailable | Select-Object Name, Version
```

When the command returns no module, install Pester for the current user:

```powershell
Install-Module Pester -Scope CurrentUser -Force
```

Run the complete suite:

```powershell
./scripts/Invoke-Tests.ps1
```

The wrapper runs Pester and prints each result count on a separate line. Pester
3.x displays test details by default, so do not add `-Output Detailed` when
using that version because the parameter is ambiguous.

To run only the browser-favorites specifications:

```powershell
Invoke-Pester ./tests/Get-BrowserFavorites.Tests.ps1
```
