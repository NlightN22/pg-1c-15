param(
  [string]$Version,
  [string]$ImageName = "oncharterliz/pg-1c-15",
  [string]$Dockerfile = "Dockerfile",
  [string]$Context = ".",
  [switch]$NoCache
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Version)) {
  $Version = Read-Host "Enter Docker image version tag"
}

if ([string]::IsNullOrWhiteSpace($Version)) {
  throw "Docker image version tag is required."
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
& docker @buildArgs

if ($LASTEXITCODE -ne 0) {
  throw "docker build failed with exit code $LASTEXITCODE."
}

Write-Host "Build completed."
