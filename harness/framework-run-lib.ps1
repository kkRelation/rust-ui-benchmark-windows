if (-not (Get-Command Get-BenchmarkFrameworkDefinition -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot "framework-registry.ps1")
}
if (-not (Get-Command New-BenchmarkFrameworkWorkspace -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot "framework-workspace.ps1")
}
if (-not (Get-Command Compare-ResidentAnchor -ErrorAction SilentlyContinue)) {
  . (Join-Path $PSScriptRoot "anchor-comparison-lib.ps1")
}

function Get-FrameworkResultProperty {
  param(
    [AllowNull()][object]$Object,
    [Parameter(Mandatory = $true)][string]$Name
  )

  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  $property.Value
}

function Test-FrameworkResult {
  param(
    [Parameter(Mandatory = $true)][object]$Result,
    [Parameter(Mandatory = $true)][string]$Framework,
    [Parameter(Mandatory = $true)][ValidateRange(1, 100)][int]$ExpectedRounds
  )

  $errors = [System.Collections.Generic.List[string]]::new()
  $frameworkRuns = @($Result.runs | Where-Object framework -eq $Framework)
  $failedRuns = @($frameworkRuns | Where-Object status -ne "ok")
  if ($failedRuns.Count -gt 0) {
    $errors.Add("Result contains $($failedRuns.Count) failed run(s) for '$Framework'.")
  }
  $successfulRuns = @($frameworkRuns | Where-Object status -eq "ok")
  $distinctRounds = @($successfulRuns | ForEach-Object round | Sort-Object -Unique)
  if ($successfulRuns.Count -ne $ExpectedRounds -or $distinctRounds.Count -ne $ExpectedRounds) {
    $errors.Add("Expected exactly $ExpectedRounds distinct successful rounds for '$Framework'; found $($successfulRuns.Count) successful run(s) and $($distinctRounds.Count) distinct round number(s).")
  }

  $requiredPhases = @("hiddenIdle", "visibleIdle", "workload400", "postHideIdle", "postCycleIdle")
  $topologyStages = @("hidden", "visible", "postHide", "postCycle")
  $expectedProtocol = [ordered]@{
    resident = $true
    windows = 2
    mainContentSize = "700x480"
    auxiliaryContentSize = "1200x760"
    workload = "400 shared-state updates at 20 ms"
    rounds = $ExpectedRounds
    smoke = $ExpectedRounds -eq 1
    sampleSeconds = if ($ExpectedRounds -eq 1) { 1 } else { 10 }
    postHideSettleSeconds = if ($ExpectedRounds -eq 1) { 1 } else { 15 }
    cycleCount = if ($ExpectedRounds -eq 1) { 2 } else { 30 }
  }
  foreach ($entry in $expectedProtocol.GetEnumerator()) {
    $actual = Get-FrameworkResultProperty -Object $Result.protocol -Name $entry.Key
    if ($null -eq $actual -or "$actual" -ne "$($entry.Value)") {
      $errors.Add("Result protocol.$($entry.Key) must be '$($entry.Value)'; found '$actual'.")
    }
  }
  $protocolPhases = @(Get-FrameworkResultProperty -Object $Result.protocol -Name "phases")
  foreach ($phaseName in $requiredPhases) {
    if ($phaseName -notin $protocolPhases) {
      $errors.Add("Result protocol.phases is missing '$phaseName'.")
    }
  }

  $expectedTitles = @("UI Framework Bench - Auxiliary Canvas", "UI Framework Bench - Main") | Sort-Object
  $expectedVisibility = @{
    hidden = $false
    visible = $true
    postHide = $false
    postCycle = $false
  }
  foreach ($run in $successfulRuns) {
    foreach ($phaseName in $requiredPhases) {
      $phase = Get-FrameworkResultProperty -Object $run.phases -Name $phaseName
      if ($null -eq $phase) {
        $errors.Add("Round $($run.round) is missing required phase '$phaseName'.")
      } elseif ($null -eq (Get-FrameworkResultProperty -Object $phase -Name "processCount") -or
                $null -eq (Get-FrameworkResultProperty -Object $phase -Name "rendererCount")) {
        $errors.Add("Round $($run.round) phase '$phaseName' is missing processCount or rendererCount.")
      }
    }
    foreach ($stageName in $topologyStages) {
      $windowsValue = Get-FrameworkResultProperty -Object $run.topology -Name $stageName
      $windows = if ($null -eq $windowsValue) { @() } else { @($windowsValue) }
      $titles = @($windows | ForEach-Object Title | Sort-Object)
      $validTitles = $windows.Count -eq 2 -and ($titles -join "|") -eq ($expectedTitles -join "|")
      $validDimensions = @($windows | Where-Object { [int]$_.Width -le 0 -or [int]$_.Height -le 0 }).Count -eq 0
      $validVisibility = @($windows | Where-Object { [bool]$_.Visible -ne $expectedVisibility[$stageName] }).Count -eq 0
      if (-not $validTitles -or -not $validDimensions -or -not $validVisibility) {
        $errors.Add("Round $($run.round) topology.$stageName must contain both exact benchmark window titles with positive dimensions and expected visibility.")
      }
    }

    $eventLog = Get-FrameworkResultProperty -Object $run -Name "eventLog"
    if ([string]::IsNullOrWhiteSpace("$eventLog")) {
      $errors.Add("Round $($run.round) eventLog is missing.")
    } else {
      try {
        $resolvedEventLog = [System.IO.Path]::GetFullPath("$eventLog")
        if (@($resolvedEventLog -split '[\\/]' | Where-Object { $_ -eq ".benchmark-work" }).Count -gt 0) {
          $errors.Add("Round $($run.round) eventLog must be outside .benchmark-work: $resolvedEventLog")
        }
        if (-not (Test-Path -LiteralPath $resolvedEventLog -PathType Leaf)) {
          $errors.Add("Round $($run.round) eventLog does not exist: $resolvedEventLog")
        }
      } catch {
        $errors.Add("Round $($run.round) eventLog path is invalid: $eventLog")
      }
    }
    foreach ($hashName in @("executableSha256", "lockfileSha256")) {
      $hash = Get-FrameworkResultProperty -Object $run -Name $hashName
      if ("$hash" -notmatch '^[0-9a-fA-F]{64}$') {
        $errors.Add("Round $($run.round) $hashName must be a SHA-256 value.")
      }
    }
  }

  foreach ($toolName in @("rustcVerbose", "cargoVersion")) {
    $toolValue = Get-FrameworkResultProperty -Object $Result.toolchain -Name $toolName
    if ([string]::IsNullOrWhiteSpace("$toolValue")) {
      $errors.Add("Result toolchain.$toolName is missing.")
    }
  }
  foreach ($phaseName in $requiredPhases) {
    $entries = @($Result.summary.phases | Where-Object { $_.framework -eq $Framework -and $_.phase -eq $phaseName })
    if ($entries.Count -ne 1 -or $null -eq $entries[0].metrics) {
      $errors.Add("Result summary is missing the unique '$Framework'/$phaseName phase entry.")
    }
  }
  $latencyEntries = @($Result.summary.latency | Where-Object framework -eq $Framework)
  if ($latencyEntries.Count -ne 1 -or $null -eq $latencyEntries[0].showLatencyMs -or $null -eq $latencyEntries[0].hideLatencyMs) {
    $errors.Add("Result summary is missing the unique '$Framework' latency entry.")
  }

  [pscustomobject]@{
    Valid = $errors.Count -eq 0
    Errors = @($errors)
  }
}

