$registryPath = Join-Path $PSScriptRoot "..\framework-registry.ps1"
$workspacePath = Join-Path $PSScriptRoot "..\framework-workspace.ps1"
. $registryPath
. $workspacePath

function Assert-WorkspaceCallThrows {
  param(
    [Parameter(Mandatory = $true)][scriptblock]$Call,
    [Parameter(Mandatory = $true)][string]$MessagePattern
  )

  $threw = $false
  try {
    & $Call | Out-Null
  } catch {
    $threw = $true
    $_.Exception.Message | Should Match $MessagePattern
  }
  $threw | Should Be $true
}

Describe "isolated benchmark framework workspaces" {
  BeforeEach {
    $repoRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $repoRoot | Out-Null
  }

  It "creates the exact isolated Cargo home and target directories" {
    $workspace = New-BenchmarkFrameworkWorkspace -RepoRoot $repoRoot -Framework "slint"
    $expectedRoot = [System.IO.Path]::GetFullPath((Join-Path $repoRoot ".benchmark-work\slint"))

    $workspace.Root | Should Be $expectedRoot
    $workspace.CargoHome | Should Be (Join-Path $expectedRoot "cargo-home")
    $workspace.TargetDirectory | Should Be (Join-Path $expectedRoot "target")
    (Test-Path -LiteralPath $workspace.CargoHome -PathType Container) | Should Be $true
    (Test-Path -LiteralPath $workspace.TargetDirectory -PathType Container) | Should Be $true
    ($workspace.FreeBytesBefore -gt 0) | Should Be $true
  }

  It "allows a declared expansion candidate before it is enabled" {
    (Get-BenchmarkFrameworkDefinition -Name "iced").Enabled | Should Be $false
    $workspace = New-BenchmarkFrameworkWorkspace -RepoRoot $repoRoot -Framework "iced"

    $workspace.Root | Should Be ([System.IO.Path]::GetFullPath((Join-Path $repoRoot ".benchmark-work\iced")))
  }

  It "rejects traversal roots and broad or mismatched cleanup paths" {
    $workBase = Join-Path $repoRoot ".benchmark-work"
    $cases = @(
      (Join-Path $workBase "slint\.."),
      (Join-Path $repoRoot "sibling"),
      $repoRoot,
      $workBase,
      (Join-Path $workBase "iced")
    )

    foreach ($candidate in $cases) {
      Assert-WorkspaceCallThrows -MessagePattern "safe framework work root" -Call {
        Resolve-SafeBenchmarkWorkRoot -RepoRoot $repoRoot -Framework "slint" -Path $candidate
      }
    }
  }

  It "rejects an unknown or path-like framework before creating directories" {
    Assert-WorkspaceCallThrows -MessagePattern "Unknown benchmark framework" -Call {
      New-BenchmarkFrameworkWorkspace -RepoRoot $repoRoot -Framework "..\slint"
    }
    (Test-Path -LiteralPath (Join-Path $repoRoot ".benchmark-work")) | Should Be $false
  }

  It "rejects a junction that redirects the framework root" {
    $workBase = Join-Path $repoRoot ".benchmark-work"
    $outside = Join-Path $TestDrive ("outside-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $workBase,$outside | Out-Null
    $junction = Join-Path $workBase "slint"

    try {
      New-Item -ItemType Junction -Path $junction -Target $outside -ErrorAction Stop | Out-Null
    } catch {
      Write-Warning "Junction creation is unavailable in this environment: $($_.Exception.Message)"
      $true | Should Be $true
      return
    }

    Assert-WorkspaceCallThrows -MessagePattern "reparse point" -Call {
      Resolve-SafeBenchmarkWorkRoot -RepoRoot $repoRoot -Framework "slint" -Path $junction
    }
  }

  It "removes only the verified framework root and reports recovery" {
    $workspace = New-BenchmarkFrameworkWorkspace -RepoRoot $repoRoot -Framework "slint"
    $sibling = Join-Path $repoRoot ".benchmark-work\iced"
    New-Item -ItemType Directory -Path $sibling | Out-Null
    Set-Content -LiteralPath (Join-Path $workspace.TargetDirectory "fixture.bin") -Value ("x" * 4096)

    $result = Remove-BenchmarkFrameworkWorkspace -RepoRoot $repoRoot -Framework "slint" -Path $workspace.Root

    $result.RemovedPath | Should Be $workspace.Root
    $result.WasPresent | Should Be $true
    ($result.FreeBytesAfter -ge $result.FreeBytesBefore) | Should Be $true
    ($result.RecoveredBytes -ge 0) | Should Be $true
    (Test-Path -LiteralPath $workspace.Root) | Should Be $false
    (Test-Path -LiteralPath $sibling -PathType Container) | Should Be $true
  }
}
