$scriptPath = Join-Path $PSScriptRoot "..\ferroui-preflight.ps1"
. $scriptPath -WorkRoot ".benchmark-work\ferroui" -MinimumFreeBytes 1

Describe "FerroUI read-only prerequisite preflight" {
  BeforeEach {
    Mock Get-FerroUiFreeBytes { 200 }
    Mock Find-FerroUiMsvc { "C:\BuildTools\VC\bin\cl.exe" }
    Mock Find-FerroUiLibClang { "C:\LLVM\bin\libclang.dll" }
  }

  It "fails with a specific reason when free space is insufficient" {
    Mock Get-FerroUiFreeBytes { 99 }

    $result = Invoke-FerroUiPreflight -WorkRoot ".benchmark-work\ferroui" -MinimumFreeBytes 100

    $result.passed | Should Be $false
    (@($result.reasons) -contains "insufficient-free-space") | Should Be $true
  }

  It "fails with a specific reason when the x64 MSVC compiler is missing" {
    Mock Find-FerroUiMsvc { $null }

    $result = Invoke-FerroUiPreflight -WorkRoot ".benchmark-work\ferroui" -MinimumFreeBytes 100

    $result.passed | Should Be $false
    (@($result.reasons) -contains "missing-msvc-x64") | Should Be $true
  }

  It "fails with a specific reason when libclang is missing" {
    Mock Find-FerroUiLibClang { $null }

    $result = Invoke-FerroUiPreflight -WorkRoot ".benchmark-work\ferroui" -MinimumFreeBytes 100

    $result.passed | Should Be $false
    (@($result.reasons) -contains "missing-libclang") | Should Be $true
  }

  It "passes a complete fixture without changing prerequisite environment variables" {
    $libclangBefore = $env:LIBCLANG_PATH
    $vcToolsBefore = $env:VCToolsInstallDir

    $result = Invoke-FerroUiPreflight -WorkRoot ".benchmark-work\ferroui" -MinimumFreeBytes 100

    $result.passed | Should Be $true
    $result.reasons.Count | Should Be 0
    $result.msvc.found | Should Be $true
    $result.libclang.found | Should Be $true
    $env:LIBCLANG_PATH | Should Be $libclangBefore
    $env:VCToolsInstallDir | Should Be $vcToolsBefore
  }
}
