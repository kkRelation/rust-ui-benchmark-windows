param(
  [string[]]$Framework = @(),
  [ValidateSet("debug", "release")]
  [string]$Configuration = "release",
  [string]$CargoHome,
  [string]$TargetDirectory
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "framework-registry.ps1")
. (Join-Path $PSScriptRoot "benchmark-build-lib.ps1")

if ($Framework.Count -eq 0) {
  $Framework = @(
    (Get-BenchmarkFrameworkDefinitions).Values |
      Where-Object Enabled |
      ForEach-Object Name
  )
}

$resolvedCargoHome = if ([string]::IsNullOrWhiteSpace($CargoHome)) {
  $null
} else {
  if ([System.IO.Path]::IsPathRooted($CargoHome)) {
    [System.IO.Path]::GetFullPath($CargoHome)
  } else {
    [System.IO.Path]::GetFullPath((Join-Path $repoRoot $CargoHome))
  }
}
$resolvedTargetDirectory = if ([string]::IsNullOrWhiteSpace($TargetDirectory)) {
  $null
} else {
  if ([System.IO.Path]::IsPathRooted($TargetDirectory)) {
    [System.IO.Path]::GetFullPath($TargetDirectory)
  } else {
    [System.IO.Path]::GetFullPath((Join-Path $repoRoot $TargetDirectory))
  }
}

$buildAction = {
  foreach ($frameworkName in $Framework) {
    $definition = Get-BenchmarkFrameworkDefinition -Name $frameworkName
    if (-not $definition.Enabled) {
      throw "Benchmark framework is declared but not enabled: $frameworkName"
    }
    $manifestPath = Join-Path $repoRoot "probes\$($definition.Directory)\Cargo.toml"
    $arguments = @(Get-BenchmarkCargoBuildArguments `
      -ManifestPath $manifestPath `
      -Configuration $Configuration `
      -TargetDirectory $resolvedTargetDirectory)

    Write-Host "Building $frameworkName ($Configuration)"
    & cargo @arguments
    if ($LASTEXITCODE -ne 0) {
      throw "cargo build failed for $frameworkName with exit code $LASTEXITCODE"
    }
  }
}

if ($null -ne $resolvedCargoHome) {
  [System.IO.Directory]::CreateDirectory($resolvedCargoHome) | Out-Null
}
if ($null -ne $resolvedTargetDirectory) {
  [System.IO.Directory]::CreateDirectory($resolvedTargetDirectory) | Out-Null
}
Invoke-WithBenchmarkCargoHome -CargoHome $resolvedCargoHome -Action $buildAction

