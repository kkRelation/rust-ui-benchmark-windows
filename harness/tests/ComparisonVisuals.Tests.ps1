$generator = Join-Path $PSScriptRoot "..\generate-comparison-visuals.ps1"

Describe "comparison visual generation" {
  It "generates deterministic rankings and thirteen independent valid SVG radars" {
    $output = Join-Path $TestDrive "comparison"
    $result = & $generator -OutputDirectory $output

    $result.FrameworkCount | Should Be 13
    $result.RadarCount | Should Be 13
    Test-Path -LiteralPath (Join-Path $output "ranking-heatmap.svg") | Should Be $true
    Test-Path -LiteralPath (Join-Path $output "overall-ranking.svg") | Should Be $true

    $svgFiles = @(Get-ChildItem -LiteralPath $output -Filter "*.svg" -Recurse)
    $svgFiles.Count | Should Be 15
    foreach ($file in $svgFiles) {
      { [xml](Get-Content -LiteralPath $file.FullName -Raw -Encoding utf8) } | Should Not Throw
    }

    $data = Get-Content -LiteralPath (Join-Path $output "comparison-data.json") -Raw -Encoding utf8 |
      ConvertFrom-Json
    $data.frameworks.Count | Should Be 13
    $data.methodology.radarAreaUsedForRanking | Should Be $false
    $data.methodology.hardwareBaseline.systemRamGiB | Should Be 32
    $data.methodology.hardwareBaseline.dedicatedVramGiB | Should Be 8

    $leader = @($data.frameworks | Sort-Object overallRank)[0]
    $leader.name | Should Be "tauri"
    $leader.overallRank | Should Be 1
    $gpuiFast = @($data.frameworks | Where-Object name -eq "gpui-fast")[0]
    $gpuiFast.overallRank | Should Be 3.5
    $gpuiFast.axisRanks.ram | Should Be 2
  }
}
