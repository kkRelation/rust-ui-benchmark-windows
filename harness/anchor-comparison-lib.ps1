function Get-AnchorPropertyValue {
  param(
    [AllowNull()][object]$Object,
    [Parameter(Mandatory = $true)][string]$Name
  )

  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  $property.Value
}

function Compare-AnchorMetric {
  param(
    [AllowNull()][object]$HistoricalStatistics,
    [AllowNull()][object]$CurrentStatistics,
    [Parameter(Mandatory = $true)][string]$Name
  )

  $historicalMedian = Get-AnchorPropertyValue -Object $HistoricalStatistics -Name "median"
  $historicalMinimum = Get-AnchorPropertyValue -Object $HistoricalStatistics -Name "minimum"
  $historicalMaximum = Get-AnchorPropertyValue -Object $HistoricalStatistics -Name "maximum"
  $currentMedian = Get-AnchorPropertyValue -Object $CurrentStatistics -Name "median"
  if ($null -eq $historicalMedian -or $null -eq $historicalMinimum -or
      $null -eq $historicalMaximum -or $null -eq $currentMedian) {
    return [pscustomobject]@{
      name = $Name
      status = "fail"
      rule = "missing-statistics"
      historical = $HistoricalStatistics
      current = $CurrentStatistics
      relativeDifference = $null
    }
  }

  $historicalMedian = [double]$historicalMedian
  $historicalMinimum = [double]$historicalMinimum
  $historicalMaximum = [double]$historicalMaximum
  $currentMedian = [double]$currentMedian
  if ($historicalMedian -eq 0) {
    $passed = $currentMedian -eq 0
    return [pscustomobject]@{
      name = $Name
      status = if ($passed) { "pass" } else { "fail" }
      rule = "historical-zero"
      historical = $HistoricalStatistics
      current = $CurrentStatistics
      relativeDifference = if ($passed) { 0 } else { $null }
    }
  }

  if ($currentMedian -ge $historicalMinimum -and $currentMedian -le $historicalMaximum) {
    return [pscustomobject]@{
      name = $Name
      status = "pass"
      rule = "historical-range"
      historical = $HistoricalStatistics
      current = $CurrentStatistics
      relativeDifference = [math]::Round(
        [math]::Abs($currentMedian - $historicalMedian) / [math]::Abs($historicalMedian),
        6
      )
    }
  }

  $relativeDifference = [math]::Abs($currentMedian - $historicalMedian) / [math]::Abs($historicalMedian)
  [pscustomobject]@{
    name = $Name
    status = if ($relativeDifference -le 0.1) { "pass" } else { "fail" }
    rule = "relative-10-percent"
    historical = $HistoricalStatistics
    current = $CurrentStatistics
    relativeDifference = [math]::Round($relativeDifference, 6)
  }
}

function Get-AnchorSummaryStatistics {
  param(
    [Parameter(Mandatory = $true)][object]$Result,
    [Parameter(Mandatory = $true)][string]$Framework,
    [Parameter(Mandatory = $true)][string]$Location,
    [Parameter(Mandatory = $true)][string]$Metric
  )

  if ($Location -eq "latency") {
    $entries = @($Result.summary.latency | Where-Object { $_.framework -eq $Framework })
    if ($entries.Count -ne 1) { return $null }
    return Get-AnchorPropertyValue -Object $entries[0] -Name $Metric
  }

  $entries = @(
    $Result.summary.phases |
      Where-Object { $_.framework -eq $Framework -and $_.phase -eq $Location }
  )
  if ($entries.Count -ne 1) { return $null }
  Get-AnchorPropertyValue -Object $entries[0].metrics -Name $Metric
}

function Get-AnchorWindowSignature {
  param([AllowNull()][object[]]$Windows)

  if ($null -eq $Windows) { return "<missing>" }
  $items = @(
    $Windows |
      Sort-Object Title,Width,Height |
      ForEach-Object {
        "$($_.Title)|$([bool]$_.Visible)|$([int]$_.Width)|$([int]$_.Height)"
      }
  )
  "count=$($items.Count);" + ($items -join ";")
}

