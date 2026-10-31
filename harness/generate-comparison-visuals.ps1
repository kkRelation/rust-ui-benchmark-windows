param(
  [string]$OutputDirectory,
  [ValidateRange(1, 1024)][double]$SystemRamGiB = 32,
  [ValidateRange(1, 128)][double]$DedicatedVramGiB = 8,
  [hashtable]$Weights = @{
    Ram = 1
    Cpu = 1
    Gpu = 1
    Vram = 1
    SharedGpu = 1
    Show = 1
    Hide = 1
  }
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
  $OutputDirectory = Join-Path $repoRoot "docs\assets\comparison"
} elseif (-not [System.IO.Path]::IsPathRooted($OutputDirectory)) {
  $OutputDirectory = Join-Path $repoRoot $OutputDirectory
}
$outputRoot = [System.IO.Path]::GetFullPath($OutputDirectory)
$radarRoot = Join-Path $outputRoot "radar"
[System.IO.Directory]::CreateDirectory($radarRoot) | Out-Null

$definitions = @(
  [pscustomobject]@{ Name = "tauri"; Display = "Tauri / WebView2"; File = "results\2026-10-29\tauri-unmanaged.json" },
  [pscustomobject]@{ Name = "slint"; Display = "Slint"; File = "results\2026-10-29\slint-anchor-unmanaged-attempt-2.json" },
  [pscustomobject]@{ Name = "zgui"; Display = "zgui"; File = "results\2026-10-29\zgui-unmanaged.json" },
  [pscustomobject]@{ Name = "dioxus-desktop"; Display = "Dioxus Desktop / WebView2"; File = "results\2026-10-29\dioxus-desktop-unmanaged.json" },
  [pscustomobject]@{ Name = "dioxus-native"; Display = "Dioxus Native / Blitz"; File = "results\2026-10-29\dioxus-native-unmanaged.json" },
  [pscustomobject]@{ Name = "gpui-ce"; Display = "gpui-ce"; File = "results\2026-10-29\gpui-ce-unmanaged.json" },
  [pscustomobject]@{ Name = "iced"; Display = "Iced"; File = "results\2026-10-29\iced-unmanaged-attempt-3.json" },
  [pscustomobject]@{ Name = "gpui-kit"; Display = "gpui-kit"; File = "results\2026-10-29\gpui-kit-unmanaged-attempt-2.json" },
  [pscustomobject]@{ Name = "kas"; Display = "KAS"; File = "results\2026-10-29\kas-unmanaged-attempt-2.json" },
  [pscustomobject]@{ Name = "makepad"; Display = "Makepad"; File = "results\2026-10-29\makepad.json" },
  [pscustomobject]@{ Name = "ferroui"; Display = "FerroUI"; File = "results\2026-10-29\ferroui.json" },
  [pscustomobject]@{ Name = "egui"; Display = "egui"; File = "results\2026-10-29\egui.json" },
  [pscustomobject]@{ Name = "gpui-fast"; Display = "gpui-fast"; File = "results\2026-10-31\gpui-fast.json" }
)

function Get-PhaseMetrics {
  param([object]$Result, [string]$Phase)
  $entry = @($Result.summary.phases | Where-Object phase -eq $Phase)
  if ($entry.Count -ne 1) { throw "Expected one '$Phase' summary entry; found $($entry.Count)." }
  $entry[0].metrics
}

