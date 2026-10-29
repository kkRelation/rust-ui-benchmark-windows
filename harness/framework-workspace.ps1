if (-not (Get-Command Get-BenchmarkFrameworkDefinition -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot "framework-registry.ps1")
}

function Get-BenchmarkFreeBytes {
  param([Parameter(Mandatory = $true)][string]$Path)

  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $driveRoot = [System.IO.Path]::GetPathRoot($fullPath)
  ([System.IO.DriveInfo]::new($driveRoot)).AvailableFreeSpace
}

function Get-ResolvedBenchmarkRepoRoot {
  param([Parameter(Mandatory = $true)][string]$RepoRoot)

  if (-not (Test-Path -LiteralPath $RepoRoot -PathType Container)) {
    throw "Benchmark repository root does not exist: $RepoRoot"
  }
  [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $RepoRoot).Path).TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
  )
}

function Assert-BenchmarkPathIsNotReparsePoint {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) { return }
  $item = Get-Item -LiteralPath $Path -Force
  if (-not $item.PSIsContainer) {
    throw "Safe framework work root must be a directory: $Path"
  }
  if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw "Safe framework work root cannot be a reparse point: $Path"
  }
}

function Resolve-SafeBenchmarkWorkRoot {
  param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [Parameter(Mandatory = $true)][string]$Framework,
    [Parameter(Mandatory = $true)][string]$Path
  )

  $definition = Get-BenchmarkFrameworkDefinition -Name $Framework
  $resolvedRepo = Get-ResolvedBenchmarkRepoRoot -RepoRoot $RepoRoot
  $workBase = [System.IO.Path]::GetFullPath((Join-Path $resolvedRepo ".benchmark-work"))
  $expected = [System.IO.Path]::GetFullPath((Join-Path $workBase $definition.Name))
  $candidateInput = if ([System.IO.Path]::IsPathRooted($Path)) {
    $Path
  } else {
    Join-Path $resolvedRepo $Path
  }
  $candidate = [System.IO.Path]::GetFullPath($candidateInput)
  $comparison = [System.StringComparison]::OrdinalIgnoreCase
  $workPrefix = $workBase.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar

  if (-not $expected.StartsWith($workPrefix, $comparison) -or
      -not $candidate.Equals($expected, $comparison)) {
    throw "Path is not the safe framework work root for '$Framework': $candidate"
  }

  Assert-BenchmarkPathIsNotReparsePoint -Path $workBase
  Assert-BenchmarkPathIsNotReparsePoint -Path $expected
  $expected
}

function New-BenchmarkFrameworkWorkspace {
  param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [Parameter(Mandatory = $true)][string]$Framework
  )

  $definition = Get-BenchmarkFrameworkDefinition -Name $Framework
  $resolvedRepo = Get-ResolvedBenchmarkRepoRoot -RepoRoot $RepoRoot
  $candidate = Join-Path $resolvedRepo ".benchmark-work\$($definition.Name)"
  $root = Resolve-SafeBenchmarkWorkRoot -RepoRoot $resolvedRepo -Framework $Framework -Path $candidate
  $freeBytesBefore = Get-BenchmarkFreeBytes -Path $resolvedRepo
  $cargoHome = Join-Path $root "cargo-home"
  $targetDirectory = Join-Path $root "target"

  New-Item -ItemType Directory -Force -Path $cargoHome,$targetDirectory | Out-Null
  $root = Resolve-SafeBenchmarkWorkRoot -RepoRoot $resolvedRepo -Framework $Framework -Path $root

  [pscustomobject]@{
    Root = $root
    CargoHome = $cargoHome
    TargetDirectory = $targetDirectory
    FreeBytesBefore = [int64]$freeBytesBefore
  }
}

function Remove-BenchmarkFrameworkWorkspace {
  param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [Parameter(Mandatory = $true)][string]$Framework,
    [Parameter(Mandatory = $true)][string]$Path
  )

  $resolvedRepo = Get-ResolvedBenchmarkRepoRoot -RepoRoot $RepoRoot
  $resolvedRoot = Resolve-SafeBenchmarkWorkRoot -RepoRoot $resolvedRepo -Framework $Framework -Path $Path
  $freeBytesBefore = Get-BenchmarkFreeBytes -Path $resolvedRepo
  $wasPresent = Test-Path -LiteralPath $resolvedRoot -PathType Container

  if ($wasPresent) {
    Remove-Item -LiteralPath $resolvedRoot -Recurse -Force
  }
  if (Test-Path -LiteralPath $resolvedRoot) {
    throw "Framework work root still exists after cleanup: $resolvedRoot"
  }

  $freeBytesAfter = Get-BenchmarkFreeBytes -Path $resolvedRepo
  $recoveredBytes = [int64]($freeBytesAfter - $freeBytesBefore)
  if ($recoveredBytes -lt 0) { $recoveredBytes = [int64]0 }
  [pscustomobject]@{
    RemovedPath = $resolvedRoot
    WasPresent = [bool]$wasPresent
    FreeBytesBefore = [int64]$freeBytesBefore
    FreeBytesAfter = [int64]$freeBytesAfter
    RecoveredBytes = $recoveredBytes
  }
}
