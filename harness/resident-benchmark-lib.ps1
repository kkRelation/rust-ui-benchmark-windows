function Get-RotatedFrameworkOrder {
  param(
    [Parameter(Mandatory = $true)][string[]]$Frameworks,
    [Parameter(Mandatory = $true)][int]$Round
  )

  if ($Frameworks.Count -eq 0) { return @() }
  $offset = (($Round - 1) % $Frameworks.Count + $Frameworks.Count) % $Frameworks.Count
  @(
    for ($index = 0; $index -lt $Frameworks.Count; $index++) {
      $Frameworks[($index + $offset) % $Frameworks.Count]
    }
  )
}

function Get-BenchmarkStatistics {
  param([Parameter(Mandatory = $true)][AllowNull()][AllowEmptyCollection()][object[]]$Values)

  $numbers = @(
    $Values |
      Where-Object { $null -ne $_ } |
      ForEach-Object { [double]$_ } |
      Sort-Object
  )
  if ($numbers.Count -eq 0) {
    return [pscustomobject]@{ count = 0; median = $null; minimum = $null; maximum = $null }
  }
  $middle = [math]::Floor($numbers.Count / 2)
  $median = if ($numbers.Count % 2 -eq 1) {
    $numbers[$middle]
  } else {
    ($numbers[$middle - 1] + $numbers[$middle]) / 2
  }
  [pscustomobject]@{
    count = $numbers.Count
    median = [math]::Round($median, 3)
    minimum = [math]::Round($numbers[0], 3)
    maximum = [math]::Round($numbers[-1], 3)
  }
}

function New-ResidentBenchmarkSummary {
  param(
    [Parameter(Mandatory = $true)][object[]]$Runs,
    [Parameter(Mandatory = $true)][string[]]$Frameworks
  )
  $metrics = @(
    "workingSetMb", "privateWorkingSetMb", "privateBytesMb",
    "cpuSingleCorePercent", "cpuMachinePercent",
    "gpuEngineAveragePercent", "gpuEnginePeakPercent",
    "dedicatedGpuPeakMb", "sharedGpuPeakMb"
  )
  $phaseSummaries = @()
  foreach ($frameworkName in $Frameworks) {
    $frameworkRuns = @($Runs | Where-Object { $_.framework -eq $frameworkName -and $_.status -eq "ok" })
    foreach ($phaseName in @("hiddenIdle", "visibleIdle", "workload400", "postHideIdle", "postCycleIdle")) {
      $metricSummary = [ordered]@{}
      foreach ($metric in $metrics) {
        $values = @($frameworkRuns | ForEach-Object { $_.phases.$phaseName.$metric })
        $metricSummary[$metric] = Get-BenchmarkStatistics -Values $values
      }
      $phaseSummaries += [pscustomobject]@{
        framework = $frameworkName
        phase = $phaseName
        metrics = [pscustomobject]$metricSummary
      }
    }
  }
  [pscustomobject]@{
    phases = $phaseSummaries
    latency = @(
      foreach ($frameworkName in $Frameworks) {
        $frameworkRuns = @($Runs | Where-Object { $_.framework -eq $frameworkName -and $_.status -eq "ok" })
        [pscustomobject]@{
          framework = $frameworkName
          showLatencyMs = Get-BenchmarkStatistics -Values @($frameworkRuns.showLatencyMs)
          hideLatencyMs = Get-BenchmarkStatistics -Values @($frameworkRuns.hideLatencyMs)
        }
      }
    )
  }
}

function Wait-ProbeEvent {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Event,
    [int]$AfterLine = 0,
    [ValidateRange(1, 300)][int]$TimeoutSeconds = 60,
    [System.Diagnostics.Process]$Process
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    if (Test-Path -LiteralPath $Path) {
      $lines = @(Get-Content -LiteralPath $Path -Encoding utf8)
      for ($index = [math]::Max(0, $AfterLine); $index -lt $lines.Count; $index++) {
        if ([string]::IsNullOrWhiteSpace($lines[$index])) { continue }
        try {
          $value = $lines[$index] | ConvertFrom-Json
          if ($value.event -eq $Event) {
            return [pscustomobject]@{ lineNumber = $index + 1; value = $value }
          }
          if ($value.event -eq "error") {
            throw "Probe reported an error: $($value.detail.message)"
          }
        } catch [System.ArgumentException] {
          # The writer may have flushed between a file read and the last newline.
        }
      }
    }
    if ($null -ne $Process -and $Process.HasExited) {
      throw "Probe exited with code $($Process.ExitCode) while waiting for '$Event'"
    }
    Start-Sleep -Milliseconds 20
  } while ((Get-Date) -lt $deadline)

  throw "Timed out waiting for probe event '$Event' in $Path"
}
