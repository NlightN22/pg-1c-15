## add pg_hba or edit other config:
list nodes `patronictl list`
edit config `patronictl edit-config`
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
    max_wal_senders: 16
    max_replication_slots: 16
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