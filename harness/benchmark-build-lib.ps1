function Get-BenchmarkCargoBuildArguments {
  param(
    [Parameter(Mandatory = $true)][string]$ManifestPath,
    [Parameter(Mandatory = $true)][ValidateSet("debug", "release")][string]$Configuration,
    [string]$TargetDirectory
  )

  $arguments = @("build", "--locked", "--manifest-path", $ManifestPath)
  if ($Configuration -eq "release") { $arguments += "--release" }
  if (-not [string]::IsNullOrWhiteSpace($TargetDirectory)) {
    $arguments += @("--target-dir", $TargetDirectory)
  }
  $arguments
}

function Invoke-WithBenchmarkCargoHome {
  param(
    [string]$CargoHome,
    [Parameter(Mandatory = $true)][scriptblock]$Action
  )

  $hadCargoHome = Test-Path Env:CARGO_HOME
  $previousCargoHome = $env:CARGO_HOME
  try {
    if (-not [string]::IsNullOrWhiteSpace($CargoHome)) {
      $env:CARGO_HOME = $CargoHome
    }
    & $Action
  } finally {
    if ($hadCargoHome) {
      $env:CARGO_HOME = $previousCargoHome
    } else {
      Remove-Item Env:CARGO_HOME -ErrorAction SilentlyContinue
    }
  }
}
