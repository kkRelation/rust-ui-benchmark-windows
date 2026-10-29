$libraryPath = Join-Path $PSScriptRoot "..\framework-registry.ps1"
. $libraryPath

Describe "benchmark framework registry" {
  It "keeps implemented frameworks enabled in cohort order" {
    $definitions = Get-BenchmarkFrameworkDefinitions
    $definitions.GetType().FullName | Should Be "System.Collections.Specialized.OrderedDictionary"
    $enabled = @($definitions.Values | Where-Object Enabled | ForEach-Object Name)

    $enabled | Should Be @(
      "tauri", "slint", "zgui", "dioxus-desktop", "dioxus-native", "gpui-ce", "iced", "gpui-kit", "kas", "makepad"
    )
  }

  It "predeclares the approved expansion candidates as disabled" {
    $definitions = Get-BenchmarkFrameworkDefinitions
    $disabled = @($definitions.Values | Where-Object { -not $_.Enabled } | ForEach-Object Name)

    $disabled | Should Be @("ferroui")
  }

  It "resolves the exact Iced build definition and pin" {
    $definition = Get-BenchmarkFrameworkDefinition -Name "iced"

    $definition.Name | Should Be "iced"
    $definition.Directory | Should Be "iced-probe"
    $definition.Binary | Should Be "komorebi-iced-framework-bench.exe"
    $definition.PinName | Should Be "iced"
    $definition.Pin | Should Be "0.14.0"
    $definition.Enabled | Should Be $true
  }

  It "resolves gpui-kit separately from gpui-ce" {
    $definition = Get-BenchmarkFrameworkDefinition -Name "gpui-kit"
    $gpuiCe = Get-BenchmarkFrameworkDefinition -Name "gpui-ce"

    $definition.Name | Should Be "gpui-kit"
    $definition.Directory | Should Be "gpui-kit-probe"
    $definition.Binary | Should Be "komorebi-gpui-kit-framework-bench.exe"
    $definition.PinName | Should Be "gpuiKit"
    $definition.Pin | Should Be "0.8.1"
    $definition.Enabled | Should Be $true
    $gpuiCe.PinName | Should Be "gpuiCe"
    $gpuiCe.Pin | Should Be "5cac1478fea0a5f6f28ae4bc7df4b552dff8854b"
  }

  It "resolves the exact KAS WGPU build definition and pin" {
    $definition = Get-BenchmarkFrameworkDefinition -Name "kas"

    $definition.Name | Should Be "kas"
    $definition.Directory | Should Be "kas-probe"
    $definition.Binary | Should Be "komorebi-kas-framework-bench.exe"
    $definition.PinName | Should Be "kas"
    $definition.Pin | Should Be "0.17.0"
    $definition.Enabled | Should Be $true
  }

  It "resolves the exact Makepad native build definition and pin" {
    $definition = Get-BenchmarkFrameworkDefinition -Name "makepad"

    $definition.Name | Should Be "makepad"
    $definition.Directory | Should Be "makepad-probe"
    $definition.Binary | Should Be "komorebi-makepad-framework-bench.exe"
    $definition.PinName | Should Be "makepad"
    $definition.Pin | Should Be "1.0.0"
    $definition.Enabled | Should Be $true
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