function Get-AnchorProcessSignature {
  param([AllowNull()][object]$Phase)

  $processCount = Get-AnchorPropertyValue -Object $Phase -Name "processCount"
  $rendererCount = Get-AnchorPropertyValue -Object $Phase -Name "rendererCount"
  if ($null -eq $processCount -or $null -eq $rendererCount) { return "<missing>" }
  "processCount=$([int]$processCount);rendererCount=$([int]$rendererCount)"
}

function Compare-AnchorTopology {
  param(
    [Parameter(Mandatory = $true)][object]$Historical,
    [Parameter(Mandatory = $true)][object]$Current,
    [Parameter(Mandatory = $true)][string]$Framework
  )

  $historicalRuns = @($Historical.runs | Where-Object { $_.framework -eq $Framework -and $_.status -eq "ok" })
  $currentRuns = @($Current.runs | Where-Object { $_.framework -eq $Framework -and $_.status -eq "ok" })
  $checks = @()
  if ($historicalRuns.Count -eq 0 -or $currentRuns.Count -eq 0) {
    return [pscustomobject]@{
      Match = $false
      Checks = @([pscustomobject]@{
        name = "successful-runs"
        status = "fail"
        historicalAccepted = $historicalRuns.Count
        current = $currentRuns.Count
      })
    }
  }

  foreach ($phaseName in @("hiddenIdle", "visibleIdle", "workload400", "postHideIdle", "postCycleIdle")) {
    $historicalSignatures = @(
      $historicalRuns |
        ForEach-Object { Get-AnchorProcessSignature -Phase (Get-AnchorPropertyValue -Object $_.phases -Name $phaseName) } |
        Sort-Object -Unique
    )
    $currentSignatures = @(
      $currentRuns |
        ForEach-Object { Get-AnchorProcessSignature -Phase (Get-AnchorPropertyValue -Object $_.phases -Name $phaseName) }
    )
    $passed = @($currentSignatures | Where-Object { $_ -notin $historicalSignatures }).Count -eq 0
    $checks += [pscustomobject]@{
      name = "process.$phaseName"
      status = if ($passed) { "pass" } else { "fail" }
      historicalAccepted = $historicalSignatures
      current = $currentSignatures
    }
  }

  foreach ($stageName in @("hidden", "visible", "postHide", "postCycle")) {
    $historicalSignatures = @(
      $historicalRuns |
        ForEach-Object {
          Get-AnchorWindowSignature -Windows @(Get-AnchorPropertyValue -Object $_.topology -Name $stageName)
        } |
        Sort-Object -Unique
    )
    $currentSignatures = @(
      $currentRuns |
        ForEach-Object {
          Get-AnchorWindowSignature -Windows @(Get-AnchorPropertyValue -Object $_.topology -Name $stageName)
        }
    )
    $passed = @($currentSignatures | Where-Object { $_ -notin $historicalSignatures }).Count -eq 0
    $checks += [pscustomobject]@{
      name = "windows.$stageName"
      status = if ($passed) { "pass" } else { "fail" }
      historicalAccepted = $historicalSignatures
      current = $currentSignatures
    }
  }

  [pscustomobject]@{
    Match = @($checks | Where-Object status -eq "fail").Count -eq 0
    Checks = $checks
  }
}

function ConvertTo-AnchorEnvironmentValue {
  param(
    [AllowNull()][object]$Environment,
    [Parameter(Mandatory = $true)][string]$Name
  )

  $value = Get-AnchorPropertyValue -Object $Environment -Name $Name
  if ($null -eq $value) { return $null }
  switch ($Name) {
    "cpu" { return (@($value | ForEach-Object { "$_" } | Sort-Object) -join "|") }
    "gpu" {
      return (@(
        $value |
          ForEach-Object { "$($_.name)|$($_.driverVersion)" } |
          Sort-Object
      ) -join "|")
    }
    default { return "$value".Trim() }
  }
}

