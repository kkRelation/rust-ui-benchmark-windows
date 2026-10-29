function Get-ProcessTreeRowsFromSnapshot {
  param(
    [Parameter(Mandatory = $true)][object[]]$Processes,
    [Parameter(Mandatory = $true)][int]$RootProcessId
  )

  $root = @($Processes | Where-Object { [int]$_.ProcessId -eq $RootProcessId } | Select-Object -First 1)
  if ($root.Count -eq 0) { return @() }

  $accepted = @{$RootProcessId = [datetime]$root[0].CreationDate}
  do {
    $added = $false
    foreach ($process in $Processes) {
      $processId = [int]$process.ProcessId
      $parentId = [int]$process.ParentProcessId
      if ($accepted.ContainsKey($processId) -or -not $accepted.ContainsKey($parentId)) { continue }
      if ($null -eq $process.CreationDate) { continue }
      $created = [datetime]$process.CreationDate
      if ($created -lt $accepted[$parentId]) { continue }
      $accepted[$processId] = $created
      $added = $true
    }
  } while ($added)

  @($Processes | Where-Object { $accepted.ContainsKey([int]$_.ProcessId) })
}

function Get-ProcessTreeRows {
  param([Parameter(Mandatory = $true)][int]$RootProcessId)
  Get-ProcessTreeRowsFromSnapshot -Processes @(Get-CimInstance Win32_Process) -RootProcessId $RootProcessId
}
