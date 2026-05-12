#!/bin/bash
set -euo pipefail

DB_HOST="${DB_HOST:-pg1}"
DB_USER="${DB_USER:-postgres}"
DB_PASSWORD="${DB_PASSWORD:-postgres}"
INFOBASE_NAME="${INFOBASE_NAME:-1cdb_demo}"
INFOBASE_LOCALE="${INFOBASE_LOCALE:-ru}"
DT_PATH="${DT_PATH:-/home/www/1cv8.dt}"

PLATFORM_DIR="$(find /opt/1cv8/x86_64 -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
RAC="${PLATFORM_DIR}/rac"
WEBINST="${PLATFORM_DIR}/webinst"
IBCMD="${PLATFORM_DIR}/ibcmd"

wait_for_cluster() {
  for _ in $(seq 1 60); do
    if su usr1cv8 -c "\"${RAC}\" cluster list" | grep -q "^cluster"; then
      return 0
    fi
    sleep 2
  done

  echo "1C cluster is not available." >&2
  return 1
}

get_cluster_id() {
  su usr1cv8 -c "\"${RAC}\" cluster list" \
    | awk -F': ' '/^cluster/ { print $2; exit }'
}

wait_for_cluster
CLUSTER_ID="$(get_cluster_id)"

if [ -z "${CLUSTER_ID}" ]; then
  echo "Failed to detect 1C cluster id." >&2
  exit 1
fi

echo "Using 1C cluster: ${CLUSTER_ID}"
echo "Creating infobase '${INFOBASE_NAME}' on PostgreSQL host '${DB_HOST}'..."

su usr1cv8 -c "\"${RAC}\" infobase --cluster=\"${CLUSTER_ID}\" create \
  --create-database \
  --name=\"${INFOBASE_NAME}\" \
  --dbms=postgresql \
  --db-server=\"${DB_HOST}\" \
  --db-name=\"${INFOBASE_NAME}\" \
  --locale=\"${INFOBASE_LOCALE}\" \
  --db-user=\"${DB_USER}\" \
  --db-pwd=\"${DB_PASSWORD}\" \
  --license-distribution=allow"

echo "Publishing '${INFOBASE_NAME}' to Apache..."
"${WEBINST}" -publish -apache24 \
  -wsdir "${INFOBASE_NAME}" \
  -dir "/var/www/${INFOBASE_NAME}" \
  -connstr "Srvr=srv1ck8s;Ref=${INFOBASE_NAME};" \
  -confpath /etc/apache2/sites-enabled/ws1c.conf

service apache2 reload

if [ -f "${DT_PATH}" ]; then
  echo "Restoring infobase from '${DT_PATH}'..."
  "${IBCMD}" infobase restore \
    --db-server="${DB_HOST}" \
    --dbms=postgresql \
    --db-name="${INFOBASE_NAME}" \
    --db-user="${DB_USER}" \
    --db-pwd="${DB_PASSWORD}" \
    "${DT_PATH}"
else
  echo "DT file '${DT_PATH}' was not found. Infobase was created without restore."
fi

echo "1C demo infobase setup completed."
