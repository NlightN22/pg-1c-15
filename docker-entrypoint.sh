#!/bin/bash
set -e

readonly PGHOME=/var/lib/pgpro/1c-15
readonly PGDATA=$PGHOME/data

## We start an etcd
if [ -z "$PATRONI_ETCD3_HOSTS" ] && [ -z "$PATRONI_ZOOKEEPER_HOSTS" ]; then
    export PATRONI_ETCD_URL="http://127.0.0.1:2379"
    etcd --data-dir /tmp/etcd.data -advertise-client-urls=$PATRONI_ETCD_URL -listen-client-urls=http://0.0.0.0:2379 > /var/log/etcd.log 2> /var/log/etcd.err &
fi

# Set standard Patroni environment variables
export PATRONI_SCOPE=${PATRONI_SCOPE:-postgres-cluster}
export PATRONI_NAMESPACE=${PATRONI_NAMESPACE:-/db/}
export PATRONI_NAME=${PATRONI_NAME:-pg1}
export PATRONI_RESTAPI_LISTEN=${PATRONI_RESTAPI_LISTEN:-0.0.0.0:8008}
export PATRONI_RESTAPI_CONNECT_ADDRESS=${PATRONI_RESTAPI_CONNECT_ADDRESS:-pg1:8008}
export PATRONI_ETCD_HOST=${PATRONI_ETCD_HOST:-etcd:2379}
export PATRONI_POSTGRESQL_LISTEN=${PATRONI_POSTGRESQL_LISTEN:-0.0.0.0:5432}
export PATRONI_POSTGRESQL_CONNECT_ADDRESS=${PATRONI_POSTGRESQL_CONNECT_ADDRESS:-pg1:5432}
export PATRONI_POSTGRESQL_DATA_DIR=${PATRONI_POSTGRESQL_DATA_DIR:-/var/lib/pgpro/1c-15/data}

export DUMB_INIT_SETSID=0

# Run pre-check to ensure data directory is valid
check-db-dir "$PGDATA" || sudo initdb -D "$PGDATA" --locale=ru_RU.UTF-8

# Start Postgres Pro 1C with specified config
# exec su - postgres -s /bin/bash -c "/opt/pgpro/1c-15/bin/postgres -D '$PGDATA' -c 'config_file=$PGDATA/postgresql.conf'"

# Start Patroni
exec dumb-init patroni patroni.yml