function Invoke-BenchmarkFrameworkBuild {
  param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [Parameter(Mandatory = $true)][string]$Framework,
    [Parameter(Mandatory = $true)][ValidateSet("debug", "release")][string]$Configuration,
    [Parameter(Mandatory = $true)][string]$CargoHome,
    [Parameter(Mandatory = $true)][string]$TargetDirectory
  )

  & (Join-Path $RepoRoot "harness\build-all.ps1") `
    -Framework $Framework `
    -Configuration $Configuration `
    -CargoHome $CargoHome `
    -TargetDirectory $TargetDirectory
}

function Invoke-BenchmarkFrameworkMeasurement {
  param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [Parameter(Mandatory = $true)][string]$Framework,
    [Parameter(Mandatory = $true)][ValidateSet("debug", "release")][string]$Configuration,
    [Parameter(Mandatory = $true)][string]$TargetDirectory,
    [Parameter(Mandatory = $true)][string]$ArtifactDirectory,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [switch]$Smoke
  )

  $arguments = @{
    Framework = @($Framework)
    Configuration = $Configuration
    TargetDirectory = $TargetDirectory
    ArtifactDirectory = $ArtifactDirectory
    OutputPath = $OutputPath
  }
  if ($Smoke) {
    $arguments.Smoke = $true
  } else {
    $arguments.Rounds = 3
    $arguments.SampleSeconds = 10
    $arguments.PostHideSettleSeconds = 15
    $arguments.CycleCount = 30
  }
  $null = & (Join-Path $RepoRoot "harness\measure-resident.ps1") @arguments
  if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
    throw "Measurement did not create its result: $OutputPath"
  }
  Get-Content -LiteralPath $OutputPath -Raw -Encoding utf8 | ConvertFrom-Json
}

