param(
  [Parameter(Mandatory = $true)]
  [int]$RootProcessId,
  [ValidateRange(1, 30)]
  [int]$CpuSampleSeconds = 4,
  [ValidateRange(1, 30)]
  [int]$GpuSamples = 3,
  [string]$ReadyPath
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "process-tree-lib.ps1")

function Get-CounterTotal {
  param([object[]]$Samples, [string]$Suffix)

  $suffixPattern = [regex]::Escape($Suffix) + "$"
  $matching = @($Samples | Where-Object { $_.Path -match $suffixPattern })
  if ($matching.Count -eq 0) { return $null }
  [double](($matching | Measure-Object CookedValue -Sum).Sum)
}

function Get-TimestampTotals {
  param([object[]]$Samples, [string]$Suffix)

  $suffixPattern = [regex]::Escape($Suffix) + "$"
  @(
    $Samples |
      Where-Object { $_.Path -match $suffixPattern } |
      Group-Object Timestamp |
      Sort-Object { [datetime]$_.Name } |
      ForEach-Object {
        [pscustomobject]@{
          timestamp = [datetime]$_.Name
          value = [double](($_.Group | Measure-Object CookedValue -Sum).Sum)
        }
      }
  )
}

function Convert-BytesToMb {
  param([AllowNull()][Nullable[double]]$Value)
  if ($null -eq $Value) { return $null }
  [math]::Round($Value / 1MB, 1)
}

function Get-SeriesValue {
  param(
    [object[]]$Series,
    [ValidateSet("First", "Last", "Maximum", "Average")]
    [string]$Kind
  )

  if ($Series.Count -eq 0) { return $null }
  switch ($Kind) {
    "First" { return [double]$Series[0].value }
    "Last" { return [double]$Series[-1].value }
    "Maximum" { return [double](($Series.value | Measure-Object -Maximum).Maximum) }
    "Average" { return [double](($Series.value | Measure-Object -Average).Average) }
  }
}

$treeRows = @(Get-ProcessTreeRows -RootProcessId $RootProcessId)
if ($treeRows.Count -eq 0) { throw "No process tree found for PID $RootProcessId" }

$liveProcesses = @(
  $treeRows | ForEach-Object {
    Get-Process -Id ([int]$_.ProcessId) -ErrorAction SilentlyContinue
  }
)
$liveIds = @($liveProcesses | ForEach-Object { [int]$_.Id })
if ($liveIds.Count -eq 0) { throw "No live processes found for PID $RootProcessId" }

$cpuBefore = @{}
foreach ($process in $liveProcesses) {
  $cpuBefore[$process.Id] = $process.TotalProcessorTime.TotalSeconds
}

$pidPattern = "pid_(" + (($liveIds | ForEach-Object { [regex]::Escape("$_") }) -join "|") + ")_"
$gpuCounterPaths = @()
try {
  $gpuCounterPaths = @(
    typeperf -qx "GPU Engine" |
      Where-Object { $_ -match $pidPattern -and $_ -match "\\Utilization Percentage$" }
    typeperf -qx "GPU Process Memory" |
      Where-Object {
        $_ -match $pidPattern -and
        ($_ -match "\\Dedicated Usage$" -or $_ -match "\\Shared Usage$")
      }
  )
} catch {
  $gpuCounterPaths = @()
}

