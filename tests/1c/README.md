# 1C Integration Test Harness

This directory contains a minimal 1C container setup for testing the project PostgreSQL/Patroni image from a 1C application server.

Expected baseline:

- `docker-compose.min.yml` is already running from the repository root.
- The PostgreSQL container is attached to the Docker network named `docker_default`.
- The PostgreSQL service is reachable from this compose file as `pg1:5432`.

Start 1C:

```powershell
docker compose -f tests/1c/docker-compose.yml up -d
```

The compose file uses a test entrypoint from `scripts/start-server.sh` instead of the image default entrypoint. The image default removes `/home/usr1cv8`, which makes `ragent` exit in this environment.

Create and publish a demo infobase:

```powershell
docker compose -f tests/1c/docker-compose.yml exec srv1c bash /opt/1c-tests/setup-demo.sh
```

The default web publication is available on host port `8080` under `/1cdb_demo`.

Clean up the demo infobase and its PostgreSQL database:

```powershell
docker compose -f tests/1c/docker-compose.yml exec srv1c bash /opt/1c-tests/cleanup-demo.sh
```

Stop 1C:

```powershell
docker compose -f tests/1c/docker-compose.yml down
```
