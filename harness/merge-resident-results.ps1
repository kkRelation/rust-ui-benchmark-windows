param(
  [Parameter(Mandatory = $true)][string]$PrimaryPath,
  [Parameter(Mandatory = $true)][string[]]$SupplementPath,
  [Parameter(Mandatory = $true)][string]$OutputPath
)

$ErrorActionPreference = "Stop"
$benchmarkRoot = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $benchmarkRoot "..")).Path
. (Join-Path $benchmarkRoot "resident-benchmark-lib.ps1")

function Resolve-RepoPath([string]$Path) {
  if ([System.IO.Path]::IsPathRooted($Path)) { return [System.IO.Path]::GetFullPath($Path) }
  [System.IO.Path]::GetFullPath((Join-Path $repoRoot $Path))
}

$primary = Get-Content -LiteralPath (Resolve-RepoPath $PrimaryPath) -Raw -Encoding utf8 | ConvertFrom-Json
$supplements = @(
  foreach ($path in $SupplementPath) {
    Get-Content -LiteralPath (Resolve-RepoPath $path) -Raw -Encoding utf8 | ConvertFrom-Json
  }
)
$frameworks = @("tauri", "slint", "zgui", "dioxus-desktop", "dioxus-native", "gpui-ce")
$allRuns = @($primary.runs) + @($supplements | ForEach-Object { $_.runs })
$failedAttempts = @($allRuns | Where-Object status -eq "failed")

$successfulByKey = [ordered]@{}
$supersededSuccessfulPairs = @()
foreach ($run in @($allRuns | Where-Object status -eq "ok")) {
  $key = "$($run.framework):$($run.round)"
  if ($successfulByKey.Contains($key)) { $supersededSuccessfulPairs += $key }
  $successfulByKey[$key] = $run
}
$runs = @(
  foreach ($round in 1..$primary.protocol.rounds) {
    foreach ($framework in $frameworks) {
      $key = "${framework}:$round"
      if ($successfulByKey.Contains($key)) { $successfulByKey[$key] }
    }
  }
)

$expected = $frameworks.Count * [int]$primary.protocol.rounds
if ($runs.Count -ne $expected) {
  throw "Expected $expected successful framework/round pairs, found $($runs.Count)"
}

$result = $primary
$result.capturedAt = (Get-Date).ToString("o")
$result.runs = $runs
$result.summary = New-ResidentBenchmarkSummary -Runs $runs -Frameworks $frameworks
$result | Add-Member -Force -NotePropertyName failedAttempts -NotePropertyValue $failedAttempts
$result | Add-Member -Force -NotePropertyName supersededSuccessfulPairs -NotePropertyValue @($supersededSuccessfulPairs | Sort-Object -Unique)
$result | Add-Member -Force -NotePropertyName assembly -NotePropertyValue ([pscustomobject]@{
  primary = $PrimaryPath -replace "\\", "/"
  supplements = @($SupplementPath | ForEach-Object { $_ -replace "\\", "/" })
  policy = "successful framework/round pairs; supplements override duplicate successful pairs; failed attempts retained separately"
})

$resolvedOutput = Resolve-RepoPath $OutputPath
[System.IO.Directory]::CreateDirectory((Split-Path -Parent $resolvedOutput)) | Out-Null
$result | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $resolvedOutput -Encoding utf8
$result
