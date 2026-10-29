$scriptPath = Join-Path $PSScriptRoot "..\measure-process-tree.ps1"
$processTreeLibrary = Join-Path $PSScriptRoot "..\process-tree-lib.ps1"
. $processTreeLibrary

Describe "measure-process-tree concurrent resource sampling" {
  It "rejects stale parent IDs after PID reuse" {
    $rootStart = [datetime]"2026-10-28T12:00:00Z"
    $snapshot = @(
      [pscustomobject]@{ ProcessId=100; ParentProcessId=1; CreationDate=$rootStart; Name="root" },
      [pscustomobject]@{ ProcessId=200; ParentProcessId=100; CreationDate=$rootStart.AddMinutes(-5); Name="stale" },
      [pscustomobject]@{ ProcessId=300; ParentProcessId=100; CreationDate=$rootStart.AddSeconds(1); Name="child" },
      [pscustomobject]@{ ProcessId=400; ParentProcessId=300; CreationDate=$rootStart.AddSeconds(2); Name="grandchild" }
    )
    $names = @(Get-ProcessTreeRowsFromSnapshot -Processes $snapshot -RootProcessId 100 | Select-Object -ExpandProperty Name)
    $names | Should Be @("root", "child", "grandchild")
  }

  It "reports a shared sample interval and GPU memory endpoints" {
    $process = Start-Process pwsh -ArgumentList @(
      "-NoLogo",
      "-NoProfile",
      "-Command",
      "Start-Sleep -Seconds 15"
    ) -PassThru -WindowStyle Hidden

    try {
      $result = & $scriptPath `
        -RootProcessId $process.Id `
        -CpuSampleSeconds 2 `
        -GpuSamples 2 | ConvertFrom-Json

      $result.sampleStartedAt | Should Not BeNullOrEmpty
      $result.sampleEndedAt | Should Not BeNullOrEmpty
      $result.sampleDurationSeconds | Should BeGreaterThan 1.5
      $result.sampleDurationSeconds | Should BeLessThan 3.5
      $names = @($result.PSObject.Properties.Name)
      foreach ($name in @(
        "gpuEngineAveragePercent", "gpuEnginePeakPercent",
        "dedicatedGpuStartMb", "dedicatedGpuEndMb", "dedicatedGpuPeakMb",
        "sharedGpuStartMb", "sharedGpuEndMb", "sharedGpuPeakMb"
      )) {
        ($names -contains $name) | Should Be $true
      }
    } finally {
      Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
  }

  It "keeps the established CPU and memory fields" {
    $process = Start-Process pwsh -ArgumentList @(
      "-NoLogo",
      "-NoProfile",
      "-Command",
      "Start-Sleep -Seconds 10"
    ) -PassThru -WindowStyle Hidden

    try {
      $result = & $scriptPath `
        -RootProcessId $process.Id `
        -CpuSampleSeconds 1 `
        -GpuSamples 1 | ConvertFrom-Json

      foreach ($name in @(
        "processCount", "rendererCount", "workingSetMb",
        "privateWorkingSetMb", "privateBytesMb", "cpuSingleCorePercent",
        "cpuMachinePercent", "gpuEnginePercent", "processes"
      )) {
        (@($result.PSObject.Properties.Name) -contains $name) | Should Be $true
      }
    } finally {
      Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
  }
}
