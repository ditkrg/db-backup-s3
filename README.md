# Introduction
This project provides Docker images to periodically back up a database to AWS S3, and to restore from the backup as needed.

Supported databases:
- PostgreSQL
- MariaDB/MySQL
- Microsoft SQL Server (MSSQL)

# Usage
## Backup
```yaml
services:
  postgres:
    image: postgres:13
    environment:
      DATABASE_USER: user
      DATABASE_PASSWORD: password

  backup:
    image: reg.dev.krd/db-backup-s3/db-backup-s3:alpine-3.21
    environment:
      SCHEDULE: '@weekly'     # optional
      BACKUP_KEEP_DAYS: 7     # optional
      PASSPHRASE: passphrase  # optional
      S3_REGION: region
      S3_ACCESS_KEY_ID: key
      S3_SECRET_ACCESS_KEY: secret
      S3_BUCKET: my-bucket
      S3_PREFIX: backup
      DATABASE_HOST: postgres
      DATABASE_NAME: dbname
      DATABASE_USER: user
      DATABASE_PASSWORD: password
      DATABASE_SERVER: postgres  # postgres, mariadb, or mssql
```

### MSSQL Example
**Note:** MSSQL backups use `sqlcmd` with the native `BACKUP DATABASE` command, which writes backup files server-side. This requires a shared volume between the MSSQL and backup containers.

```yaml
services:
  mssql:
    image: mcr.microsoft.com/mssql/server:2022-latest
    platform: linux/amd64  # Required for Apple Silicon Macs
    environment:
      ACCEPT_EULA: Y
      MSSQL_SA_PASSWORD: YourStrong@Passw0rd
      MSSQL_PID: Express
    volumes:
      - mssql-data:/var/opt/mssql  # Shared volume

  backup:
    image: reg.dev.krd/db-backup-s3/db-backup-s3:alpine-3.21
    platform: linux/amd64  # Required for Apple Silicon Macs
    volumes:
      - mssql-data:/var/opt/mssql  # Shared volume with MSSQL
    environment:
      SCHEDULE: '@daily'
      S3_REGION: us-east-1
      S3_ACCESS_KEY_ID: your_key
      S3_SECRET_ACCESS_KEY: your_secret
      S3_BUCKET: my-bucket
      S3_PREFIX: mssql-backup
      DATABASE_HOST: mssql
      DATABASE_PORT: 1433
      DATABASE_NAME: MyDatabase
      DATABASE_USER: sa
      DATABASE_PASSWORD: YourStrong@Passw0rd
      DATABASE_SERVER: mssql
      MSSQL_BACKUP_DIR: /var/opt/mssql/data  # Path where backups are stored

volumes:
  mssql-data:  # Shared volume for MSSQL data and backups
```

See [`docker-compose.yaml`](./docker-compose.yaml) for a complete working example.

