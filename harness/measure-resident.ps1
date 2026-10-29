param(
  [string[]]$Framework = @(),
  [ValidateRange(1, 20)][int]$Rounds = 3,
  [ValidateRange(1, 100)][int]$RoundStart = 1,
  [ValidateSet("debug", "release")][string]$Configuration = "release",
  [ValidateRange(1, 30)][int]$SampleSeconds = 10,
  [ValidateRange(0, 120)][int]$PostHideSettleSeconds = 15,
  [ValidateRange(1, 1000)][int]$CycleCount = 30,
  [switch]$Smoke,
  [string]$OutputPath = ".\results\local\resident.json",
  [string]$TargetDirectory,
  [string]$ArtifactDirectory
)

$ErrorActionPreference = "Stop"
$benchmarkRoot = $PSScriptRoot
$repoRoot = (Resolve-Path (Join-Path $benchmarkRoot "..")).Path
$measureScript = Join-Path $benchmarkRoot "measure-process-tree.ps1"
. (Join-Path $benchmarkRoot "resident-benchmark-lib.ps1")
. (Join-Path $benchmarkRoot "process-tree-lib.ps1")
. (Join-Path $benchmarkRoot "framework-registry.ps1")
. (Join-Path $benchmarkRoot "benchmark-artifact-lib.ps1")

if ($Framework.Count -eq 0) {
  $Framework = @(
    (Get-BenchmarkFrameworkDefinitions).Values |
      Where-Object Enabled |
      ForEach-Object Name
  )
}

$probeDefinitions = [ordered]@{}
foreach ($frameworkName in $Framework) {
  $definition = Get-BenchmarkFrameworkDefinition -Name $frameworkName
  if (-not $definition.Enabled) {
    throw "Benchmark framework is declared but not enabled: $frameworkName"
  }
  $probeDefinitions[$frameworkName] = $definition
}

if ($Smoke) {
  $Rounds = 1
  $SampleSeconds = 1
  $PostHideSettleSeconds = 1
  $CycleCount = 2
}

if (-not ("ResidentBench.NativeWindows" -as [type])) {
  Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace ResidentBench {
  public sealed class WindowInfo {
    public IntPtr Handle { get; set; }
    public int ProcessId { get; set; }
    public string Title { get; set; }
    public bool Visible { get; set; }
    public int Width { get; set; }
    public int Height { get; set; }
  }

  public static class NativeWindows {
    private delegate bool EnumWindowsProc(IntPtr handle, IntPtr parameter);
    [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc callback, IntPtr parameter);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextLengthW(IntPtr handle);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowTextW(IntPtr handle, StringBuilder text, int count);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr handle, out uint processId);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr handle);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr handle, out Rect rect);

    public static WindowInfo[] Enumerate(int[] processIds) {
      var accepted = new HashSet<int>(processIds);
      var result = new List<WindowInfo>();
      EnumWindows((handle, parameter) => {
        uint processId;
        GetWindowThreadProcessId(handle, out processId);
        if (!accepted.Contains((int)processId)) return true;
        var length = GetWindowTextLengthW(handle);
        if (length == 0) return true;
        var title = new StringBuilder(length + 1);
        GetWindowTextW(handle, title, title.Capacity);
        var value = title.ToString();
        if (value != "UI Framework Bench - Main" && value != "UI Framework Bench - Auxiliary Canvas") return true;
        Rect rect;
        GetWindowRect(handle, out rect);
        result.Add(new WindowInfo {
          Handle = handle,
          ProcessId = (int)processId,
          Title = value,
          Visible = IsWindowVisible(handle),
          Width = Math.Max(0, rect.Right - rect.Left),
          Height = Math.Max(0, rect.Bottom - rect.Top)
        });
        return true;
      }, IntPtr.Zero);
      return result.ToArray();
    }
  }
}
"@
}

function Get-ProcessTreeIds {
  param([int]$RootProcessId)
  @(Get-ProcessTreeRows -RootProcessId $RootProcessId | ForEach-Object { [int]$_.ProcessId })
}

function Get-BenchmarkWindows {
  param([int]$RootProcessId)
  $ids = @(Get-ProcessTreeIds -RootProcessId $RootProcessId)
  @([ResidentBench.NativeWindows]::Enumerate([int[]]$ids) | Sort-Object Title)
}

function Wait-WindowState {
  param(
    [int]$RootProcessId,
    [ValidateSet("hidden", "visible")][string]$State,
    [string]$Stage = "unspecified",
    [int]$TimeoutSeconds = 30
  )
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    $windows = @(Get-BenchmarkWindows -RootProcessId $RootProcessId)
    $visibleCount = @($windows | Where-Object Visible).Count
    if ($windows.Count -eq 2 -and (
      ($State -eq "visible" -and $visibleCount -eq 2) -or
      ($State -eq "hidden" -and $visibleCount -eq 0)
    )) {
      return $windows
    }
    Start-Sleep -Milliseconds 5
  } while ((Get-Date) -lt $deadline)
  $observed = @($windows | ForEach-Object { "$($_.Title):visible=$($_.Visible)" }) -join "; "
  throw "Expected two $State benchmark windows during '$Stage' for PID $RootProcessId; observed $($windows.Count): $observed"
}