function Invoke-BenchmarkResultValidation {
  param(
    [Parameter(Mandatory = $true)][object]$Result,
    [Parameter(Mandatory = $true)][string]$Framework,
    [Parameter(Mandatory = $true)][int]$ExpectedRounds
  )
  Test-FrameworkResult -Result $Result -Framework $Framework -ExpectedRounds $ExpectedRounds
}

function Invoke-BenchmarkAnchorComparison {
  param(
    [Parameter(Mandatory = $true)][string]$HistoricalPath,
    [Parameter(Mandatory = $true)][string]$CurrentPath,
    [Parameter(Mandatory = $true)][string]$Framework,
    [Parameter(Mandatory = $true)][string]$OutputPath
  )

  $historical = Get-Content -LiteralPath $HistoricalPath -Raw -Encoding utf8 | ConvertFrom-Json
  $current = Get-Content -LiteralPath $CurrentPath -Raw -Encoding utf8 | ConvertFrom-Json
  $comparison = Compare-ResidentAnchor -Historical $historical -Current $current -Framework $Framework
  $audit = [pscustomobject]@{
    capturedAt = (Get-Date).ToString("o")
    historicalPath = [System.IO.Path]::GetFullPath($HistoricalPath)
    currentPath = [System.IO.Path]::GetFullPath($CurrentPath)
    comparison = $comparison
  }
  $audit | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding utf8
  $comparison
}

function Write-BenchmarkRunStatus {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][object]$Status
  )
  $Status | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $Path -Encoding utf8
}

