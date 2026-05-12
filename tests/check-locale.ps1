param(
  [string]$ComposeFile = "docker-compose.min.yml",
  [string]$Service = "pg1",
  [string]$Database = "postgres"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Docker {
  param([Parameter(Mandatory = $true)][string[]]$Arguments)

  $previousErrorActionPreference = $ErrorActionPreference
  $previousNativeErrorPreference = $null
  if (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue) {
    $previousNativeErrorPreference = $global:PSNativeCommandUseErrorActionPreference
    $global:PSNativeCommandUseErrorActionPreference = $false
  }

  try {
    $ErrorActionPreference = 'Continue'
    $output = & docker @Arguments 2>&1
    $exitCode = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $previousErrorActionPreference
    if ($null -ne $previousNativeErrorPreference) {
      $global:PSNativeCommandUseErrorActionPreference = $previousNativeErrorPreference
    }
  }

  return [PSCustomObject]@{
    ExitCode = $exitCode
    Output = ($output -join "`n").Trim()
  }
}

function Invoke-Psql {
  param(
    [Parameter(Mandatory = $true)][string]$Sql,
    [switch]$AllowFailure
  )

  $args = @(
    "compose", "-f", $ComposeFile,
    "exec", "-T", "--user", "postgres",
    $Service,
    "psql",
    "-X", "-q", "-t", "-A",
    "-d", $Database,
    "-c", $Sql
  )

  $result = Invoke-Docker -Arguments $args
  if (-not $AllowFailure -and $result.ExitCode -ne 0) {
    throw "psql failed with exit code $($result.ExitCode): $($result.Output)"
  }

  return $result
}

function Get-ServiceLogs {
  $result = Invoke-Docker -Arguments @(
    "compose", "-f", $ComposeFile,
    "logs", "--tail", "300",
    $Service
  )

  if ($result.ExitCode -ne 0) {
    throw "docker compose logs failed: $($result.Output)"
  }

  return $result.Output
}

Write-Host "Checking system locales..."
$localeResult = Invoke-Docker -Arguments @(
  "compose", "-f", $ComposeFile,
  "exec", "-T",
  $Service,
  "locale", "-a"
)

if ($localeResult.ExitCode -ne 0) {
  throw "locale -a failed: $($localeResult.Output)"
}

$locales = $localeResult.Output -split "`n"
$hasRussian = $locales | Where-Object { $_ -match '^ru_RU\.utf8$' }
$hasEnglish = $locales | Where-Object { $_ -match '^en_US\.utf8$' }

if (-not $hasRussian) {
  throw "Locale ru_RU.utf8 was not found."
}

if (-not $hasEnglish) {
  throw "Locale en_US.utf8 was not found."
}

Write-Host "System locales OK: ru_RU.utf8, en_US.utf8"

Write-Host "Checking PostgreSQL locale settings..."
$settings = Invoke-Psql -Sql "SELECT current_setting('lc_messages'), current_setting('lc_collate'), current_setting('lc_ctype');"
Write-Host "Current PostgreSQL locale settings: $($settings.Output)"

$russian = Invoke-Psql -Sql "SET lc_messages TO 'ru_RU.UTF-8'; SHOW lc_messages;"
if ($russian.Output -notmatch 'ru_RU\.UTF-8') {
  throw "Failed to switch lc_messages to ru_RU.UTF-8. Output: $($russian.Output)"
}

$english = Invoke-Psql -Sql "SET lc_messages TO 'en_US.UTF-8'; SHOW lc_messages;"
if ($english.Output -notmatch 'en_US\.UTF-8') {
  throw "Failed to switch lc_messages to en_US.UTF-8. Output: $($english.Output)"
}

Write-Host "PostgreSQL lc_messages accepts both ru_RU.UTF-8 and en_US.UTF-8"

$probe = Invoke-Psql -Sql "SET lc_messages TO 'en_US.UTF-8'; SELECT 1;" -AllowFailure
if ($probe.ExitCode -ne 0) {
  throw "Simple query failed after switching lc_messages to en_US.UTF-8. Output: $($probe.Output)"
}

$logs = Get-ServiceLogs
if ($logs -match 'lc_messages' -and $logs -match 'en_US\.UTF-8') {
  throw "PostgreSQL logs contain an en_US.UTF-8 lc_messages error."
}

Write-Host "No en_US.UTF-8 lc_messages error was found in recent PostgreSQL logs."
Write-Host "Locale test completed."
