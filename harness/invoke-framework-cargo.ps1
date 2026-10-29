param(
  [Parameter(Mandatory = $true)][string]$Framework,
  [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string[]]$CargoArguments
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
. (Join-Path $PSScriptRoot "framework-registry.ps1")
. (Join-Path $PSScriptRoot "framework-workspace.ps1")

$workspace = New-BenchmarkFrameworkWorkspace -RepoRoot $repoRoot -Framework $Framework
$cargo = (Get-Command cargo -CommandType Application -ErrorAction Stop).Source
$startInfo = [System.Diagnostics.ProcessStartInfo]::new()
$startInfo.FileName = $cargo
$startInfo.WorkingDirectory = $repoRoot
$startInfo.UseShellExecute = $false
$startInfo.Environment["CARGO_HOME"] = $workspace.CargoHome
$startInfo.Environment["CARGO_TARGET_DIR"] = $workspace.TargetDirectory
foreach ($argument in $CargoArguments) {
  [void]$startInfo.ArgumentList.Add($argument)
}

Write-Host "Cargo workspace: $($workspace.Root)"
$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $startInfo
if (-not $process.Start()) {
  throw "Failed to start Cargo for $Framework"
}
$process.WaitForExit()
if ($process.ExitCode -ne 0) {
  throw "Cargo failed for $Framework with exit code $($process.ExitCode)"
}