$sampleSeconds = [math]::Max($CpuSampleSeconds, $GpuSamples)
if (-not [string]::IsNullOrWhiteSpace($ReadyPath)) {
  [System.IO.File]::WriteAllText(
    [System.IO.Path]::GetFullPath($ReadyPath),
    (Get-Date).ToString("o")
  )
}
$sampleStartedAt = Get-Date
$sampleStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$gpuCounterSamples = @()
if ($gpuCounterPaths.Count -gt 0) {
  try {
    # One immediate counter sample plus one per second spans sampleSeconds.
    # CPU deltas wrap this same call, so CPU and GPU share a wall-clock interval.
    $gpuCounterSamples = @(
      (Get-Counter `
        -Counter $gpuCounterPaths `
        -SampleInterval 1 `
        -MaxSamples ($sampleSeconds + 1)).CounterSamples
    )
  } catch {
    $remainingMilliseconds = $sampleSeconds * 1000 - $sampleStopwatch.ElapsedMilliseconds
    if ($remainingMilliseconds -gt 0) { Start-Sleep -Milliseconds $remainingMilliseconds }
  }
} else {
  Start-Sleep -Seconds $sampleSeconds
}
$sampleStopwatch.Stop()
$sampleEndedAt = Get-Date
$actualSampleSeconds = [math]::Max($sampleStopwatch.Elapsed.TotalSeconds, 0.001)

$cpuSeconds = 0.0
foreach ($processId in $liveIds) {
  $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
  if ($null -ne $process -and $cpuBefore.ContainsKey($processId)) {
    $cpuSeconds += [math]::Max(
      0,
      $process.TotalProcessorTime.TotalSeconds - $cpuBefore[$processId]
    )
  }
}
$singleCoreCpuPercent = $cpuSeconds / $actualSampleSeconds * 100
$logicalProcessorCount = [Environment]::ProcessorCount

$processCounterPaths = @(
  foreach ($processId in $liveIds) {
    $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
    if ($null -ne $process) {
      $instance = "$($process.ProcessName):$($process.Id)"
      "\Process V2($instance)\Working Set - Private"
      "\Process V2($instance)\Private Bytes"
      "\Process V2($instance)\Working Set"
    }
  }
)
$processCounterSamples = @()
if ($processCounterPaths.Count -gt 0) {
  $processCounterSamples = @((Get-Counter -Counter $processCounterPaths).CounterSamples)
}

$workingSet = Get-CounterTotal -Samples $processCounterSamples -Suffix "\Working Set"
$privateWorkingSet = Get-CounterTotal -Samples $processCounterSamples -Suffix "\Working Set - Private"
$privateBytes = Get-CounterTotal -Samples $processCounterSamples -Suffix "\Private Bytes"

$engineSeries = @(Get-TimestampTotals -Samples $gpuCounterSamples -Suffix "\Utilization Percentage")
$dedicatedSeries = @(Get-TimestampTotals -Samples $gpuCounterSamples -Suffix "\Dedicated Usage")
$sharedSeries = @(Get-TimestampTotals -Samples $gpuCounterSamples -Suffix "\Shared Usage")

$gpuEngineAverage = Get-SeriesValue -Series $engineSeries -Kind Average
$gpuEnginePeak = Get-SeriesValue -Series $engineSeries -Kind Maximum
$dedicatedStart = Get-SeriesValue -Series $dedicatedSeries -Kind First
$dedicatedEnd = Get-SeriesValue -Series $dedicatedSeries -Kind Last
$dedicatedPeak = Get-SeriesValue -Series $dedicatedSeries -Kind Maximum
$sharedStart = Get-SeriesValue -Series $sharedSeries -Kind First
$sharedEnd = Get-SeriesValue -Series $sharedSeries -Kind Last
$sharedPeak = Get-SeriesValue -Series $sharedSeries -Kind Maximum

$rendererCount = @(
  $treeRows | Where-Object { $_.CommandLine -match "--type=renderer(?:\s|$)" }
).Count

[pscustomobject]@{
  capturedAt = $sampleEndedAt.ToString("o")
  sampleStartedAt = $sampleStartedAt.ToString("o")
  sampleEndedAt = $sampleEndedAt.ToString("o")
  sampleDurationSeconds = [math]::Round($actualSampleSeconds, 3)
  rootProcessId = $RootProcessId
  processCount = $liveProcesses.Count
  rendererCount = $rendererCount
  workingSetMb = Convert-BytesToMb $workingSet
  privateWorkingSetMb = Convert-BytesToMb $privateWorkingSet
  privateBytesMb = Convert-BytesToMb $privateBytes
  cpuSampleSeconds = $CpuSampleSeconds
  cpuSingleCorePercent = [math]::Round($singleCoreCpuPercent, 3)
  cpuMachinePercent = [math]::Round($singleCoreCpuPercent / $logicalProcessorCount, 3)
  logicalProcessorCount = $logicalProcessorCount
  gpuSamples = $engineSeries.Count
  gpuEnginePercent = if ($null -eq $gpuEngineAverage) { $null } else { [math]::Round($gpuEngineAverage, 3) }
  gpuEngineAveragePercent = if ($null -eq $gpuEngineAverage) { $null } else { [math]::Round($gpuEngineAverage, 3) }
  gpuEnginePeakPercent = if ($null -eq $gpuEnginePeak) { $null } else { [math]::Round($gpuEnginePeak, 3) }
  dedicatedGpuMb = Convert-BytesToMb $dedicatedEnd
  dedicatedGpuStartMb = Convert-BytesToMb $dedicatedStart
  dedicatedGpuEndMb = Convert-BytesToMb $dedicatedEnd
  dedicatedGpuPeakMb = Convert-BytesToMb $dedicatedPeak
  sharedGpuMb = Convert-BytesToMb $sharedEnd
  sharedGpuStartMb = Convert-BytesToMb $sharedStart
  sharedGpuEndMb = Convert-BytesToMb $sharedEnd
  sharedGpuPeakMb = Convert-BytesToMb $sharedPeak
  processes = @(
    $treeRows |
      Sort-Object ProcessId |
      ForEach-Object {
        [pscustomobject]@{
          processId = [int]$_.ProcessId
          parentProcessId = [int]$_.ParentProcessId
          name = $_.Name
          renderer = $_.CommandLine -match "--type=renderer(?:\s|$)"
        }
      }
  )
} | ConvertTo-Json -Depth 5
