$libraryPath = Join-Path $PSScriptRoot "..\framework-registry.ps1"
. $libraryPath

Describe "benchmark framework registry" {
  It "keeps the historical six enabled in their published order" {
    $definitions = Get-BenchmarkFrameworkDefinitions
    $definitions.GetType().FullName | Should Be "System.Collections.Specialized.OrderedDictionary"
    $enabled = @($definitions.Values | Where-Object Enabled | ForEach-Object Name)

    $enabled | Should Be @(
      "tauri", "slint", "zgui", "dioxus-desktop", "dioxus-native", "gpui-ce"
    )
  }

  It "predeclares the approved expansion candidates as disabled" {
    $definitions = Get-BenchmarkFrameworkDefinitions
    $disabled = @($definitions.Values | Where-Object { -not $_.Enabled } | ForEach-Object Name)

    $disabled | Should Be @("iced", "gpui-kit", "kas", "makepad", "ferroui")
  }

  It "resolves the exact Slint build definition and pin" {
    $definition = Get-BenchmarkFrameworkDefinition -Name "slint"

    $definition.Name | Should Be "slint"
    $definition.Directory | Should Be "slint-probe"
    $definition.Binary | Should Be "komorebi-slint-framework-bench.exe"
    $definition.PinName | Should Be "slint"
    $definition.Pin | Should Be "1.16.1"
    $definition.Enabled | Should Be $true
  }

  It "rejects an unknown framework name" {
    $threw = $false
    try {
      Get-BenchmarkFrameworkDefinition -Name "../unknown" | Out-Null
    } catch {
      $threw = $true
      $_.Exception.Message | Should Match "Unknown benchmark framework"
    }
    $threw | Should Be $true
  }
}
