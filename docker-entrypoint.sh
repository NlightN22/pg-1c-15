#!/bin/bash
set -e

readonly PATRONI_SCOPE="${PATRONI_SCOPE:-batman}"
PATRONI_NAMESPACE="${PATRONI_NAMESPACE:-/service}"
readonly PATRONI_NAMESPACE="${PATRONI_NAMESPACE%/}"
DOCKER_IP=$(hostname --ip-address)
readonly DOCKER_IP

readonly PGHOME=/var/lib/pgpro/1c-15
readonly PGDATA=$PGHOME/data

export DUMB_INIT_SETSID=0

## We start an etcd
if [ -z "$PATRONI_ETCD3_HOSTS" ] && [ -z "$PATRONI_ZOOKEEPER_HOSTS" ]; then
    export PATRONI_ETCD_URL="http://127.0.0.1:2379"
    etcd --data-dir /tmp/etcd.data -advertise-client-urls=$PATRONI_ETCD_URL -listen-client-urls=http://0.0.0.0:2379 > /var/log/etcd.log 2> /var/log/etcd.err &
fi

# Set standard Patroni environment variables
export PATRONI_SCOPE
export PATRONI_NAMESPACE
export PATRONI_NAME="${PATRONI_NAME:-$(hostname)}"
export PATRONI_RESTAPI_CONNECT_ADDRESS="${PATRONI_RESTAPI_CONNECT_ADDRESS:-$DOCKER_IP:8008}"
export PATRONI_RESTAPI_LISTEN="${PATRONI_RESTAPI_LISTEN:-0.0.0.0:8008}"
export PATRONI_admin_PASSWORD="${PATRONI_admin_PASSWORD:-admin}"
export PATRONI_admin_OPTIONS="${PATRONI_admin_OPTIONS:-createdb, createrole}"
export PATRONI_POSTGRESQL_CONNECT_ADDRESS="${PATRONI_POSTGRESQL_CONNECT_ADDRESS:-$DOCKER_IP:5432}"
export PATRONI_POSTGRESQL_LISTEN="${PATRONI_POSTGRESQL_LISTEN:-0.0.0.0:5432}"
export PATRONI_POSTGRESQL_DATA_DIR="${PATRONI_POSTGRESQL_DATA_DIR:-$PGDATA}"
export PATRONI_REPLICATION_USERNAME="${PATRONI_REPLICATION_USERNAME:-replicator}"
export PATRONI_REPLICATION_PASSWORD="${PATRONI_REPLICATION_PASSWORD:-replicate}"
export PATRONI_SUPERUSER_USERNAME="${PATRONI_SUPERUSER_USERNAME:-postgres}"
export PATRONI_SUPERUSER_PASSWORD="${PATRONI_SUPERUSER_PASSWORD:-postgres}"
export PATRONI_REPLICATION_SSLMODE="${PATRONI_REPLICATION_SSLMODE:-$PGSSLMODE}"
export PATRONI_REPLICATION_SSLKEY="${PATRONI_REPLICATION_SSLKEY:-$PGSSLKEY}"
export PATRONI_REPLICATION_SSLCERT="${PATRONI_REPLICATION_SSLCERT:-$PGSSLCERT}"
export PATRONI_REPLICATION_SSLROOTCERT="${PATRONI_REPLICATION_SSLROOTCERT:-$PGSSLROOTCERT}"
export PATRONI_SUPERUSER_SSLMODE="${PATRONI_SUPERUSER_SSLMODE:-$PGSSLMODE}"
export PATRONI_SUPERUSER_SSLKEY="${PATRONI_SUPERUSER_SSLKEY:-$PGSSLKEY}"
export PATRONI_SUPERUSER_SSLCERT="${PATRONI_SUPERUSER_SSLCERT:-$PGSSLCERT}"
export PATRONI_SUPERUSER_SSLROOTCERT="${PATRONI_SUPERUSER_SSLROOTCERT:-$PGSSLROOTCERT}"

# Run pre-check to ensure data directory is valid
if ! check-db-dir "$PGDATA"; then
    # Create directory if it doesn't exist and set ownership/permissions.
    if [ "$(id -u)" -eq 0 ]; then
        mkdir -p "$PGDATA"
        chown postgres:postgres "$PGDATA"
        chmod 700 "$PGDATA"
        log_pgdata_info
    else
        # running as non-root (e.g. USER postgres). Try creating directory; if ownership or perms wrong, instruct user.
        if ! mkdir -p "$PGDATA" 2>/dev/null; then
            echo "ERROR: cannot create $PGDATA. Create it on the host and set owner to uid $(id -u postgres) gid $(id -g postgres) and mode 700"
            log_pgdata_info
            exit 1
        fi
        # best-effort to set permissions (may fail without root)
        chmod 700 "$PGDATA" 2>/dev/null || true
        log_pgdata_info
    fi
fi

# Start Postgres Pro 1C with specified config
# exec su - postgres -s /bin/bash -c "/opt/pgpro/1c-15/bin/postgres -D '$PGDATA' -c 'config_file=$PGDATA/postgresql.conf'"

# Start Patroni
exec dumb-init patroni patroni.yml