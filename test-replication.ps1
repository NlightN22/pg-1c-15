# test-replication.ps1
param(
  [string]$ComposeDir = "." ,                 # Path to directory with docker-compose.yml
  [string]$NodeA = "pg1",              # First Patroni node service name
  [string]$NodeB = "pg2",              # Second Patroni node service name
  [string]$DbName = "postgres",        # Target database
  [string]$Table = "public.test_replica" # Test table
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Helpers (English comments only) ---
function Invoke-Compose {
  param([string[]]$ArgList)
  Push-Location -Path (Resolve-Path $ComposeDir) | Out-Null
  try {
    $dcArgs = $ArgList
    & docker @dcArgs
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw "docker exited with code ${code}: $($dcArgs -join ' ')" }
  } finally {
    Pop-Location | Out-Null
  }
}

function Invoke-ComposeCap {
  param([string[]]$ArgList)
  Push-Location -Path (Resolve-Path $ComposeDir) | Out-Null
  try {
    $dcArgs = $ArgList
    $out = & docker @dcArgs
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw "docker exited with code ${code}: $($dcArgs -join ' ')" }
    return ($out -join "`n").Trim()
  } finally {
    Pop-Location | Out-Null
  }
}

function Patroni-ListJson {
  # Query cluster state (JSON may be either an object or an array of rows)
  $raw = Invoke-ComposeCap @("compose","exec","-T",$NodeA,"patronictl","list","--format","json")
  try {
    return ($raw | ConvertFrom-Json)
  } catch {
    throw "patronictl JSON parse failed: $($_.Exception.Message)"
  }
}

function Get-Leader {
  $j = Patroni-ListJson
  # Handle two common shapes:
  # 1) Object with .members[]
  # 2) Array of rows with fields: Member, Role, ...
  if ($null -ne ($j.PSObject.Properties['members'])) {
    $leader = ($j.members | Where-Object { $_.role -eq 'Leader' } | Select-Object -First 1).member
  } else {
    $leader = ($j | Where-Object { $_.Role -eq 'Leader' } | Select-Object -First 1).Member
  }
  if (-not $leader) { throw "Leader not found in patronictl output." }
  return $leader
}
function Get-Replica {
  param([Parameter(Mandatory = $true)][string]$Leader)
  if ($Leader -eq $NodeA) { return $NodeB } else { return $NodeA }
}

function Invoke-Psql {
  param(
    [Parameter(Mandatory = $true)][string]$Service,
    [Parameter(Mandatory = $true)][string]$Sql,
    [switch]$Raw
  )
  $dcArgs = @(
    "compose","exec","--user","postgres","-T",
    "--env","LANG=C","--env","LC_ALL=C",
    $Service,
    "psql","-v","ON_ERROR_STOP=1","-X","-q",
    "-P","pager=off","-P","footer=off",
    "-d",$DbName
  )
  if ($Raw) { $dcArgs += @("-t","-A") }
  $dcArgs += @("-c",$Sql)
  Invoke-Compose $dcArgs
}

function Invoke-PsqlCap {
  param(
    [Parameter(Mandatory = $true)][string]$Service,
    [Parameter(Mandatory = $true)][string]$Sql,
    [switch]$Raw
  )
  $dcArgs = @(
    "compose","exec","--user","postgres","-T",
    "--env","LANG=C","--env","LC_ALL=C",
    $Service,
    "psql","-v","ON_ERROR_STOP=1","-X","-q",
    "-P","pager=off","-P","footer=off",
    "-d",$DbName
  )
  if ($Raw) { $dcArgs += @("-t","-A") }
  $dcArgs += @("-c",$Sql)
  Invoke-ComposeCap $dcArgs
}

# --- Test 1: create on leader, read on replica ---
try {
    $leader  = Get-Leader
    $replica = Get-Replica -Leader $leader
    Write-Host "Leader=${leader}; Replica=${replica}"

    # Create table and insert one row on leader
    $ddlDml = @"
BEGIN;
CREATE TABLE IF NOT EXISTS $Table(
  id int PRIMARY KEY,
  val text NOT NULL
);
ALTER TABLE $Table
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
UPDATE $Table SET created_at = now() WHERE created_at IS NULL;
INSERT INTO $Table(id,val)
VALUES ((extract(epoch from now())::int % 1000000), 'hello from leader')
ON CONFLICT (id) DO NOTHING;
COMMIT;
"@
    Invoke-Psql -Service $leader -Sql $ddlDml

    # Verify on replica
    $cnt = Invoke-PsqlCap -Service $replica -Sql "SELECT count(*) FROM $Table;" -Raw
    if ([int]$cnt -lt 1) { throw "Replica does not see inserted rows (count=${cnt})" }
    Write-Host "Replica sees rows: $cnt"

    # Optional: show latest rows on replica
    Invoke-Psql -Service $replica -Sql "SELECT id,val,created_at FROM $Table ORDER BY created_at DESC NULLS LAST LIMIT 3;"
}
finally {
    Write-Host "Cleaning up test table..."
    try {
        Invoke-Psql -Service $leader -Sql "DROP TABLE IF EXISTS $Table;"
    } catch {
        Write-Warning "Cleanup failed: $($_.Exception.Message)"
    }
}