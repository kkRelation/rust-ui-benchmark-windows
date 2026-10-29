param(
  [Parameter(Mandatory = $true)][string]$HistoricalPath,
  [Parameter(Mandatory = $true)][string]$CurrentPath,
  [string]$Framework = "slint",
  [Parameter(Mandatory = $true)][string]$OutputPath
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "anchor-comparison-lib.ps1")

$resolvedHistorical = [System.IO.Path]::GetFullPath($HistoricalPath)
$resolvedCurrent = [System.IO.Path]::GetFullPath($CurrentPath)
$resolvedOutput = [System.IO.Path]::GetFullPath($OutputPath)
foreach ($path in @($resolvedHistorical, $resolvedCurrent)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Anchor input does not exist: $path"
  }
}

$historical = Get-Content -LiteralPath $resolvedHistorical -Raw -Encoding utf8 | ConvertFrom-Json
$current = Get-Content -LiteralPath $resolvedCurrent -Raw -Encoding utf8 | ConvertFrom-Json
$comparison = Compare-ResidentAnchor -Historical $historical -Current $current -Framework $Framework
$audit = [pscustomobject]@{
  capturedAt = (Get-Date).ToString("o")
  historicalPath = $resolvedHistorical
  currentPath = $resolvedCurrent
  comparison = $comparison
}

$outputDirectory = Split-Path -Parent $resolvedOutput
[System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
$audit | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resolvedOutput -Encoding utf8
$audit | ConvertTo-Json -Depth 12

if ($comparison.status -eq "pass") { exit 0 }
if ($comparison.retryEligible) { exit 2 }
exit 1
