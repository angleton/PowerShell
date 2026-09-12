[CmdletBinding()]
param(
    [string]$TestPath = (Join-Path $PSScriptRoot '..\tests')
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command -Name Invoke-Pester -ErrorAction SilentlyContinue)) {
    throw 'Pester is not installed. Run Install-Module Pester -Scope CurrentUser -Force, then run this script again.'
}

$result = Invoke-Pester -Script $TestPath -PassThru -Quiet
$inconclusiveProperty = $result.PSObject.Properties['InconclusiveCount']
$inconclusiveCount = if ($inconclusiveProperty) { $inconclusiveProperty.Value } else { 0 }

@(
    "Passed: $($result.PassedCount)"
    "Failed: $($result.FailedCount)"
    "Skipped: $($result.SkippedCount)"
    "Pending: $($result.PendingCount)"
    "Inconclusive: $inconclusiveCount"
) | Write-Output

if ($result.FailedCount -gt 0) {
    exit 1
}