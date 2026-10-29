param(
  [ValidateSet("tauri", "slint", "zgui", "dioxus-desktop", "dioxus-native", "gpui-ce")]
  [string[]]$Framework = @("tauri", "slint", "zgui", "dioxus-desktop", "dioxus-native", "gpui-ce"),
  [ValidateSet("debug", "release")]
  [string]$Configuration = "release"
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$probeDirectories = [ordered]@{
  "tauri" = "tauri-probe"
  "slint" = "slint-probe"
  "zgui" = "zgui-probe"
  "dioxus-desktop" = "dioxus-desktop-probe"
  "dioxus-native" = "dioxus-native-probe"
  "gpui-ce" = "gpui-ce-probe"
}

foreach ($frameworkName in $Framework) {
  $manifestPath = Join-Path $repoRoot "probes\$($probeDirectories[$frameworkName])\Cargo.toml"
  $arguments = @("build", "--locked", "--manifest-path", $manifestPath)
  if ($Configuration -eq "release") { $arguments += "--release" }

  Write-Host "Building $frameworkName ($Configuration)"
  & cargo @arguments
  if ($LASTEXITCODE -ne 0) {
    throw "cargo build failed for $frameworkName with exit code $LASTEXITCODE"
  }
}