function Start-BenchmarkProbe {
  param([string]$Executable, [string]$EventLog)
  $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = $Executable
  $startInfo.WorkingDirectory = Split-Path -Parent $Executable
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  $startInfo.RedirectStandardInput = $true
  [void]$startInfo.ArgumentList.Add("--event-log")
  [void]$startInfo.ArgumentList.Add($EventLog)
  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  if (-not $process.Start()) { throw "Failed to start $Executable" }
  $process
}

function Stop-BenchmarkProbe {
  param([System.Diagnostics.Process]$Process)
  if ($null -eq $Process -or $Process.HasExited) { return }
  $ids = @(Get-ProcessTreeIds -RootProcessId $Process.Id | Sort-Object -Descending)
  foreach ($processId in $ids) {
    Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue
  }
}

function Measure-ResourcePhase {
  param([int]$RootProcessId, [int]$Seconds)
  (& $measureScript -RootProcessId $RootProcessId -CpuSampleSeconds $Seconds -GpuSamples $Seconds) |
    ConvertFrom-Json
}

function Start-WorkloadSample {
  param([int]$RootProcessId, [string]$Directory)
  $readyPath = Join-Path $Directory "sampler-ready.txt"
  $resultPath = Join-Path $Directory "workload-sample.json"
  $errorPath = Join-Path $Directory "workload-sample.err.txt"
  $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
  $startInfo.FileName = (Get-Command pwsh).Source
  $startInfo.UseShellExecute = $false
  $startInfo.CreateNoWindow = $true
  foreach ($argument in @(
    "-NoLogo", "-NoProfile", "-File", $measureScript,
    "-RootProcessId", "$RootProcessId",
    "-CpuSampleSeconds", "8", "-GpuSamples", "8",
    "-ReadyPath", $readyPath
  )) { [void]$startInfo.ArgumentList.Add($argument) }
  $startInfo.RedirectStandardOutput = $true
  $startInfo.RedirectStandardError = $true
  $process = [System.Diagnostics.Process]::new()
  $process.StartInfo = $startInfo
  if (-not $process.Start()) { throw "Failed to start workload sampler" }
  [pscustomobject]@{
    process = $process
    readyPath = $readyPath
    resultPath = $resultPath
    errorPath = $errorPath
  }
}

function Complete-WorkloadSample {
  param([pscustomobject]$Sampler)
  if (-not $Sampler.process.WaitForExit(120000)) {
    Stop-Process -Id $Sampler.process.Id -Force -ErrorAction SilentlyContinue
    throw "Workload sampler timed out"
  }
  $stdout = $Sampler.process.StandardOutput.ReadToEnd()
  $stderr = $Sampler.process.StandardError.ReadToEnd()
  if ($Sampler.process.ExitCode -ne 0) {
    throw "Workload sampler failed: $stderr"
  }
  $stdout | ConvertFrom-Json
}

function Wait-SamplerReady {
  param([pscustomobject]$Sampler)
  $deadline = (Get-Date).AddSeconds(60)
  do {
    if (Test-Path -LiteralPath $Sampler.readyPath) { return }
    if ($Sampler.process.HasExited) {
      $stderr = $Sampler.process.StandardError.ReadToEnd()
      throw "Workload sampler exited before ready: $stderr"
    }
    Start-Sleep -Milliseconds 10
  } while ((Get-Date) -lt $deadline)
  throw "Timed out waiting for workload sampler"
}

