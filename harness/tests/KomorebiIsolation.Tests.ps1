$libraryPath = Join-Path $PSScriptRoot "..\komorebi-isolation.ps1"
. $libraryPath

Describe "komorebi benchmark isolation" {
  It "finds exact title rules even when identifier groups are nested" {
    $identifiers = @(
      [pscustomobject]@{ kind = "Exe"; id = "fixture.exe"; matching_strategy = "Equals" },
      @(
        [pscustomobject]@{ kind = "Class"; id = "FixtureClass"; matching_strategy = "Equals" },
        [pscustomobject]@{ kind = "Title"; id = "UI Framework Bench - Main"; matching_strategy = "Equals" }
      )
    )

    Test-KomorebiExactTitleIgnoreRule -Identifiers $identifiers -Title "UI Framework Bench - Main" | Should Be $true
    Test-KomorebiExactTitleIgnoreRule -Identifiers $identifiers -Title "UI Framework Bench - Auxiliary Canvas" | Should Be $false
  }

  It "accepts the legacy strategy emitted by the dynamic ignore-rule command" {
    $identifiers = @(
      [pscustomobject]@{
        kind = "Title"
        id = "UI Framework Bench - Auxiliary Canvas"
        matching_strategy = "Legacy"
      }
    )

    Test-KomorebiExactTitleIgnoreRule `
      -Identifiers $identifiers `
      -Title "UI Framework Bench - Auxiliary Canvas" | Should Be $true
  }

  It "does nothing when komorebi is not running" {
    Mock Test-BenchmarkKomorebiRunning { $false }
    Mock Get-BenchmarkKomorebiState { throw "must not query" }
    Mock Invoke-BenchmarkKomorebiIgnoreRule { throw "must not mutate" }

    $result = Ensure-BenchmarkWindowsIgnoredByKomorebi

    $result.active | Should Be $false
    $result.verified | Should Be $true
    Assert-MockCalled Get-BenchmarkKomorebiState -Times 0 -Scope It
    Assert-MockCalled Invoke-BenchmarkKomorebiIgnoreRule -Times 0 -Scope It
  }

  It "adds only missing exact title rules and verifies the final state" {
    $script:stateQuery = 0
    Mock Test-BenchmarkKomorebiRunning { $true }
    Mock Get-BenchmarkKomorebiState {
      $script:stateQuery++
      $rules = if ($script:stateQuery -eq 1) {
        @([pscustomobject]@{ kind = "Title"; id = "UI Framework Bench - Main"; matching_strategy = "Equals" })
      } else {
        @(
          [pscustomobject]@{ kind = "Title"; id = "UI Framework Bench - Main"; matching_strategy = "Equals" },
          [pscustomobject]@{ kind = "Title"; id = "UI Framework Bench - Auxiliary Canvas"; matching_strategy = "Equals" }
        )
      }
      [pscustomobject]@{ ignore_identifiers = $rules }
    }
    Mock Invoke-BenchmarkKomorebiIgnoreRule {}

    $result = Ensure-BenchmarkWindowsIgnoredByKomorebi

    $result.active | Should Be $true
    $result.verified | Should Be $true
    $result.addedRules | Should Be @("UI Framework Bench - Auxiliary Canvas")
    Assert-MockCalled Invoke-BenchmarkKomorebiIgnoreRule -Times 1 -Scope It -ParameterFilter {
      $Title -eq "UI Framework Bench - Auxiliary Canvas"
    }
  }

  It "throws when the rules cannot be verified after addition" {
    Mock Test-BenchmarkKomorebiRunning { $true }
    Mock Get-BenchmarkKomorebiState { [pscustomobject]@{ ignore_identifiers = @() } }
    Mock Invoke-BenchmarkKomorebiIgnoreRule {}

    $threw = $false
    try { $null = Ensure-BenchmarkWindowsIgnoredByKomorebi } catch { $threw = $true }
    $threw | Should Be $true
  }
}
