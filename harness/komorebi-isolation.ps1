function Get-FlatKomorebiIdentifiers {
  param([AllowNull()][object]$Value)

  if ($null -eq $Value) { return }
  if ($Value -is [string] -or $Value -is [pscustomobject]) {
    $Value
    return
  }
  if ($Value -is [System.Collections.IEnumerable]) {
    foreach ($item in $Value) {
      Get-FlatKomorebiIdentifiers -Value $item
    }
    return
  }
  $Value
}

function Test-KomorebiExactTitleIgnoreRule {
  param(
    [AllowNull()][object]$Identifiers,
    [Parameter(Mandatory = $true)][string]$Title
  )

  @(
    Get-FlatKomorebiIdentifiers -Value $Identifiers |
      Where-Object {
        $_.kind -eq "Title" -and
        $_.id -eq $Title -and
        $_.matching_strategy -in @("Equals", "Legacy")
      }
  ).Count -gt 0
}

function Test-BenchmarkKomorebiRunning {
  @((Get-Process -Name "komorebi" -ErrorAction SilentlyContinue)).Count -gt 0
}

function Get-BenchmarkKomorebiCommand {
  $commands = @(Get-Command "komorebic" -CommandType Application -ErrorAction Stop)
  if ($commands.Count -eq 0) {
    throw "komorebi is running but komorebic is unavailable."
  }
  $commands[0].Source
}

function Get-BenchmarkKomorebiState {
  $command = Get-BenchmarkKomorebiCommand
  $json = (& $command global-state) -join "`n"
  if ($LASTEXITCODE -ne 0) {
    throw "komorebic global-state failed with exit code $LASTEXITCODE"
  }
  $json | ConvertFrom-Json
}

function Invoke-BenchmarkKomorebiIgnoreRule {
  param([Parameter(Mandatory = $true)][string]$Title)

  $command = Get-BenchmarkKomorebiCommand
  & $command ignore-rule title $Title
  if ($LASTEXITCODE -ne 0) {
    throw "komorebic failed to ignore benchmark title '$Title' with exit code $LASTEXITCODE"
  }
}

function Ensure-BenchmarkWindowsIgnoredByKomorebi {
  $titles = @(
    "UI Framework Bench - Main",
    "UI Framework Bench - Auxiliary Canvas"
  )
  if (-not (Test-BenchmarkKomorebiRunning)) {
    return [pscustomobject]@{
      manager = "komorebi"
      active = $false
      verified = $true
      requiredRules = $titles
      addedRules = @()
    }
  }

  $initial = Get-BenchmarkKomorebiState
  $added = @()
  foreach ($title in $titles) {
    if (-not (Test-KomorebiExactTitleIgnoreRule -Identifiers $initial.ignore_identifiers -Title $title)) {
      Invoke-BenchmarkKomorebiIgnoreRule -Title $title
      $added += $title
    }
  }

  $final = Get-BenchmarkKomorebiState
  $missing = @(
    $titles |
      Where-Object {
        -not (Test-KomorebiExactTitleIgnoreRule -Identifiers $final.ignore_identifiers -Title $_)
      }
  )
  if ($missing.Count -gt 0) {
    throw "Could not verify komorebi ignore rules for benchmark windows: $($missing -join ', ')"
  }

  [pscustomobject]@{
    manager = "komorebi"
    active = $true
    verified = $true
    requiredRules = $titles
    addedRules = $added
  }
}
