## set rights to host directory:
```bash
docker compose run --rm --no-deps --entrypoint sh pg1 -c 'id -u postgres; id -g postgres'
chown -R 999:1000 /mnt/sdb1/pg1/data
```
## add pg_hba or edit other config:
connect to container, ex. `docker compose exec -it pg1 bash`
list nodes `patronictl list`
`patronictl show-config`
`patronictl edit-config`
restart `patronictl restart pg-cluster pg2`
reinit `patronictl reinit pg2`
switchover `patronictl switchover --candidate pg2`

## minimal worked config:
```yaml
loop_wait: 10
maximum_lag_on_failover: 1048576
postgresql:
  parameters:
    wal_level: replica
    max_wal_senders: 5
    max_replication_slots: 5
    hot_standby: "on"
    wal_keep_size: 1024MB
  pg_hba:
  - local all postgres peer
  - host replication replicator 127.0.0.1/32 md5
  - host replication replicator 172.21.0.0/16 md5
  - host all all 0.0.0.0/0 md5
  use_pg_rewind: true
retry_timeout: 10
ttl: 30
```

## recommended config:
```yaml
postgresql:
  parameters:
    max_connections: 100
    dynamic_shared_memory_type: posix
    seq_page_cost: 1.1
    random_page_cost: 1.1
    cpu_operator_cost: 0.0025
    logging_collector: on
    log_timezone: 'Asia/Krasnoyarsk'
    datestyle: 'iso, dmy'
    timezone: 'Asia/Krasnoyarsk'
    lc_messages: 'ru_RU.UTF-8'
    lc_monetary: 'ru_RU.UTF-8'
    lc_numeric: 'ru_RU.UTF-8'
    lc_time: 'ru_RU.UTF-8'
    default_text_search_config: 'pg_catalog.russian'
    temp_buffers: 128MB
    max_files_per_process: 10000
    commit_delay: 1000
    from_collapse_limit: 8
    join_collapse_limit: 8
    autovacuum_max_workers: 6
    vacuum_cost_limit: 2000
    autovacuum_naptime: 10s
    autovacuum_vacuum_scale_factor: 0.01
    autovacuum_analyze_scale_factor: 0.005
    max_locks_per_transaction: 512
    escape_string_warning: off
    standard_conforming_strings: off
    shared_preload_libraries: 'online_analyze, plantuner'
    online_analyze.threshold: 50
    online_analyze.scale_factor: 0.1
    online_analyze.enable: on
    online_analyze.verbose: off
    online_analyze.min_interval: 10000
    online_analyze.table_type: 'temporary'
    plantuner.fix_empty_table: on
    checkpoint_completion_target: 0.9
    wal_buffers: 16MB
    default_statistics_target: 500
    effective_io_concurrency: 200
    max_worker_processes: 12
    max_parallel_workers_per_gather: 6
    max_parallel_workers: 12
    max_parallel_maintenance_workers: 4
    # per node
    shared_buffers: 8GB
    effective_cache_size: 16GB
    maintenance_work_mem: 1GB
    work_mem: 14MB
    min_wal_size: 2GB
    max_wal_size: 16GB
    # AI recommends
    wal_level: replica
    checkpoint_timeout: 15min
    wal_compression: on
    wal_log_hints: on
    autovacuum_vacuum_cost_limit: 2500
    autovacuum_work_mem: 1GB
    hot_standby_feedback: on
```