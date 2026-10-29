param(
  [string[]]$Framework = @(),
  [ValidateSet("debug", "release")]
  [string]$Configuration = "release"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "framework-registry.ps1")

if ($Framework.Count -eq 0) {
  $Framework = @(
    (Get-BenchmarkFrameworkDefinitions).Values |
      Where-Object Enabled |
      ForEach-Object Name
  )
}

foreach ($frameworkName in $Framework) {
  $definition = Get-BenchmarkFrameworkDefinition -Name $frameworkName
  if (-not $definition.Enabled) {
    throw "Benchmark framework is declared but not enabled: $frameworkName"
  }
  $manifestPath = Join-Path $repoRoot "probes\$($definition.Directory)\Cargo.toml"
  $arguments = @("build", "--locked", "--manifest-path", $manifestPath)
  if ($Configuration -eq "release") { $arguments += "--release" }

  Write-Host "Building $frameworkName ($Configuration)"
  & cargo @arguments
  if ($LASTEXITCODE -ne 0) {
    throw "cargo build failed for $frameworkName with exit code $LASTEXITCODE"
  }
}

