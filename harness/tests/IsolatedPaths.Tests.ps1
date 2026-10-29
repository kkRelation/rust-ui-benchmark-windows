$artifactLibraryPath = Join-Path $PSScriptRoot "..\benchmark-artifact-lib.ps1"
. $artifactLibraryPath
$buildLibraryPath = Join-Path $PSScriptRoot "..\benchmark-build-lib.ps1"
. $buildLibraryPath

Describe "isolated benchmark paths" {
  It "uses the normal probe target when no isolated target is supplied" {
    $repoRoot = Join-Path $TestDrive "repo"
    $probeRoot = Join-Path $repoRoot "probes\fixture-probe"
    New-Item -ItemType Directory -Force -Path $probeRoot | Out-Null
    $definition = [pscustomobject]@{
      Name = "fixture"
      Directory = "fixture-probe"
      Binary = "fixture.exe"
    }

    $artifact = Get-BenchmarkProbeArtifact `
      -RepoRoot $repoRoot `
      -Definition $definition `
      -Configuration "release"

    $artifact.Path | Should Be (Join-Path $probeRoot "target\release\fixture.exe")
    $artifact.Label | Should Be "probes/fixture-probe/target/release/fixture.exe"
  }

  It "uses the supplied target directory for executable lookup" {
    $repoRoot = Join-Path $TestDrive "repo"
    $targetDirectory = Join-Path $repoRoot ".benchmark-work\fixture\target"
    New-Item -ItemType Directory -Force -Path $targetDirectory | Out-Null
    $definition = [pscustomobject]@{
      Name = "fixture"
      Directory = "fixture-probe"
      Binary = "fixture.exe"
    }

    $artifact = Get-BenchmarkProbeArtifact `
      -RepoRoot $repoRoot `
      -Definition $definition `
      -Configuration "debug" `
      -TargetDirectory $targetDirectory

    $artifact.Path | Should Be (Join-Path $targetDirectory "debug\fixture.exe")
    $artifact.Label | Should Be ".benchmark-work/fixture/target/debug/fixture.exe"
  }

  It "passes isolated Cargo paths and restores CARGO_HOME after failure" {
    $cargoHome = Join-Path $TestDrive "cargo home"
    $targetDirectory = Join-Path $TestDrive "cargo target"
    $hadCargoHome = Test-Path Env:CARGO_HOME
    $oldCargoHome = $env:CARGO_HOME
    try {
      $env:CARGO_HOME = "parent-sentinel"
      $script:observedCargoHome = $null

      $threw = $false
      try {
        Invoke-WithBenchmarkCargoHome -CargoHome $cargoHome -Action {
          $script:observedCargoHome = $env:CARGO_HOME
          throw "fixture build failure"
        }
      } catch {
        $threw = $true
      }

      $threw | Should Be $true
      $env:CARGO_HOME | Should Be "parent-sentinel"
      $script:observedCargoHome | Should Be $cargoHome
      $arguments = @(Get-BenchmarkCargoBuildArguments `
        -ManifestPath "C:\fixture\Cargo.toml" `
        -Configuration "debug" `
        -TargetDirectory $targetDirectory)
      ($arguments -join " ") | Should Match "--target-dir"
      ($arguments -join " ") | Should Match ([regex]::Escape($targetDirectory))
    } finally {
      if ($hadCargoHome) { $env:CARGO_HOME = $oldCargoHome } else { Remove-Item Env:CARGO_HOME -ErrorAction SilentlyContinue }
    }
  }

  It "passes isolated paths through the build command" {
    $cargoHome = Join-Path $TestDrive "build cargo home"
    $targetDirectory = Join-Path $TestDrive "build target"
    $global:capturedBuildCargoHome = $null
    $global:capturedBuildArguments = @()
    function global:cargo {
      $global:capturedBuildCargoHome = $env:CARGO_HOME
      $global:capturedBuildArguments = @($args)
      $global:LASTEXITCODE = 0
    }

    try {
      & (Join-Path $PSScriptRoot "..\build-all.ps1") `
        -Framework "slint" `
        -Configuration "debug" `
        -CargoHome $cargoHome `
        -TargetDirectory $targetDirectory

      $global:capturedBuildCargoHome | Should Be $cargoHome
      ($global:capturedBuildArguments -join " ") | Should Match "--target-dir"
      ($global:capturedBuildArguments -join " ") | Should Match ([regex]::Escape($targetDirectory))
    } finally {
      Remove-Item Function:\global:cargo -ErrorAction SilentlyContinue
      Remove-Variable capturedBuildCargoHome,capturedBuildArguments -Scope Global -ErrorAction SilentlyContinue
    }
  }

  It "does not add a target argument when the isolated target is omitted" {
    $arguments = @(Get-BenchmarkCargoBuildArguments `
      -ManifestPath "C:\fixture\Cargo.toml" `
      -Configuration "debug")
    ($arguments -join " ") | Should Not Match "--target-dir"
  }
}