function Invoke-ProbeRound {
  param(
    [string]$FrameworkName,
    [int]$Round,
    [string]$Executable,
    [string]$ArtifactLabel,
    [string]$TemporaryDirectory
  )
  $eventLog = Join-Path $TemporaryDirectory "events.jsonl"
  New-Item -ItemType File -Force -Path $eventLog | Out-Null
  $process = $null
  try {
    $process = Start-BenchmarkProbe -Executable $Executable -EventLog $eventLog
    $ready = Wait-ProbeEvent -Path $eventLog -Event "ready-hidden" -TimeoutSeconds 90 -Process $process
    $hiddenWindows = @(Wait-WindowState -RootProcessId $process.Id -State hidden -Stage "ready-hidden")
    $hidden = Measure-ResourcePhase -RootProcessId $process.Id -Seconds $SampleSeconds

    $showClock = [System.Diagnostics.Stopwatch]::StartNew()
    $process.StandardInput.WriteLine("show")
    $process.StandardInput.Flush()
    $show = Wait-ProbeEvent -Path $eventLog -Event "show-end" -AfterLine $ready.lineNumber -TimeoutSeconds 30 -Process $process
    $visibleWindows = @(Wait-WindowState -RootProcessId $process.Id -State visible -Stage "warm-show")
    $showClock.Stop()
    $visible = Measure-ResourcePhase -RootProcessId $process.Id -Seconds $SampleSeconds

    $sampler = Start-WorkloadSample -RootProcessId $process.Id -Directory $TemporaryDirectory
    Wait-SamplerReady -Sampler $sampler
    $process.StandardInput.WriteLine("workload")
    $process.StandardInput.Flush()
    $workloadEnd = Wait-ProbeEvent -Path $eventLog -Event "workload-end" -AfterLine $show.lineNumber -TimeoutSeconds 30 -Process $process
    $workload = Complete-WorkloadSample -Sampler $sampler

    $hideClock = [System.Diagnostics.Stopwatch]::StartNew()
    $process.StandardInput.WriteLine("hide")
    $process.StandardInput.Flush()
    $hide = Wait-ProbeEvent -Path $eventLog -Event "hide-end" -AfterLine $workloadEnd.lineNumber -TimeoutSeconds 30 -Process $process
    $postHideWindows = @(Wait-WindowState -RootProcessId $process.Id -State hidden -Stage "warm-hide")
    $hideClock.Stop()
    if ($PostHideSettleSeconds -gt 0) { Start-Sleep -Seconds $PostHideSettleSeconds }
    $postHide = Measure-ResourcePhase -RootProcessId $process.Id -Seconds $SampleSeconds

    $process.StandardInput.WriteLine("cycle $CycleCount")
    $process.StandardInput.Flush()
    $cycleEnd = Wait-ProbeEvent -Path $eventLog -Event "cycle-end" -AfterLine $hide.lineNumber -TimeoutSeconds 120 -Process $process
    $postCycleWindows = @(Wait-WindowState -RootProcessId $process.Id -State hidden -Stage "cycle-end")
    $postCycle = Measure-ResourcePhase -RootProcessId $process.Id -Seconds $SampleSeconds

    $process.StandardInput.WriteLine("quit")
    $process.StandardInput.Flush()
    [void](Wait-ProbeEvent -Path $eventLog -Event "quit" -AfterLine $cycleEnd.lineNumber -TimeoutSeconds 10 -Process $process)
    [void]$process.WaitForExit(10000)

    [pscustomobject]@{
      framework = $FrameworkName
      round = $Round
      status = "ok"
      executable = $ArtifactLabel
      executableSizeMb = [math]::Round((Get-Item -LiteralPath $Executable).Length / 1MB, 1)
      showLatencyMs = [math]::Round($showClock.Elapsed.TotalMilliseconds, 3)
      hideLatencyMs = [math]::Round($hideClock.Elapsed.TotalMilliseconds, 3)
      topology = [pscustomobject]@{
        hidden = @($hiddenWindows | Select-Object ProcessId,Title,Visible,Width,Height)
        visible = @($visibleWindows | Select-Object ProcessId,Title,Visible,Width,Height)
        postHide = @($postHideWindows | Select-Object ProcessId,Title,Visible,Width,Height)
        postCycle = @($postCycleWindows | Select-Object ProcessId,Title,Visible,Width,Height)
      }
      phases = [pscustomobject]@{
        hiddenIdle = $hidden
        visibleIdle = $visible
        workload400 = $workload
        postHideIdle = $postHide
        postCycleIdle = $postCycle
      }
    }
  } finally {
    Stop-BenchmarkProbe -Process $process
  }
}