function Compare-AnchorEnvironment {
  param(
    [Parameter(Mandatory = $true)][object]$Historical,
    [Parameter(Mandatory = $true)][object]$Current
  )

  $checks = @(
    foreach ($name in @("osVersion", "logicalProcessors", "cpu", "gpu", "powerPlan")) {
      $historicalValue = ConvertTo-AnchorEnvironmentValue -Environment $Historical.environment -Name $name
      $currentValue = ConvertTo-AnchorEnvironmentValue -Environment $Current.environment -Name $name
      $passed = $null -ne $historicalValue -and $null -ne $currentValue -and $historicalValue -eq $currentValue
      [pscustomobject]@{
        name = $name
        status = if ($passed) { "pass" } else { "fail" }
        historical = $historicalValue
        current = $currentValue
      }
    }
  )
  [pscustomobject]@{
    Match = @($checks | Where-Object status -eq "fail").Count -eq 0
    Checks = $checks
  }
}

function Compare-ResidentAnchor {
  param(
    [Parameter(Mandatory = $true)][object]$Historical,
    [Parameter(Mandatory = $true)][object]$Current,
    [Parameter(Mandatory = $true)][string]$Framework
  )

  $descriptors = @(
    [pscustomobject]@{ Name = "hiddenIdle.privateWorkingSetMb"; Location = "hiddenIdle"; Metric = "privateWorkingSetMb" },
    [pscustomobject]@{ Name = "workload400.privateWorkingSetMb"; Location = "workload400"; Metric = "privateWorkingSetMb" },
    [pscustomobject]@{ Name = "workload400.cpuMachinePercent"; Location = "workload400"; Metric = "cpuMachinePercent" },
    [pscustomobject]@{ Name = "workload400.gpuEngineAveragePercent"; Location = "workload400"; Metric = "gpuEngineAveragePercent" },
    [pscustomobject]@{ Name = "workload400.dedicatedGpuPeakMb"; Location = "workload400"; Metric = "dedicatedGpuPeakMb" },
    [pscustomobject]@{ Name = "workload400.sharedGpuPeakMb"; Location = "workload400"; Metric = "sharedGpuPeakMb" },
    [pscustomobject]@{ Name = "latency.showLatencyMs"; Location = "latency"; Metric = "showLatencyMs" },
    [pscustomobject]@{ Name = "latency.hideLatencyMs"; Location = "latency"; Metric = "hideLatencyMs" },
    [pscustomobject]@{ Name = "postHideIdle.cpuMachinePercent"; Location = "postHideIdle"; Metric = "cpuMachinePercent" }
  )
  $metrics = @(
    foreach ($descriptor in $descriptors) {
      Compare-AnchorMetric `
        -HistoricalStatistics (Get-AnchorSummaryStatistics -Result $Historical -Framework $Framework -Location $descriptor.Location -Metric $descriptor.Metric) `
        -CurrentStatistics (Get-AnchorSummaryStatistics -Result $Current -Framework $Framework -Location $descriptor.Location -Metric $descriptor.Metric) `
        -Name $descriptor.Name
    }
  )
  $topology = Compare-AnchorTopology -Historical $Historical -Current $Current -Framework $Framework
  $environment = Compare-AnchorEnvironment -Historical $Historical -Current $Current
  $failedMetricCount = @($metrics | Where-Object status -eq "fail").Count
  $passed = $failedMetricCount -eq 0 -and $topology.Match -and $environment.Match

  [pscustomobject]@{
    framework = $Framework
    status = if ($passed) { "pass" } else { "fail" }
    failedMetricCount = $failedMetricCount
    retryEligible = $failedMetricCount -eq 1 -and $topology.Match -and $environment.Match
    topologyMatch = [bool]$topology.Match
    environmentMatch = [bool]$environment.Match
    metrics = $metrics
    topology = $topology.Checks
    environment = $environment.Checks
  }
}
