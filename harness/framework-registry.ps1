function Get-BenchmarkFrameworkDefinitions {
  $definitions = [ordered]@{}

  foreach ($definition in @(
    [pscustomobject]@{ Name = "tauri"; Directory = "tauri-probe"; Binary = "komorebi-tauri-framework-bench.exe"; PinName = "tauri"; Pin = "2.12.5"; Enabled = $true },
    [pscustomobject]@{ Name = "slint"; Directory = "slint-probe"; Binary = "komorebi-slint-framework-bench.exe"; PinName = "slint"; Pin = "1.16.1"; Enabled = $true },
    [pscustomobject]@{ Name = "zgui"; Directory = "zgui-probe"; Binary = "komorebi-zgui-framework-bench.exe"; PinName = "zgui"; Pin = "951a0ea3b113247da6dff439fccbd9097aa3187f"; Enabled = $true },
    [pscustomobject]@{ Name = "dioxus-desktop"; Directory = "dioxus-desktop-probe"; Binary = "komorebi-dioxus-desktop-framework-bench.exe"; PinName = "dioxusDesktop"; Pin = "0.7.10"; Enabled = $true },
    [pscustomobject]@{ Name = "dioxus-native"; Directory = "dioxus-native-probe"; Binary = "komorebi-dioxus-native-framework-bench.exe"; PinName = "dioxusNativeBlitz"; Pin = "fe33b778baaef5375d941c8a4f491f62cbd31d30"; Enabled = $true },
    [pscustomobject]@{ Name = "gpui-ce"; Directory = "gpui-ce-probe"; Binary = "komorebi-gpui-ce-framework-bench.exe"; PinName = "gpuiCe"; Pin = "5cac1478fea0a5f6f28ae4bc7df4b552dff8854b"; Enabled = $true },
    [pscustomobject]@{ Name = "iced"; Directory = "iced-probe"; Binary = "komorebi-iced-framework-bench.exe"; PinName = "iced"; Pin = "0.14.0"; Enabled = $true },
    [pscustomobject]@{ Name = "gpui-kit"; Directory = "gpui-kit-probe"; Binary = "komorebi-gpui-kit-framework-bench.exe"; PinName = "gpuiKit"; Pin = "0.8.1"; Enabled = $true },
    [pscustomobject]@{ Name = "kas"; Directory = "kas-probe"; Binary = "komorebi-kas-framework-bench.exe"; PinName = "kas"; Pin = "0.17.0"; Enabled = $true },
    [pscustomobject]@{ Name = "makepad"; Directory = "makepad-probe"; Binary = "komorebi-makepad-framework-bench.exe"; PinName = "makepad"; Pin = "1.0.0"; Enabled = $true },
    [pscustomobject]@{ Name = "ferroui"; Directory = "ferroui-probe"; Binary = "komorebi-ferroui-framework-bench.exe"; PinName = "ferroUi"; Pin = "0.4.0-preview.1"; Enabled = $true },
    [pscustomobject]@{ Name = "egui"; Directory = "egui-probe"; Binary = "komorebi-egui-framework-bench.exe"; PinName = "egui"; Pin = "0.37.0"; Enabled = $true }
  )) {
    [void]$definitions.Add($definition.Name, $definition)
  }

  $definitions
}

function Get-BenchmarkFrameworkDefinition {
  param([Parameter(Mandatory = $true)][string]$Name)

  $definitions = Get-BenchmarkFrameworkDefinitions
  if (-not $definitions.Contains($Name)) {
    throw "Unknown benchmark framework: $Name"
  }
  $definitions[$Name]
}