function Set-Property {
  param([object]$Object, [string]$Name, [object]$Value)
  $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Add-LowerBetterRanking {
  param([object[]]$Rows, [string]$ValueProperty, [string]$RankProperty, [string]$ScoreProperty)
  $sorted = @($Rows | Sort-Object { [double]$_.$ValueProperty }, Name)
  $count = $sorted.Count
  $index = 0
  while ($index -lt $count) {
    $end = $index
    $value = [double]$sorted[$index].$ValueProperty
    while ($end + 1 -lt $count -and [double]$sorted[$end + 1].$ValueProperty -eq $value) { $end++ }
    $rank = (($index + 1) + ($end + 1)) / 2.0
    $score = if ($count -eq 1) { 100.0 } else { 100.0 * ($count - $rank) / ($count - 1) }
    for ($cursor = $index; $cursor -le $end; $cursor++) {
      Set-Property $sorted[$cursor] $RankProperty ([math]::Round($rank, 3))
      Set-Property $sorted[$cursor] $ScoreProperty ([math]::Round($score, 3))
    }
    $index = $end + 1
  }
}

function Add-HigherBetterRanking {
  param([object[]]$Rows, [string]$ValueProperty, [string]$RankProperty)
  $sorted = @($Rows | Sort-Object @{ Expression = { [double]$_.$ValueProperty }; Descending = $true }, Name)
  $index = 0
  while ($index -lt $sorted.Count) {
    $end = $index
    $value = [double]$sorted[$index].$ValueProperty
    while ($end + 1 -lt $sorted.Count -and [double]$sorted[$end + 1].$ValueProperty -eq $value) { $end++ }
    $rank = (($index + 1) + ($end + 1)) / 2.0
    for ($cursor = $index; $cursor -le $end; $cursor++) {
      Set-Property $sorted[$cursor] $RankProperty ([math]::Round($rank, 3))
    }
    $index = $end + 1
  }
}

function Escape-Xml([string]$Value) {
  [System.Security.SecurityElement]::Escape($Value)
}

function Format-Number([double]$Value, [string]$Format = "0.###") {
  $Value.ToString($Format, [System.Globalization.CultureInfo]::InvariantCulture)
}

function Write-Utf8File([string]$Path, [string]$Content) {
  [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

$rows = @(
  foreach ($definition in $definitions) {
    $path = Join-Path $repoRoot $definition.File
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing comparison result: $path" }
    $result = Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json
    $hidden = Get-PhaseMetrics $result "hiddenIdle"
    $workload = Get-PhaseMetrics $result "workload400"
    $latency = @($result.summary.latency)
    if ($latency.Count -ne 1) { throw "Expected one latency summary in $path." }
    [pscustomobject]@{
      Name = $definition.Name
      Display = $definition.Display
      Source = $definition.File.Replace('\', '/')
      HiddenPwsMb = [double]$hidden.privateWorkingSetMb.median
      WorkloadPwsMb = [double]$workload.privateWorkingSetMb.median
      CpuPercent = [double]$workload.cpuMachinePercent.median
      GpuPercent = [double]$workload.gpuEngineAveragePercent.median
      DedicatedVramMb = [double]$workload.dedicatedGpuPeakMb.median
      SharedGpuMb = [double]$workload.sharedGpuPeakMb.median
      ShowMs = [double]$latency[0].showLatencyMs.median
      HideMs = [double]$latency[0].hideLatencyMs.median
    }
  }
)

foreach ($metric in @(
  @("HiddenPwsMb", "HiddenPwsRank", "HiddenPwsScore"),
  @("WorkloadPwsMb", "WorkloadPwsRank", "WorkloadPwsScore"),
  @("CpuPercent", "CpuRank", "CpuScore"),
  @("GpuPercent", "GpuRank", "GpuScore"),
  @("DedicatedVramMb", "VramRank", "VramScore"),
  @("SharedGpuMb", "SharedGpuRank", "SharedGpuScore"),
  @("ShowMs", "ShowRank", "ShowScore"),
  @("HideMs", "HideRank", "HideScore")
)) {
  Add-LowerBetterRanking $rows $metric[0] $metric[1] $metric[2]
}

$requiredWeights = @("Ram", "Cpu", "Gpu", "Vram", "SharedGpu", "Show", "Hide")
foreach ($key in $requiredWeights) {
  if (-not $Weights.ContainsKey($key) -or [double]$Weights[$key] -le 0) {
    throw "Weight '$key' must be present and greater than zero."
  }
}
$weightTotal = ($requiredWeights | ForEach-Object { [double]$Weights[$_] } | Measure-Object -Sum).Sum

foreach ($row in $rows) {
  $ramScore = ([double]$row.HiddenPwsScore + [double]$row.WorkloadPwsScore) / 2.0
  Set-Property $row "RamScore" ([math]::Round($ramScore, 3))
  $axisScores = @($ramScore, $row.CpuScore, $row.GpuScore, $row.VramScore, $row.SharedGpuScore, $row.ShowScore, $row.HideScore)
  $overall = (
    $ramScore * [double]$Weights.Ram +
    [double]$row.CpuScore * [double]$Weights.Cpu +
    [double]$row.GpuScore * [double]$Weights.Gpu +
    [double]$row.VramScore * [double]$Weights.Vram +
    [double]$row.SharedGpuScore * [double]$Weights.SharedGpu +
    [double]$row.ShowScore * [double]$Weights.Show +
    [double]$row.HideScore * [double]$Weights.Hide
  ) / $weightTotal
  Set-Property $row "OverallScore" ([math]::Round($overall, 3))
  Set-Property $row "FloorScore" ([math]::Round(($axisScores | Measure-Object -Minimum).Minimum, 3))
  Set-Property $row "SystemRamCostPercent" ([math]::Round(100.0 * $row.WorkloadPwsMb / ($SystemRamGiB * 1024.0), 4))
  Set-Property $row "DedicatedVramCostPercent" ([math]::Round(100.0 * $row.DedicatedVramMb / ($DedicatedVramGiB * 1024.0), 4))
}
Add-HigherBetterRanking $rows "RamScore" "RamRank"
Add-HigherBetterRanking $rows "OverallScore" "OverallRank"

$axisDefinitions = @(
  [pscustomobject]@{ Key = "Ram"; Label = "RAM"; Score = "RamScore"; Rank = "RamRank" },
  [pscustomobject]@{ Key = "Cpu"; Label = "CPU"; Score = "CpuScore"; Rank = "CpuRank" },
  [pscustomobject]@{ Key = "Gpu"; Label = "GPU activity"; Score = "GpuScore"; Rank = "GpuRank" },
  [pscustomobject]@{ Key = "Vram"; Label = "Dedicated VRAM"; Score = "VramScore"; Rank = "VramRank" },
  [pscustomobject]@{ Key = "SharedGpu"; Label = "Shared GPU RAM"; Score = "SharedGpuScore"; Rank = "SharedGpuRank" },
  [pscustomobject]@{ Key = "Show"; Label = "Warm show"; Score = "ShowScore"; Rank = "ShowRank" },
  [pscustomobject]@{ Key = "Hide"; Label = "Warm hide"; Score = "HideScore"; Rank = "HideRank" }
)

function Get-HeatColor([double]$Score) {
  $ratio = $Score / 100.0
  $red = [int][math]::Round(19 + (31 - 19) * $ratio)
  $green = [int][math]::Round(36 + (111 - 36) * $ratio)
  $blue = [int][math]::Round(58 + (235 - 58) * $ratio)
  "#{0:X2}{1:X2}{2:X2}" -f $red, $green, $blue
}

function New-RankingHeatmap([object[]]$Data) {
  $ordered = @($Data | Sort-Object OverallRank, Display)
  $width = 1700
  $left = 330
  $top = 150
  $rowHeight = 44
  $columnWidth = 165
  $height = $top + $ordered.Count * $rowHeight + 74
  $builder = [System.Text.StringBuilder]::new()
  [void]$builder.AppendLine("<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"$width`" height=`"$height`" viewBox=`"0 0 $width $height`" role=`"img`" aria-labelledby=`"title desc`">")
  [void]$builder.AppendLine("<title id=`"title`">Per-dimension rankings for thirteen Rust UI frameworks</title><desc id=`"desc`">Lower resource use and latency rank higher. Overall is the equal-weight mean of seven percentile rank scores.</desc>")
  [void]$builder.AppendLine('<style>text{font-family:"Segoe UI",Arial,sans-serif;fill:#e6edf3}.title{font-size:25px;font-weight:700}.sub{font-size:14px;fill:#9da7b3}.head{font-size:13px;font-weight:700}.name{font-size:14px;font-weight:600}.cell{font-size:13px;font-weight:700}.rank{font-size:12px;fill:#c9d1d9}.grid{stroke:#30363d;stroke-width:1}</style>')
  [void]$builder.AppendLine("<rect width=`"$width`" height=`"$height`" rx=`"14`" fill=`"#0d1117`"/>")
  [void]$builder.AppendLine('<text class="title" x="28" y="40">Per-Dimension Ranking Heatmap</text>')
  [void]$builder.AppendLine('<text class="sub" x="28" y="67">#1 is best · ties use average rank · cell brightness follows the 0–100 percentile rank score</text>')
  [void]$builder.AppendLine('<text class="sub" x="28" y="91">RAM combines hidden and workload PWS; Overall equally weights RAM, CPU, GPU activity, dedicated VRAM, shared GPU RAM, show and hide.</text>')
  $headers = @("Framework", "RAM", "CPU", "GPU activity", "Dedicated VRAM", "Shared GPU RAM", "Warm show", "Warm hide", "Overall")
  [void]$builder.AppendLine("<rect x=`"24`" y=`"112`" width=`"1652`" height=`"$($height - 146)`" rx=`"8`" fill=`"#0b1016`" stroke=`"#30363d`"/>")
  [void]$builder.AppendLine("<rect x=`"24`" y=`"112`" width=`"1652`" height=`"38`" rx=`"8`" fill=`"#161b22`"/>")
  [void]$builder.AppendLine("<text class=`"head`" x=`"44`" y=`"137`">Framework</text>")
  for ($column = 1; $column -lt $headers.Count; $column++) {
    $x = $left + ($column - 1) * $columnWidth + $columnWidth / 2
    [void]$builder.AppendLine("<text class=`"head`" x=`"$x`" y=`"137`" text-anchor=`"middle`">$(Escape-Xml $headers[$column])</text>")
  }
  for ($index = 0; $index -lt $ordered.Count; $index++) {
    $row = $ordered[$index]
    $y = $top + $index * $rowHeight
    if ($row.Name -eq "gpui-fast") { [void]$builder.AppendLine("<rect x=`"24`" y=`"$y`" width=`"1652`" height=`"$rowHeight`" fill=`"#102a43`"/>") }
    [void]$builder.AppendLine("<text class=`"name`" x=`"44`" y=`"$($y + 28)`">$(Escape-Xml $row.Display)</text>")
    $cells = @(
      @($row.RamRank, $row.RamScore), @($row.CpuRank, $row.CpuScore),
      @($row.GpuRank, $row.GpuScore), @($row.VramRank, $row.VramScore),
      @($row.SharedGpuRank, $row.SharedGpuScore),
      @($row.ShowRank, $row.ShowScore), @($row.HideRank, $row.HideScore),
      @($row.OverallRank, $row.OverallScore)
    )
    for ($column = 0; $column -lt $cells.Count; $column++) {
      $x = $left + $column * $columnWidth
      $color = Get-HeatColor ([double]$cells[$column][1])
      [void]$builder.AppendLine("<rect x=`"$($x + 5)`" y=`"$($y + 5)`" width=`"$($columnWidth - 10)`" height=`"$($rowHeight - 10)`" rx=`"5`" fill=`"$color`"/>")
      [void]$builder.AppendLine("<text class=`"cell`" x=`"$($x + $columnWidth / 2)`" y=`"$($y + 27)`" text-anchor=`"middle`">#$(Format-Number $cells[$column][0] '0.#') · $(Format-Number $cells[$column][1] '0.0')</text>")
    }
  }
  [void]$builder.AppendLine("<text class=`"sub`" x=`"28`" y=`"$($height - 22)`">Scores are cohort-relative, not universal performance grades. Hardware-capacity percentages are shown on the individual radar cards.</text>")
  [void]$builder.AppendLine('</svg>')
  $builder.ToString()
}

function New-OverallRanking([object[]]$Data) {
  $ordered = @($Data | Sort-Object OverallRank, Display)
  $width = 1100
  $top = 126
  $rowHeight = 40
  $height = $top + $ordered.Count * $rowHeight + 72
  $barX = 340
  $barWidth = 600
  $builder = [System.Text.StringBuilder]::new()
  [void]$builder.AppendLine("<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"$width`" height=`"$height`" viewBox=`"0 0 $width $height`" role=`"img`" aria-labelledby=`"title desc`">")
  [void]$builder.AppendLine('<title id="title">Equal-weight composite ranking</title><desc id="desc">The arithmetic mean of seven cohort-relative percentile rank scores.</desc>')
  [void]$builder.AppendLine('<style>text{font-family:"Segoe UI",Arial,sans-serif;fill:#e6edf3}.title{font-size:25px;font-weight:700}.sub{font-size:14px;fill:#9da7b3}.name{font-size:14px;font-weight:600}.score{font-size:13px;font-weight:700}.floor{font-size:12px;fill:#9da7b3}</style>')
  [void]$builder.AppendLine("<rect width=`"$width`" height=`"$height`" rx=`"14`" fill=`"#0d1117`"/>")
  [void]$builder.AppendLine('<text class="title" x="28" y="40">Equal-Weight Composite Ranking</text>')
  [void]$builder.AppendLine('<text class="sub" x="28" y="67">Mean of RAM, CPU, GPU activity, dedicated VRAM, shared GPU RAM, warm show and warm hide rank scores.</text>')
  [void]$builder.AppendLine('<text class="sub" x="28" y="91">The weakness floor is the lowest of the seven axis scores; radar polygon area is intentionally not used for ranking.</text>')
  for ($index = 0; $index -lt $ordered.Count; $index++) {
    $row = $ordered[$index]
    $y = $top + $index * $rowHeight
    $fill = if ($index -eq 0) { "#2ea043" } elseif ($row.Name -eq "gpui-fast") { "#58a6ff" } else { "#1f6feb" }
    $actualWidth = $barWidth * $row.OverallScore / 100.0
    [void]$builder.AppendLine("<text class=`"name`" x=`"28`" y=`"$($y + 23)`">#$(Format-Number $row.OverallRank '0.#')  $(Escape-Xml $row.Display)</text>")
    [void]$builder.AppendLine("<rect x=`"$barX`" y=`"$($y + 5)`" width=`"$barWidth`" height=`"24`" rx=`"6`" fill=`"#161b22`"/>")
    [void]$builder.AppendLine("<rect x=`"$barX`" y=`"$($y + 5)`" width=`"$(Format-Number $actualWidth '0.0')`" height=`"24`" rx=`"6`" fill=`"$fill`"/>")
    [void]$builder.AppendLine("<text class=`"score`" x=`"$($barX + $barWidth + 16)`" y=`"$($y + 23)`">$(Format-Number $row.OverallScore '0.0')</text>")
    [void]$builder.AppendLine("<text class=`"floor`" x=`"$($barX + $barWidth + 72)`" y=`"$($y + 23)`">floor $(Format-Number $row.FloorScore '0.0')</text>")
  }
  [void]$builder.AppendLine("<text class=`"sub`" x=`"28`" y=`"$($height - 22)`">Change the Weights parameter in generate-comparison-visuals.ps1 for a workload-specific ranking.</text>")
  [void]$builder.AppendLine('</svg>')
  $builder.ToString()
}

function Get-PolarPoint([double]$CenterX, [double]$CenterY, [double]$Radius, [int]$Index, [int]$Count) {
  $angle = -[math]::PI / 2 + 2 * [math]::PI * $Index / $Count
  [pscustomobject]@{ X = $CenterX + $Radius * [math]::Cos($angle); Y = $CenterY + $Radius * [math]::Sin($angle) }
}

function Get-PointString([object[]]$Points) {
  ($Points | ForEach-Object { "$(Format-Number $_.X '0.0'),$(Format-Number $_.Y '0.0')" }) -join " "
}

function New-RadarCard([object]$Row) {
  $width = 650
  $height = 575
  $centerX = 325.0
  $centerY = 300.0
  $radius = 150.0
  $labelRadius = 194.0
  $scores = @($Row.RamScore, $Row.CpuScore, $Row.GpuScore, $Row.VramScore, $Row.SharedGpuScore, $Row.ShowScore, $Row.HideScore)
  $labels = @("RAM", "CPU", "GPU activity", "Dedicated VRAM", "Shared GPU RAM", "Warm show", "Warm hide")
  $axisCount = $scores.Count
  $builder = [System.Text.StringBuilder]::new()
  [void]$builder.AppendLine("<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"$width`" height=`"$height`" viewBox=`"0 0 $width $height`" role=`"img`" aria-labelledby=`"title desc`">")
  [void]$builder.AppendLine("<title id=`"title`">$(Escape-Xml $Row.Display) seven-axis capability radar</title><desc id=`"desc`">Higher is better. Scores are cohort-relative percentile rank scores.</desc>")
  [void]$builder.AppendLine('<style>text{font-family:"Segoe UI",Arial,sans-serif;fill:#e6edf3}.title{font-size:24px;font-weight:700}.sub{font-size:13px;fill:#9da7b3}.axis{font-size:12px;font-weight:700}.value{font-size:11px;fill:#79c0ff}.ring{fill:none;stroke:#30363d;stroke-width:1}.spoke{stroke:#30363d;stroke-width:1}.shape{fill:#1f6feb;fill-opacity:.34;stroke:#58a6ff;stroke-width:3}.dot{fill:#79c0ff}</style>')
  [void]$builder.AppendLine("<rect width=`"$width`" height=`"$height`" rx=`"14`" fill=`"#0d1117`"/>")
  [void]$builder.AppendLine("<text class=`"title`" x=`"24`" y=`"38`">$(Escape-Xml $Row.Display)</text>")
  [void]$builder.AppendLine("<text class=`"sub`" x=`"24`" y=`"64`">Overall #$(Format-Number $Row.OverallRank '0.#') · score $(Format-Number $Row.OverallScore '0.0') · weakness floor $(Format-Number $Row.FloorScore '0.0')</text>")
  [void]$builder.AppendLine("<text class=`"sub`" x=`"24`" y=`"86`">Workload PWS $(Format-Number $Row.SystemRamCostPercent '0.000')% of $(Format-Number $SystemRamGiB '0.#') GiB RAM · dedicated VRAM $(Format-Number $Row.DedicatedVramCostPercent '0.000')% of $(Format-Number $DedicatedVramGiB '0.#') GiB · shared GPU $(Format-Number $Row.SharedGpuMb '0.0') MB</text>")
  foreach ($level in @(0.25, 0.5, 0.75, 1.0)) {
    $points = @(for ($index = 0; $index -lt $axisCount; $index++) { Get-PolarPoint $centerX $centerY ($radius * $level) $index $axisCount })
    [void]$builder.AppendLine("<polygon class=`"ring`" points=`"$(Get-PointString $points)`"/>")
  }
  for ($index = 0; $index -lt $axisCount; $index++) {
    $outer = Get-PolarPoint $centerX $centerY $radius $index $axisCount
    [void]$builder.AppendLine("<line class=`"spoke`" x1=`"$centerX`" y1=`"$centerY`" x2=`"$(Format-Number $outer.X '0.0')`" y2=`"$(Format-Number $outer.Y '0.0')`"/>")
  }
  $shapePoints = @(for ($index = 0; $index -lt $axisCount; $index++) { Get-PolarPoint $centerX $centerY ($radius * [double]$scores[$index] / 100.0) $index $axisCount })
  [void]$builder.AppendLine("<polygon class=`"shape`" points=`"$(Get-PointString $shapePoints)`"/>")
  foreach ($point in $shapePoints) { [void]$builder.AppendLine("<circle class=`"dot`" cx=`"$(Format-Number $point.X '0.0')`" cy=`"$(Format-Number $point.Y '0.0')`" r=`"4`"/>") }
  for ($index = 0; $index -lt $axisCount; $index++) {
    $position = Get-PolarPoint $centerX $centerY $labelRadius $index $axisCount
    $anchor = if ($position.X -lt $centerX - 10) { "end" } elseif ($position.X -gt $centerX + 10) { "start" } else { "middle" }
    [void]$builder.AppendLine("<text class=`"axis`" x=`"$(Format-Number $position.X '0.0')`" y=`"$(Format-Number $position.Y '0.0')`" text-anchor=`"$anchor`">$(Escape-Xml $labels[$index])</text>")
    [void]$builder.AppendLine("<text class=`"value`" x=`"$(Format-Number $position.X '0.0')`" y=`"$(Format-Number ($position.Y + 17) '0.0')`" text-anchor=`"$anchor`">#$(Format-Number $Row.($axisDefinitions[$index].Rank) '0.#') · $(Format-Number $scores[$index] '0.0')</text>")
  }
  [void]$builder.AppendLine('<text class="sub" x="325" y="547" text-anchor="middle">Higher polygon vertices are better.</text>')
  [void]$builder.AppendLine('<text class="sub" x="325" y="565" text-anchor="middle">Polygon area is descriptive only and is not the composite score.</text>')
  [void]$builder.AppendLine('</svg>')
  $builder.ToString()
}

function Get-RelativeClass([object[]]$Data, [string]$Property, [double]$Value, [double]$Baseline) {
  $minimum = [double](($Data | Measure-Object -Property $Property -Minimum).Minimum)
  if ($Value -eq $minimum) { return "best" }
  if ($Value -lt $Baseline) { return "better" }
  ""
}

function New-OverviewComparison([object[]]$Data) {
  $baseline = @($Data | Where-Object Name -eq "gpui-fast")[0]
  $width = 1740
  $height = 810
  $tableTop = 116
  $headerHeight = 58
  $rowHeight = 44
  $tableBottom = $tableTop + $headerHeight + $Data.Count * $rowHeight
  $builder = [System.Text.StringBuilder]::new()
  [void]$builder.AppendLine("<svg xmlns=`"http://www.w3.org/2000/svg`" width=`"$width`" height=`"$height`" viewBox=`"0 0 $width $height`" role=`"img`" aria-labelledby=`"title description`">")
  [void]$builder.AppendLine('<title id="title">Corrected unmanaged-window comparison of thirteen Rust UI frameworks</title>')
  [void]$builder.AppendLine('<desc id="description">Three-round median resource usage, dedicated and shared GPU memory peaks, and warm window latency. Red values are overall minima. Blue values beat gpui-fast without being the overall minimum.</desc>')
  [void]$builder.AppendLine('<style>text{font-family:"Segoe UI",Arial,sans-serif;fill:#e6edf3}.title{font-size:25px;font-weight:700}.subtitle{font-size:14px;fill:#9da7b3}.header{font-size:13px;font-weight:700;fill:#f0f6fc}.framework{font-size:14px;font-weight:600}.value{font-size:14px;font-variant-numeric:tabular-nums}.best{fill:#ff6b6b;font-weight:700}.better{fill:#58a6ff;font-weight:700}.baseline{fill:#79c0ff;font-weight:700}.grid{stroke:#30363d;stroke-width:1}</style>')
  [void]$builder.AppendLine("<rect width=`"$width`" height=`"$height`" rx=`"14`" fill=`"#0d1117`"/>")
  [void]$builder.AppendLine('<text class="title" x="28" y="40">Corrected Unmanaged-Window Comparison</text>')
  [void]$builder.AppendLine('<text class="subtitle" x="28" y="66">Lower is better · Three-round release medians · gpui-fast is the comparison baseline</text>')
  [void]$builder.AppendLine('<text class="subtitle" x="28" y="94"><tspan class="best">Red</tspan><tspan> = overall minimum (ties included)   ·   </tspan><tspan class="better">Blue</tspan><tspan> = lower than gpui-fast, but not the overall minimum</tspan></text>')
  [void]$builder.AppendLine("<rect x=`"24`" y=`"$tableTop`" width=`"1692`" height=`"$($tableBottom - $tableTop)`" rx=`"8`" fill=`"#0b1016`" stroke=`"#30363d`"/>")
  [void]$builder.AppendLine("<rect x=`"24`" y=`"$tableTop`" width=`"1692`" height=`"$headerHeight`" rx=`"8`" fill=`"#161b22`"/>")
  for ($index = 0; $index -lt $Data.Count; $index++) {
    $y = $tableTop + $headerHeight + $index * $rowHeight
    if ($Data[$index].Name -eq "gpui-fast") {
      [void]$builder.AppendLine("<rect x=`"24`" y=`"$y`" width=`"1692`" height=`"$rowHeight`" fill=`"#102a43`"/>")
    } elseif ($index % 2 -eq 1) {
      [void]$builder.AppendLine("<rect x=`"24`" y=`"$y`" width=`"1692`" height=`"$rowHeight`" fill=`"#0f141b`"/>")
    }
  }
  [void]$builder.AppendLine("<path class=`"grid`" d=`"M360 $tableTop`V$tableBottom M500 $tableTop`V$tableBottom M630 $tableTop`V$tableBottom M760 $tableTop`V$tableBottom M890 $tableTop`V$tableBottom M1050 $tableTop`V$tableBottom M1210 $tableTop`V$tableBottom`"/>")
  for ($index = 0; $index -le $Data.Count; $index++) {
    $y = $tableTop + $headerHeight + $index * $rowHeight
    [void]$builder.AppendLine("<path class=`"grid`" d=`"M24 $y`H1716`"/>")
  }
  [void]$builder.AppendLine('<text class="header" x="44" y="150">Framework</text>')
  $headers = @(
    @(430, "Hidden PWS", "(MB)"), @(565, "Workload PWS", "(MB)"),
    @(695, "Workload CPU", "(%)"), @(825, "GPU average", "(%)"),
    @(970, "Dedicated VRAM peak", "(MB)"), @(1130, "Shared GPU RAM peak", "(MB)"),
    @(1463, "Warm show / hide", "(ms)")
  )
  foreach ($header in $headers) {
    [void]$builder.AppendLine("<text class=`"header`" x=`"$($header[0])`" y=`"143`" text-anchor=`"middle`">$(Escape-Xml $header[1])<tspan x=`"$($header[0])`" dy=`"17`">$(Escape-Xml $header[2])</tspan></text>")
  }
  [void]$builder.AppendLine('<g class="value">')
  for ($index = 0; $index -lt $Data.Count; $index++) {
    $row = $Data[$index]
    $y = $tableTop + $headerHeight + $index * $rowHeight + 28
    $frameworkClass = if ($row.Name -eq "gpui-fast") { "framework baseline" } else { "framework" }
    [void]$builder.AppendLine("<text class=`"$frameworkClass`" x=`"44`" y=`"$y`">$(Escape-Xml $row.Display)</text>")
    $cells = @(
      @(430, "HiddenPwsMb", "0.0"), @(565, "WorkloadPwsMb", "0.0"),
      @(695, "CpuPercent", "0.000"), @(825, "GpuPercent", "0.000"),
      @(970, "DedicatedVramMb", "0.0"), @(1130, "SharedGpuMb", "0.0")
    )
    foreach ($cell in $cells) {
      $property = [string]$cell[1]
      $value = [double]$row.$property
      $class = Get-RelativeClass $Data $property $value ([double]$baseline.$property)
      [void]$builder.AppendLine("<text class=`"$class`" x=`"$($cell[0])`" y=`"$y`" text-anchor=`"middle`">$(Format-Number $value $cell[2])</text>")
    }
    $showClass = Get-RelativeClass $Data "ShowMs" ([double]$row.ShowMs) ([double]$baseline.ShowMs)
    $hideClass = Get-RelativeClass $Data "HideMs" ([double]$row.HideMs) ([double]$baseline.HideMs)
    [void]$builder.AppendLine("<text x=`"1463`" y=`"$y`" text-anchor=`"middle`"><tspan class=`"$showClass`">$(Format-Number $row.ShowMs '0.000')</tspan><tspan> / </tspan><tspan class=`"$hideClass`">$(Format-Number $row.HideMs '0.000')</tspan></text>")
  }
  [void]$builder.AppendLine('</g>')
  [void]$builder.AppendLine('<text class="subtitle" x="28" y="782">PWS = Private Working Set. Shared GPU RAM is system-memory-backed and is not dedicated VRAM. GPU 0.000 means no sampled engine activity was observed.</text>')
  [void]$builder.AppendLine('</svg>')
  $builder.ToString()
}

Write-Utf8File (Join-Path $outputRoot "overview.svg") (New-OverviewComparison $rows)
Write-Utf8File (Join-Path $outputRoot "ranking-heatmap.svg") (New-RankingHeatmap $rows)
Write-Utf8File (Join-Path $outputRoot "overall-ranking.svg") (New-OverallRanking $rows)
foreach ($row in $rows) {
  Write-Utf8File (Join-Path $radarRoot "$($row.Name).svg") (New-RadarCard $row)
}

$exportRows = @(
  foreach ($row in ($rows | Sort-Object OverallRank, Display)) {
    [ordered]@{
      name = $row.Name
      display = $row.Display
      source = $row.Source
      metrics = [ordered]@{
        hiddenPwsMb = $row.HiddenPwsMb
        workloadPwsMb = $row.WorkloadPwsMb
        workloadCpuPercent = $row.CpuPercent
        workloadGpuAveragePercent = $row.GpuPercent
        workloadDedicatedVramPeakMb = $row.DedicatedVramMb
        workloadSharedGpuPeakMb = $row.SharedGpuMb
        warmShowMs = $row.ShowMs
        warmHideMs = $row.HideMs
      }
      axisScores = [ordered]@{
        ram = $row.RamScore
        cpu = $row.CpuScore
        gpuActivity = $row.GpuScore
        dedicatedVram = $row.VramScore
        sharedGpuMemory = $row.SharedGpuScore
        warmShow = $row.ShowScore
        warmHide = $row.HideScore
      }
      axisRanks = [ordered]@{
        ram = $row.RamRank
        cpu = $row.CpuRank
        gpuActivity = $row.GpuRank
        dedicatedVram = $row.VramRank
        sharedGpuMemory = $row.SharedGpuRank
        warmShow = $row.ShowRank
        warmHide = $row.HideRank
      }
      overallScore = $row.OverallScore
      overallRank = $row.OverallRank
      weaknessFloor = $row.FloorScore
      hardwareCost = [ordered]@{
        workloadPwsPercentOfSystemRam = $row.SystemRamCostPercent
        dedicatedVramPercent = $row.DedicatedVramCostPercent
      }
    }
  }
)
$export = [ordered]@{
  schemaVersion = 2
  methodology = [ordered]@{
    direction = "lower-is-better"
    rankScore = "100 * (frameworkCount - averageTieRank) / (frameworkCount - 1)"
    ramAxis = "equal mean of hidden-PWS and workload-PWS rank scores"
    overall = "weighted arithmetic mean of the seven axis rank scores"
    radarAreaUsedForRanking = $false
    weights = [ordered]@{ ram = $Weights.Ram; cpu = $Weights.Cpu; gpu = $Weights.Gpu; vram = $Weights.Vram; sharedGpu = $Weights.SharedGpu; show = $Weights.Show; hide = $Weights.Hide }
    hardwareBaseline = [ordered]@{ systemRamGiB = $SystemRamGiB; dedicatedVramGiB = $DedicatedVramGiB }
  }
  frameworks = $exportRows
}
Write-Utf8File (Join-Path $outputRoot "comparison-data.json") ($export | ConvertTo-Json -Depth 10)

[pscustomobject]@{
  FrameworkCount = $rows.Count
  OutputDirectory = $outputRoot
  Overview = Join-Path $outputRoot "overview.svg"
  Heatmap = Join-Path $outputRoot "ranking-heatmap.svg"
  OverallRanking = Join-Path $outputRoot "overall-ranking.svg"
  RadarCount = @(Get-ChildItem -LiteralPath $radarRoot -Filter "*.svg").Count
}
