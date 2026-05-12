param(
  [string]$Version,
  [string]$ImageName = "oncharterliz/pg-1c-15",
  [string]$Dockerfile = "Dockerfile",
  [string]$Context = ".",
  [switch]$NoCache,
  [switch]$Push,
  [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-DockerChecked {
  param([Parameter(Mandatory = $true)][string[]]$Arguments)

  & docker @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "docker failed with exit code ${LASTEXITCODE}: $($Arguments -join ' ')"
  }
}

function Test-RemoteTag {
  param(
    [Parameter(Mandatory = $true)][string]$Image,
    [Parameter(Mandatory = $true)][string]$Tag
  )

  $previousErrorActionPreference = $ErrorActionPreference
  $previousNativeErrorPreference = $null
  if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $previousNativeErrorPreference = $global:PSNativeCommandUseErrorActionPreference
    $global:PSNativeCommandUseErrorActionPreference = $false
  }

  try {
    $ErrorActionPreference = 'Continue'
    $null = & docker buildx imagetools inspect "${Image}:${Tag}" 2>&1
    return ($LASTEXITCODE -eq 0)
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
    if ($null -ne $previousNativeErrorPreference) {
      $global:PSNativeCommandUseErrorActionPreference = $previousNativeErrorPreference
    }
  }
}

if ([string]::IsNullOrWhiteSpace($Version)) {
  $Version = Read-Host "Enter Docker image version tag"
}

if ([string]::IsNullOrWhiteSpace($Version)) {
  throw "Docker image version tag is required."
}

if ($Push -and -not $Force -and (Test-RemoteTag -Image $ImageName -Tag $Version)) {
  $answer = Read-Host "Remote tag ${ImageName}:${Version} already exists. Overwrite it? Type 'yes' to continue"
  if ($answer -ne 'yes') {
    throw "Push was cancelled because remote tag ${ImageName}:${Version} already exists."
  }
}

$buildArgs = @(
  "build",
  "-f", $Dockerfile,
  "-t", "${ImageName}:${Version}",
  "-t", "${ImageName}:latest"
)

if ($NoCache) {
  $buildArgs += "--no-cache"
}

$buildArgs += $Context

Write-Host "Building ${ImageName}:${Version} and ${ImageName}:latest..."
Invoke-DockerChecked -Arguments $buildArgs

Write-Host "Build completed."

if ($Push) {
  Write-Host "Pushing ${ImageName}:${Version}..."
  Invoke-DockerChecked -Arguments @("push", "${ImageName}:${Version}")

  Write-Host "Pushing ${ImageName}:latest..."
  Invoke-DockerChecked -Arguments @("push", "${ImageName}:latest")

  Write-Host "Push completed."
}
