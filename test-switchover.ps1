param(
  [string]$ComposeDir = ".",                 # Path to directory with docker-compose.yml
  [string]$NodeA = "pg1",                    # First Patroni node
  [string]$NodeB = "pg2",                    # Second Patroni node
  [string]$DbName = "postgres",              # Target database
  [string]$Table  = "public.test_replica"    # Test table (created if missing)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Helpers (English comments only) ---
function Invoke-Compose {
  param([string[]]$ArgList)
  Push-Location -Path (Resolve-Path $ComposeDir) | Out-Null
  try {
    $dcArgs = $ArgList
    $null = & docker @dcArgs
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw "docker exited with code ${code}: $($dcArgs -join ' ')" }
  } finally { Pop-Location | Out-Null }
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
  } finally { Pop-Location | Out-Null }
}

function Patroni-ListJson {
  # patronictl list JSON can be object with .members or an array
  $raw = Invoke-ComposeCap @("compose","exec","-T",$NodeA,"patronictl","list","--format","json")
  return ($raw | ConvertFrom-Json)
}

function Get-Leader {
  $j = Patroni-ListJson
  if ($null -ne ($j.PSObject.Properties['members'])) {
    $leader = ($j.members | Where-Object { $_.role -eq 'Leader' } | Select-Object -First 1).member
  } else {
    $leader = ($j | Where-Object { $_.Role -eq 'Leader' } | Select-Object -First 1).Member
  }
  if (-not $leader) { throw "Leader not found" }
  return $leader
}

function Get-Replica {
  param([Parameter(Mandatory = $true)][string]$Leader)
  if ($Leader -eq $NodeA) { return $NodeB } else { return $NodeA }
}

function Patroni-Switchover {
  param([Parameter(Mandatory = $true)][string]$Candidate)
  Invoke-Compose @("compose","exec","-T",$NodeA,"patronictl","switchover","--candidate",$Candidate,"--force")
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
  return (Invoke-ComposeCap $dcArgs)
}

# --- Test 2: switchover with verification and cleanup ---
$leader  = Get-Leader
$target  = Get-Replica -Leader $leader
Write-Host "Current leader=${leader}; switchover target=${target}"

try {
  # perform controlled switchover
  Patroni-Switchover -Candidate $target
  Start-Sleep -Seconds 3

  $newLeader  = Get-Leader
  if ($newLeader -ne $target) { throw "Expected new leader ${target}, got ${newLeader}" }
  $newReplica = Get-Replica -Leader $newLeader
  Write-Host "Switchover OK. New leader=${newLeader}; new replica=${newReplica}"

  # ensure table exists and insert a row on new leader
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
VALUES ((extract(epoch from now())::int % 1000000), 'after switchover')
ON CONFLICT (id) DO NOTHING;
COMMIT;
"@
  $null = Invoke-Psql -Service $newLeader -Sql $ddlDml

  # verify on new replica
  $cnt = Invoke-Psql -Service $newReplica -Sql "SELECT count(*) FROM $Table;" -Raw
  Write-Host "Replica row count after switchover: $cnt"

  # optional tail for visibility
  $null = Invoke-Psql -Service $newReplica -Sql "SELECT id,val,created_at FROM $Table ORDER BY created_at DESC NULLS LAST LIMIT 3;"

} finally {
  # cleanup test artifacts from the current leader (post-switchover)
  try {
    Write-Host "Cleaning up test table..."
    $finalLeader = Get-Leader
    $null = Invoke-Psql -Service $finalLeader -Sql "DROP TABLE IF EXISTS $Table;"
  } catch {
    Write-Warning "Cleanup failed: $($_.Exception.Message)"
  }
}
