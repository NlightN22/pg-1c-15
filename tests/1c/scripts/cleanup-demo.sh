#!/bin/bash
set -euo pipefail

INFOBASE_NAME="${INFOBASE_NAME:-1cdb_demo}"

PLATFORM_DIR="$(find /opt/1cv8/x86_64 -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
RAC="${PLATFORM_DIR}/rac"

CLUSTER_ID="$("${RAC}" cluster list | awk -F': ' '/^cluster/ { print $2; exit }')"

if [ -z "${CLUSTER_ID}" ]; then
  echo "Failed to detect 1C cluster id." >&2
  exit 1
fi

INFOBASE_ID="$("${RAC}" infobase summary list --cluster="${CLUSTER_ID}" \
  | awk -v name="${INFOBASE_NAME}" '
      /^infobase[[:space:]]*:/ { current = $3 }
      /^name[[:space:]]*:/ && $3 == name { print current; exit }
    ')"

if [ -z "${INFOBASE_ID}" ]; then
  echo "Infobase '${INFOBASE_NAME}' was not found."
  exit 0
fi

echo "Dropping infobase '${INFOBASE_NAME}' (${INFOBASE_ID}) and its database..."
"${RAC}" infobase drop \
  --cluster="${CLUSTER_ID}" \
  --infobase="${INFOBASE_ID}" \
  --drop-database

echo "Cleanup completed."
