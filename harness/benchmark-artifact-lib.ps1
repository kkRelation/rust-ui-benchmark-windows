function Resolve-BenchmarkPath {
  param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [Parameter(Mandatory = $true)][string]$Path
  )

  $candidate = if ([System.IO.Path]::IsPathRooted($Path)) {
    $Path
  } else {
    Join-Path $RepoRoot $Path
  }
  [System.IO.Path]::GetFullPath($candidate)
}

function ConvertTo-BenchmarkArtifactLabel {
  param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [Parameter(Mandatory = $true)][string]$Path
  )

  $resolvedRepo = [System.IO.Path]::GetFullPath($RepoRoot).TrimEnd('\', '/')
  $resolvedPath = [System.IO.Path]::GetFullPath($Path)
  $relative = [System.IO.Path]::GetRelativePath($resolvedRepo, $resolvedPath)
  if ($relative -eq ".." -or $relative.StartsWith("..\") -or $relative.StartsWith("../")) {
    return $resolvedPath.Replace('\', '/')
  }
  $relative.Replace('\', '/')
}

function Get-BenchmarkProbeArtifact {
  param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [Parameter(Mandatory = $true)][pscustomobject]$Definition,
    [Parameter(Mandatory = $true)][ValidateSet("debug", "release")][string]$Configuration,
    [string]$TargetDirectory
  )

  $probeRoot = Join-Path $RepoRoot "probes\$($Definition.Directory)"
  $resolvedTarget = if ([string]::IsNullOrWhiteSpace($TargetDirectory)) {
    Join-Path $probeRoot "target"
  } else {
    Resolve-BenchmarkPath -RepoRoot $RepoRoot -Path $TargetDirectory
  }
  $executable = [System.IO.Path]::GetFullPath(
    (Join-Path $resolvedTarget "$Configuration\$($Definition.Binary)")
  )

  [pscustomobject]@{
    Path = $executable
    Label = ConvertTo-BenchmarkArtifactLabel -RepoRoot $RepoRoot -Path $executable
    LockfilePath = Join-Path $probeRoot "Cargo.lock"
    TargetDirectory = [System.IO.Path]::GetFullPath($resolvedTarget)
  }
}

function Save-BenchmarkRoundEventLog {
  param(
    [Parameter(Mandatory = $true)][string]$SourcePath,
    [Parameter(Mandatory = $true)][string]$ArtifactDirectory,
    [Parameter(Mandatory = $true)][string]$Framework,
    [Parameter(Mandatory = $true)][ValidateRange(1, 1000)][int]$Round
  )

  if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
    throw "Round event log does not exist: $SourcePath"
  }
  $resolvedArtifactDirectory = [System.IO.Path]::GetFullPath($ArtifactDirectory)
  $frameworkDirectory = Join-Path $resolvedArtifactDirectory $Framework
  [System.IO.Directory]::CreateDirectory($frameworkDirectory) | Out-Null
  $destination = Join-Path $frameworkDirectory "round-$Round-events.jsonl"
  Copy-Item -LiteralPath $SourcePath -Destination $destination -Force
  [System.IO.Path]::GetFullPath($destination)
}

function Get-BenchmarkFileSha256 {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Cannot hash missing benchmark artifact: $Path"
  }
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
