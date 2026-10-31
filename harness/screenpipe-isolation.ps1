function Get-BenchmarkScreenpipeProcesses {
  @(
    Get-CimInstance Win32_Process -Filter "Name = 'screenpipe-app.exe'" |
      Sort-Object ProcessId
  )
}

function Get-BenchmarkScreenpipeLaunchArguments {
  param(
    [Parameter(Mandatory = $true)][string]$ExecutablePath,
    [AllowEmptyString()][string]$CommandLine
  )

  if ([string]::IsNullOrWhiteSpace($CommandLine)) { return "" }
  $trimmed = $CommandLine.Trim()
  foreach ($prefix in @(('"' + $ExecutablePath + '"'), $ExecutablePath)) {
    if ($trimmed.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
      return $trimmed.Substring($prefix.Length).Trim()
    }
  }
  throw "Screenpipe command line does not start with its executable path: $CommandLine"
}

function Test-BenchmarkScreenpipeHealthy {
  try {
    $health = Invoke-RestMethod -Uri "http://localhost:3030/health" -TimeoutSec 2
    "$($health.status)" -eq "healthy"
  } catch {
    $false
  }
}

function Enter-BenchmarkScreenpipeIsolation {
  $processes = @(Get-BenchmarkScreenpipeProcesses)
  $launches = @(
    foreach ($process in $processes) {
      if ([string]::IsNullOrWhiteSpace("$($process.ExecutablePath)")) {
        throw "Cannot restore Screenpipe process $($process.ProcessId): executable path is unavailable."
      }
      [pscustomobject]@{
        executablePath = "$($process.ExecutablePath)"
        arguments = Get-BenchmarkScreenpipeLaunchArguments `
          -ExecutablePath "$($process.ExecutablePath)" `
          -CommandLine "$($process.CommandLine)"
      }
    }
  )
  $state = [pscustomobject]@{
    wasRunning = $processes.Count -gt 0
    stoppedProcessCount = $processes.Count
    launches = $launches
    stoppedAt = $null
  }

  try {
    foreach ($process in $processes) {
      $native = Get-Process -Id $process.ProcessId -ErrorAction SilentlyContinue
      if ($null -eq $native) { continue }
      $closed = $native.CloseMainWindow()
      if ($closed) {
        [void]$native.WaitForExit(3000)
      }
      if (-not $native.HasExited) {
        Stop-Process -Id $native.Id -Force -ErrorAction Stop
      }
    }

    $deadline = (Get-Date).AddSeconds(15)
    do {
      $remaining = @(Get-BenchmarkScreenpipeProcesses)
      if ($remaining.Count -eq 0) { break }
      Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $deadline)
    if ($remaining.Count -gt 0) {
      throw "Screenpipe is still running after isolation: $(@($remaining.ProcessId) -join ', ')"
    }

    $state.stoppedAt = (Get-Date).ToString("o")
    $state
  } catch {
    $stopError = $_
    try {
      $null = Exit-BenchmarkScreenpipeIsolation -State $state
    } catch {
      throw "$($stopError.Exception.Message) Screenpipe rollback also failed: $($_.Exception.Message)"
    }
    throw $stopError
  }
}

function Exit-BenchmarkScreenpipeIsolation {
  param([Parameter(Mandatory = $true)][object]$State)

  if (-not [bool]$State.wasRunning) {
    return [pscustomobject]@{
      required = $false
      startedProcessCount = 0
      healthy = $null
      restoredAt = (Get-Date).ToString("o")
    }
  }

  $started = 0
  if (@(Get-BenchmarkScreenpipeProcesses).Count -eq 0) {
    foreach ($launch in @($State.launches)) {
      $startArguments = @{
        FilePath = "$($launch.executablePath)"
        WorkingDirectory = Split-Path -Parent "$($launch.executablePath)"
        WindowStyle = "Hidden"
      }
      if (-not [string]::IsNullOrWhiteSpace("$($launch.arguments)")) {
        $startArguments.ArgumentList = "$($launch.arguments)"
      }
      $null = Start-Process @startArguments
      $started++
    }
  }

  $deadline = (Get-Date).AddSeconds(55)
  $healthy = $false
  do {
    if (@(Get-BenchmarkScreenpipeProcesses).Count -gt 0 -and
        (Test-BenchmarkScreenpipeHealthy)) {
      $healthy = $true
      break
    }
    Start-Sleep -Seconds 1
  } while ((Get-Date) -lt $deadline)
  if (-not $healthy) {
    throw "Screenpipe was restarted but did not report healthy within 55 seconds."
  }

  [pscustomobject]@{
    required = $true
    startedProcessCount = $started
    healthy = $true
    restoredAt = (Get-Date).ToString("o")
  }
}
