param(
  [Parameter(Mandatory = $true)][string]$WorkRoot,
  [Parameter(Mandatory = $true)][ValidateRange(1, [long]::MaxValue)][long]$MinimumFreeBytes
)

$ErrorActionPreference = "Stop"

function Get-FerroUiFreeBytes {
  param([Parameter(Mandatory = $true)][string]$Path)

  $absolute = [System.IO.Path]::GetFullPath($Path)
  $driveRoot = [System.IO.Path]::GetPathRoot($absolute)
  ([System.IO.DriveInfo]::new($driveRoot)).AvailableFreeSpace
}

function Find-FerroUiMsvc {
  $onPath = Get-Command cl.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($null -ne $onPath) { return $onPath.Source }

  if (-not [string]::IsNullOrWhiteSpace($env:VCToolsInstallDir)) {
    $candidate = Join-Path $env:VCToolsInstallDir "bin\Hostx64\x64\cl.exe"
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
  }

  $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
  if (Test-Path -LiteralPath $vswhere -PathType Leaf) {
    $installation = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not [string]::IsNullOrWhiteSpace($installation)) {
      $toolsRoot = Join-Path $installation "VC\Tools\MSVC"
      if (Test-Path -LiteralPath $toolsRoot -PathType Container) {
        $match = fd --absolute-path --type f '^cl\.exe$' $toolsRoot |
          Where-Object { $_ -match '[\\/]bin[\\/]Hostx64[\\/]x64[\\/]cl\.exe$' } |
          Sort-Object -Descending |
          Select-Object -First 1
        if ($null -ne $match) { return $match }
      }
    }
  }
  $null
}

function Find-FerroUiLibClang {
  if (-not [string]::IsNullOrWhiteSpace($env:LIBCLANG_PATH)) {
    $configured = if (Test-Path -LiteralPath $env:LIBCLANG_PATH -PathType Leaf) {
      $env:LIBCLANG_PATH
    } else {
      Join-Path $env:LIBCLANG_PATH "libclang.dll"
    }
    if (Test-Path -LiteralPath $configured -PathType Leaf) { return $configured }
  }

  $candidates = @(
    (Join-Path $env:ProgramFiles "LLVM\bin\libclang.dll"),
    (Join-Path ${env:ProgramFiles(x86)} "LLVM\bin\libclang.dll"),
    (Join-Path $env:USERPROFILE "scoop\apps\llvm\current\bin\libclang.dll"),
    "E:\Scoop\apps\llvm\current\bin\libclang.dll"
  )
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
  }
  $null
}

function Invoke-FerroUiPreflight {
  param(
    [Parameter(Mandatory = $true)][string]$WorkRoot,
    [Parameter(Mandatory = $true)][long]$MinimumFreeBytes
  )

  $freeBytes = [long](Get-FerroUiFreeBytes -Path $WorkRoot)
  $msvcPath = Find-FerroUiMsvc
  $libclangPath = Find-FerroUiLibClang
  $reasons = [System.Collections.Generic.List[string]]::new()

  if ($freeBytes -lt $MinimumFreeBytes) {
    [void]$reasons.Add("insufficient-free-space")
  }
  if ([string]::IsNullOrWhiteSpace($msvcPath)) {
    [void]$reasons.Add("missing-msvc-x64")
  }
  if ([string]::IsNullOrWhiteSpace($libclangPath)) {
    [void]$reasons.Add("missing-libclang")
  }

  [pscustomobject]@{
    workRoot = [System.IO.Path]::GetFullPath($WorkRoot)
    freeBytes = $freeBytes
    minimumFreeBytes = $MinimumFreeBytes
    msvc = [pscustomobject]@{
      found = -not [string]::IsNullOrWhiteSpace($msvcPath)
      path = $msvcPath
    }
    libclang = [pscustomobject]@{
      found = -not [string]::IsNullOrWhiteSpace($libclangPath)
      path = $libclangPath
    }
    passed = $reasons.Count -eq 0
    reasons = @($reasons)
  }
}

if ($MyInvocation.InvocationName -ne ".") {
  Invoke-FerroUiPreflight -WorkRoot $WorkRoot -MinimumFreeBytes $MinimumFreeBytes |
    ConvertTo-Json -Depth 4
}
