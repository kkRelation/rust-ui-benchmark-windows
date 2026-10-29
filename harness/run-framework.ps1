param(
  [Parameter(Mandatory = $true)][string]$Framework,
  [switch]$Anchor,
  [switch]$KeepWorkdir,
  [string]$OutputDirectory,
  [string]$HistoricalPath
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "framework-run-lib.ps1")

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
  $OutputDirectory = Join-Path $repoRoot ("results\" + (Get-Date -Format "yyyy-MM-dd"))
}
if ($Anchor -and [string]::IsNullOrWhiteSpace($HistoricalPath)) {
  $HistoricalPath = Join-Path $repoRoot "results\2026-10-28\2026-10-28-six-framework-resident.json"
}

Invoke-BenchmarkFrameworkRun `
  -RepoRoot $repoRoot `
  -Framework $Framework `
  -OutputDirectory $OutputDirectory `
  -Anchor:$Anchor `
  -KeepWorkdir:$KeepWorkdir `
  -HistoricalPath $HistoricalPath