function Invoke-BenchmarkFrameworkRun {
  param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [Parameter(Mandatory = $true)][string]$Framework,
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [switch]$Anchor,
    [switch]$KeepWorkdir,
    [string]$HistoricalPath
  )

  [void](Get-BenchmarkFrameworkDefinition -Name $Framework)
  if ($Anchor -and $Framework -ne "slint") {
    throw "The historical anchor gate is defined only for slint."
  }
  $resolvedRepo = [System.IO.Path]::GetFullPath($RepoRoot)
  $resolvedOutput = [System.IO.Path]::GetFullPath($OutputDirectory)
  [System.IO.Directory]::CreateDirectory($resolvedOutput) | Out-Null
  $baseName = if ($Anchor) { "$Framework-anchor" } else { $Framework }
  $smokePath = Join-Path $resolvedOutput "$baseName-smoke.json"
  $resultPath = Join-Path $resolvedOutput "$baseName.json"
  $statusPath = Join-Path $resolvedOutput "$baseName-status.json"
  $artifactDirectory = Join-Path $resolvedOutput "$baseName-artifacts"
  $smokeArtifactDirectory = Join-Path $resolvedOutput "$baseName-smoke-artifacts"
  $comparisonPath = Join-Path $resolvedOutput "$baseName-comparison.json"
  $workspace = $null
  $stage = "workspace"

  try {
    $workspace = New-BenchmarkFrameworkWorkspace -RepoRoot $resolvedRepo -Framework $Framework
    $stage = "debug-build"
    $null = Invoke-BenchmarkFrameworkBuild -RepoRoot $resolvedRepo -Framework $Framework -Configuration debug -CargoHome $workspace.CargoHome -TargetDirectory $workspace.TargetDirectory
    $stage = "smoke-measurement"
    $smokeResult = Invoke-BenchmarkFrameworkMeasurement `
      -RepoRoot $resolvedRepo -Framework $Framework -Configuration debug `
      -TargetDirectory $workspace.TargetDirectory -ArtifactDirectory $smokeArtifactDirectory `
      -OutputPath $smokePath -Smoke
    $stage = "smoke-validation"
    $smokeValidation = Invoke-BenchmarkResultValidation -Result $smokeResult -Framework $Framework -ExpectedRounds 1
    if (-not $smokeValidation.Valid) {
      throw "Smoke result validation failed: $($smokeValidation.Errors -join '; ')"
    }

    $stage = "release-build"
    $null = Invoke-BenchmarkFrameworkBuild -RepoRoot $resolvedRepo -Framework $Framework -Configuration release -CargoHome $workspace.CargoHome -TargetDirectory $workspace.TargetDirectory
    $stage = "release-measurement"
    $result = Invoke-BenchmarkFrameworkMeasurement `
      -RepoRoot $resolvedRepo -Framework $Framework -Configuration release `
      -TargetDirectory $workspace.TargetDirectory -ArtifactDirectory $artifactDirectory `
      -OutputPath $resultPath
    $stage = "release-validation"
    $validation = Invoke-BenchmarkResultValidation -Result $result -Framework $Framework -ExpectedRounds 3
    if (-not $validation.Valid) {
      throw "Release result validation failed: $($validation.Errors -join '; ')"
    }

    $comparison = $null
    if ($Anchor) {
      if ([string]::IsNullOrWhiteSpace($HistoricalPath)) {
        throw "HistoricalPath is required for the anchor gate."
      }
      $stage = "anchor-comparison"
      $comparison = Invoke-BenchmarkAnchorComparison `
        -HistoricalPath $HistoricalPath -CurrentPath $resultPath `
        -Framework $Framework -OutputPath $comparisonPath
      if ($comparison.status -ne "pass") {
        throw "Anchor comparison failed (retryEligible=$($comparison.retryEligible), failedMetricCount=$($comparison.failedMetricCount))."
      }
    }

    $cleanup = $null
    if (-not $KeepWorkdir) {
      $stage = "cleanup"
      $cleanup = Remove-BenchmarkFrameworkWorkspace -RepoRoot $resolvedRepo -Framework $Framework -Path $workspace.Root
    }
    $status = [pscustomobject]@{
      status = "success"
      framework = $Framework
      anchor = [bool]$Anchor
      keepWorkdir = [bool]$KeepWorkdir
      resultPath = $resultPath
      smokePath = $smokePath
      comparisonPath = if ($Anchor) { $comparisonPath } else { $null }
      workspaceRoot = $workspace.Root
      cleanup = $cleanup
      completedAt = (Get-Date).ToString("o")
    }
    Write-BenchmarkRunStatus -Path $statusPath -Status $status
    $status
  } catch {
    $failure = [pscustomobject]@{
      status = "failed"
      framework = $Framework
      anchor = [bool]$Anchor
      stage = $stage
      error = $_.Exception.Message
      workspaceRoot = if ($null -ne $workspace) { $workspace.Root } else { $null }
      workspacePreserved = $null -ne $workspace
      failedAt = (Get-Date).ToString("o")
    }
    Write-BenchmarkRunStatus -Path $statusPath -Status $failure
    throw
  }
}
