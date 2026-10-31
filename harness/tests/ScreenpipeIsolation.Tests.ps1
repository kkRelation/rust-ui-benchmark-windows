$libraryPath = Join-Path $PSScriptRoot "..\screenpipe-isolation.ps1"
. $libraryPath

Describe "screenpipe benchmark isolation" {
  It "extracts the original launch arguments from a quoted executable path" {
    $path = "C:\Users\Fixture User\AppData\Local\screenpipe\screenpipe-app.exe"
    $arguments = Get-BenchmarkScreenpipeLaunchArguments `
      -ExecutablePath $path `
      -CommandLine ('"' + $path + '" --autostart')

    $arguments | Should Be "--autostart"
  }

  It "does not start Screenpipe when it was not initially running" {
    Mock Get-BenchmarkScreenpipeProcesses { @() }
    Mock Start-Process { throw "must not start" }

    $state = Enter-BenchmarkScreenpipeIsolation
    $restore = Exit-BenchmarkScreenpipeIsolation -State $state

    $state.wasRunning | Should Be $false
    $state.stoppedProcessCount | Should Be 0
    $restore.required | Should Be $false
    Assert-MockCalled Start-Process -Times 0 -Scope It
  }

  It "restarts the captured executable and waits for healthy status" {
    $script:queryCount = 0
    Mock Get-BenchmarkScreenpipeProcesses {
      $script:queryCount++
      if ($script:queryCount -eq 1) { @() } else { @([pscustomobject]@{ ProcessId = 42 }) }
    }
    Mock Test-BenchmarkScreenpipeHealthy { $true }
    Mock Start-Process {}

    $state = [pscustomobject]@{
      wasRunning = $true
      launches = @([pscustomobject]@{
        executablePath = "C:\screenpipe\screenpipe-app.exe"
        arguments = "--autostart"
      })
    }
    $restore = Exit-BenchmarkScreenpipeIsolation -State $state

    $restore.required | Should Be $true
    $restore.startedProcessCount | Should Be 1
    $restore.healthy | Should Be $true
    Assert-MockCalled Start-Process -Times 1 -Scope It
  }
}
