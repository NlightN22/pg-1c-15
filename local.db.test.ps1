param(
  [Parameter(Mandatory = $true)]
  [string]$Container,                  # Docker Compose service/container name, e.g. "pg1"
  [string]$DbName = "test_db"          # Fixed test DB name
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Psql {
  param(
    [Parameter(Mandatory = $true)][string]$Database,  # Target database
    [Parameter(Mandatory = $true)][string]$Sql,       # SQL to execute
    [switch]$Raw                                      # Return raw text (no headers/footers)
  )
  # Force ASCII messages and stable output; avoid reading ~/.psqlrc
  $baseArgs = @(
    "compose","exec","--user","postgres","-T",
    "--env","LANG=C","--env","LC_ALL=C",
    $Container,
    "psql","-v","ON_ERROR_STOP=1","-X","-q",
    "-P","pager=off","-P","footer=off",
    "-d",$Database
  )
  if ($Raw) { $baseArgs += @("-t","-A") }
  $baseArgs += @("-c",$Sql)

  $out = & docker @baseArgs
  $exit = $LASTEXITCODE
  if ($exit -ne 0) { throw "psql failed (db=$Database, exit=$exit)" }
  if ($Raw) { return ($out -join "`n").Trim() } else { $out | Write-Output }
}

function Drop-DbIfExists {
  param([Parameter(Mandatory = $true)][string]$Name)
  # Terminate sessions and drop DB in separate calls
  Invoke-Psql -Database "postgres" -Sql "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$Name';" | Out-Null
  Invoke-Psql -Database "postgres" -Sql "DROP DATABASE IF EXISTS $Name;" | Out-Null
}

try {
  Write-Host "Preparing test database '$DbName'..."

  # Ensure clean state
  $exists = Invoke-Psql -Database "postgres" -Sql "SELECT 1 FROM pg_database WHERE datname = '$DbName';" -Raw
  if ($exists -eq "1") {
    Write-Host "Existing DB found. Dropping '$DbName'..."
    Drop-DbIfExists -Name $DbName
  }

  # Create DB
  Write-Host "Creating database '$DbName'..."
  Invoke-Psql -Database "postgres" -Sql "CREATE DATABASE $DbName WITH ENCODING 'UTF8';" | Out-Null

  # Main DDL/DML test
  $testSql = @"
BEGIN;
CREATE TABLE public.test_items(
  id serial PRIMARY KEY,
  name text NOT NULL,
  qty int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX ON public.test_items(name);
INSERT INTO public.test_items(name, qty) VALUES
 ('alpha',10), ('beta',20), ('gamma',30);
SELECT count(*) AS cnt_before FROM public.test_items;
UPDATE public.test_items SET qty = qty + 5 WHERE name = 'alpha';
DELETE FROM public.test_items WHERE name = 'beta';
SELECT * FROM public.test_items ORDER BY id;
COMMIT;
"@

  Write-Host "Running DDL/DML checks..."
  Invoke-Psql -Database $DbName -Sql $testSql | Write-Output

  Write-Host "Quick integrity check..."
  Invoke-Psql -Database $DbName -Sql "SELECT sum(qty) AS total_qty FROM public.test_items;" | Write-Output

} finally {
  Write-Host "Cleaning up (terminate sessions and drop DB '$DbName')..."
  try {
    Drop-DbIfExists -Name $DbName
  } catch {
    Write-Warning "Cleanup encountered an error: $($_.Exception.Message)"
  }
}

Write-Host "Done. Database '$DbName' was tested and removed."