- Images are tagged by the major PostgreSQL version supported: `11`, `12`, `13`, `14`, or `15`.
- The `SCHEDULE` variable determines backup frequency. See go-cron schedules documentation [here](http://godoc.org/github.com/robfig/cron#hdr-Predefined_schedules). Omit to run the backup immediately and then exit.
- If `PASSPHRASE` is provided, the backup will be encrypted using GPG.
- Run `docker exec <container name> sh backup.sh` to trigger a backup ad-hoc.
- If `BACKUP_KEEP_DAYS` is set, backups older than this many days will be deleted from S3.
- Set `S3_ENDPOINT` if you're using a non-AWS S3-compatible storage provider.

## Kubernetes Examples

### Standard CronJob (PostgreSQL, MariaDB)
PostgreSQL and MariaDB can use a standard Kubernetes CronJob since they use client-side backup tools (`pg_dump`, `mariadb-dump`) that don't require shared volumes:

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: postgres-backup
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: backup
            image: reg.dev.krd/db-backup-s3/db-backup-s3:alpine-3.21
            env:
            - name: DATABASE_SERVER
              value: "postgres"
            - name: DATABASE_HOST
              value: "postgres-service"
            - name: DATABASE_PORT
              value: "5432"
            - name: DATABASE_NAME
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: database
            - name: DATABASE_USER
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: username
            - name: DATABASE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: password
            - name: S3_REGION
              value: "us-east-1"
            - name: S3_ACCESS_KEY_ID
              valueFrom:
                secretKeyRef:
                  name: s3-credentials
                  key: access-key-id
            - name: S3_SECRET_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: s3-credentials
                  key: secret-access-key
            - name: S3_BUCKET
              value: "my-backups"
            - name: S3_PREFIX
              value: "postgres-backups"
            - name: BACKUP_KEEP_DAYS
              value: "7"
```

### MSSQL CronJob Example

> **Note:** For MSSQL StatefulSets with `ReadWriteOnce` volumes, use the [sidecar pattern](#mssql-with-statefulset-sidecar-pattern) instead. This CronJob example only works if you have a `ReadWriteMany` volume or a separate network-accessible MSSQL instance.

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: mssql-backup
spec:
  schedule: "0 2 * * *"  # Daily at 2 AM
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: backup
            image: reg.dev.krd/db-backup-s3/db-backup-s3:alpine-3.21
            env:
            - name: DATABASE_SERVER
              value: "mssql"
            - name: DATABASE_HOST
              value: "mssql-service"
            - name: DATABASE_PORT
              value: "1433"
            - name: DATABASE_NAME
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: database
            - name: DATABASE_USER
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: username
            - name: DATABASE_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: password
            - name: MSSQL_BACKUP_DIR
              value: "/var/opt/mssql/data"
            - name: S3_REGION
              value: "us-east-1"
            - name: S3_ACCESS_KEY_ID
              valueFrom:
                secretKeyRef:
                  name: s3-credentials
                  key: access-key-id
            - name: S3_SECRET_ACCESS_KEY
              valueFrom:
                secretKeyRef:
                  name: s3-credentials
                  key: secret-access-key
            - name: S3_BUCKET
              value: "my-backups"
            - name: S3_PREFIX
              value: "mssql-backups"
            - name: BACKUP_KEEP_DAYS
              value: "7"
            volumeMounts:
            - name: mssql-data
              mountPath: /var/opt/mssql/data
          volumes:
          - name: mssql-data
            persistentVolumeClaim:
              claimName: mssql-data-pvc  # Must be ReadWriteMany for CronJob
```

**Manual Backup Trigger:**
```bash
# Create a one-off job from the CronJob
kubectl create job --from=cronjob/mssql-backup manual-backup-$(date +%Y%m%d-%H%M%S)
```

### MSSQL with StatefulSet (Sidecar Pattern)

For MSSQL StatefulSets with `ReadWriteOnce` volumes, use the **sidecar pattern** instead of a CronJob. This allows the backup container to share the same volume as the database container, which is required for `sqlcmd`'s native `BACKUP DATABASE` command.

**Why Sidecar for MSSQL?**
- `ReadWriteOnce` volumes can only be mounted by one pod at a time
- MSSQL's `BACKUP DATABASE` writes files server-side to `/var/opt/mssql/data`
- A sidecar container in the same pod can access the same volume
- No need for complex volume mounting or client-side backup tools

**Example: StatefulSet with Backup Sidecar**

See [`k8s-statefulset-with-sidecar.yaml`](./k8s-statefulset-with-sidecar.yaml) for a complete example.

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mssql
spec:
  # ... (your existing StatefulSet config)
  template:
    spec:
      containers:
      # MSSQL Container
      - name: mssql
        image: mcr.microsoft.com/mssql/server:2022-CU14-ubuntu-22.04
        # ... (your existing MSSQL config)
        volumeMounts:
        - mountPath: /var/opt/mssql/data
          name: data

      # Backup Sidecar Container
      - name: backup
        image: ghcr.io/your-org/db-backup-s3:latest
        env:
        - name: SCHEDULE
          value: "0 2 * * *"  # Daily at 2 AM
        - name: DATABASE_SERVER
          value: "mssql"
        - name: DATABASE_HOST
          value: "localhost"  # Same pod
        - name: DATABASE_PORT
          value: "1433"
        - name: MSSQL_BACKUP_DIR
          value: "/var/opt/mssql/data"
        # ... (S3 and DB credentials from secrets)
        volumeMounts:
        - mountPath: /var/opt/mssql/data
          name: data  # Shared with MSSQL container
```

**Key Configuration:**
- `DATABASE_HOST: "localhost"` - Both containers are in the same pod
- `MSSQL_BACKUP_DIR: "/var/opt/mssql/data"` - Must match MSSQL's data directory
- Both containers mount the same volume at `/var/opt/mssql/data`
- Set `SCHEDULE` env var for automated backups (cron format)

**Trigger Manual Backup:**
```bash
# Execute backup in the sidecar container
kubectl exec -it mssql-0 -c backup -- sh backup.sh
```

**Restore from Backup:**
```bash
# Restore latest backup
kubectl exec -it mssql-0 -c backup -- sh restore.sh

# Restore specific backup by timestamp
kubectl exec -it mssql-0 -c backup -- sh restore.sh 2025-10-22T14:05:00
```

## Restore
> **WARNING:** DATA LOSS! All database objects will be dropped and re-created.
### ... from latest backup
```sh
docker exec <container name> sh restore.sh
```
> **NOTE:** If your bucket has more than a 1000 files, the latest may not be restored -- only one S3 `ls` command is used
### ... from specific backup
```sh
docker exec <container name> sh restore.sh <timestamp>
```

# Development
## Build the image locally
`ALPINE_VERSION` determines Postgres version compatibility. See [`build-and-push-images.yml`](.github/workflows/build-and-push-images.yml) for the latest mapping.
```sh
DOCKER_BUILDKIT=1 docker build --build-arg ALPINE_VERSION=3.14 .
```
## Run a simple test environment with Docker Compose
```sh
cp template.env .env
# fill out your secrets/params in .env
docker compose up -d
```

## Test Scripts

### Docker Compose
```sh
# Test MSSQL backup/restore with Docker Compose
./tests/test-mssql.sh
```

### Kubernetes (Recommended - Everything in One Namespace)
```sh
# Complete automated test with local MinIO
# Creates mssql-backup-test namespace with BOTH MinIO and MSSQL
./tests/test-mssql-k8s-with-minio.sh

# Manual test (if you already have S3/MinIO elsewhere)
NAMESPACE=mssql-backup-test S3_ENDPOINT=http://your-s3 ./tests/test-mssql-k8s.sh

# Clean up (removes everything - one command!)
kubectl delete namespace mssql-backup-test
```

**Architecture:** MinIO and MSSQL run in the same namespace for simplified networking and easy cleanup.

# Acknowledgements
This project is a fork and re-structuring @eeshugerman's fork of @schickling's [postgres-backup-s3](https://github.com/schickling/dockerfiles/tree/master/postgres-backup-s3) and [postgres-restore-s3](https://github.com/schickling/dockerfiles/tree/master/postgres-restore-s3).

## Fork goals
The fork by @eeshugerman works very well for postgres databases, the repo is intended to add support for different databases.