$resolvedOutput = [System.IO.Path]::GetFullPath((Join-Path $repoRoot $OutputPath))
$outputDirectory = Split-Path -Parent $resolvedOutput
[System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
$resolvedArtifactDirectory = if ([string]::IsNullOrWhiteSpace($ArtifactDirectory)) {
  Join-Path $outputDirectory (([System.IO.Path]::GetFileNameWithoutExtension($resolvedOutput)) + "-artifacts")
} else {
  Resolve-BenchmarkPath -RepoRoot $repoRoot -Path $ArtifactDirectory
}
[System.IO.Directory]::CreateDirectory($resolvedArtifactDirectory) | Out-Null

$runs = @()
$roundEnd = $RoundStart + $Rounds - 1
for ($round = $RoundStart; $round -lt ($RoundStart + $Rounds); $round++) {
  $order = @(Get-RotatedFrameworkOrder -Frameworks $Framework -Round $round)
  foreach ($frameworkName in $order) {
    $definition = $probeDefinitions[$frameworkName]
    $artifact = Get-BenchmarkProbeArtifact `
      -RepoRoot $repoRoot `
      -Definition $definition `
      -Configuration $Configuration `
      -TargetDirectory $TargetDirectory
    $artifactLabel = $artifact.Label
    $executable = $artifact.Path
    if (-not (Test-Path -LiteralPath $executable)) {
      throw "Missing $Configuration probe binary: $artifactLabel"
    }
    $executableSha256 = Get-BenchmarkFileSha256 -Path $executable
    $lockfileSha256 = Get-BenchmarkFileSha256 -Path $artifact.LockfilePath
    $temporaryDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("ui-bench-" + [guid]::NewGuid().ToString("N"))
    [System.IO.Directory]::CreateDirectory($temporaryDirectory) | Out-Null
    Write-Host "[$round/$roundEnd] $frameworkName resident lifecycle"
    $run = $null
    try {
      $run = Invoke-ProbeRound `
        -FrameworkName $frameworkName `
        -Round $round `
        -Executable $executable `
        -ArtifactLabel $artifactLabel `
        -TemporaryDirectory $temporaryDirectory
    } catch {
      $run = [pscustomobject]@{
        framework = $frameworkName
        round = $round
        status = "failed"
        executable = $artifactLabel
        error = $_.Exception.Message
      }
      Write-Warning "$frameworkName round $round failed: $($_.Exception.Message)"
    } finally {
      try {
        $durableEventLog = Save-BenchmarkRoundEventLog `
          -SourcePath (Join-Path $temporaryDirectory "events.jsonl") `
          -ArtifactDirectory $resolvedArtifactDirectory `
          -Framework $frameworkName `
          -Round $round
        $run | Add-Member -NotePropertyName eventLog -NotePropertyValue $durableEventLog -Force
        $run | Add-Member -NotePropertyName executableSha256 -NotePropertyValue $executableSha256 -Force
        $run | Add-Member -NotePropertyName lockfileSha256 -NotePropertyValue $lockfileSha256 -Force
      } finally {
        $resolvedTemporary = [System.IO.Path]::GetFullPath($temporaryDirectory)
        $resolvedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
        if ($resolvedTemporary.StartsWith($resolvedTempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
          Remove-Item -LiteralPath $resolvedTemporary -Recurse -Force -ErrorAction SilentlyContinue
        }
      }
    }
    $runs += $run
  }
}

$os = Get-CimInstance Win32_OperatingSystem
$computer = Get-CimInstance Win32_ComputerSystem
$processors = @(Get-CimInstance Win32_Processor)
$videoControllers = @(Get-CimInstance Win32_VideoController)
$rustcVerbose = (& rustc -vV) -join "`n"
if ($LASTEXITCODE -ne 0) { throw "rustc -vV failed with exit code $LASTEXITCODE" }
$cargoVersion = (& cargo -V) -join "`n"
if ($LASTEXITCODE -ne 0) { throw "cargo -V failed with exit code $LASTEXITCODE" }
$pins = [ordered]@{}
foreach ($frameworkName in $Framework) {
  $definition = $probeDefinitions[$frameworkName]
  $pins[$definition.PinName] = $definition.Pin
}
$result = [pscustomobject]@{
  schemaVersion = 2
  capturedAt = (Get-Date).ToString("o")
  protocol = [pscustomobject]@{
    resident = $true
    windows = 2
    mainContentSize = "700x480"
    auxiliaryContentSize = "1200x760"
    workload = "400 shared-state updates at 20 ms"
    phases = @("hiddenIdle", "warmShow", "visibleIdle", "workload400", "warmHide", "postHideIdle", "cycle30", "postCycleIdle")
    sampleSeconds = $SampleSeconds
    postHideSettleSeconds = $PostHideSettleSeconds
    cycleCount = $CycleCount
    rounds = $Rounds
    roundStart = $RoundStart
    rotatingOrder = $true
    smoke = [bool]$Smoke
  }
  pins = [pscustomobject]$pins
  environment = [pscustomobject]@{
    os = $os.Caption
    osVersion = $os.Version
    machine = $computer.Model
    logicalProcessors = $computer.NumberOfLogicalProcessors
    cpu = @($processors | ForEach-Object Name)
    gpu = @($videoControllers | ForEach-Object { [pscustomobject]@{ name = $_.Name; driverVersion = $_.DriverVersion } })
    powerPlan = (powercfg /GETACTIVESCHEME) -join " "
  }
  toolchain = [pscustomobject]@{
    rustcVerbose = $rustcVerbose
    cargoVersion = $cargoVersion
  }
  runs = $runs
  summary = New-ResidentBenchmarkSummary -Runs $runs -Frameworks $Framework
}

$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resolvedOutput -Encoding utf8
$result | ConvertTo-Json -Depth 12
