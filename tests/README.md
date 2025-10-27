# Test Scripts

This directory contains automated test scripts for validating the backup and restore functionality across different environments.

## Files

### Docker Compose Tests
- **`test-mssql.sh`**: Tests MSSQL backup/restore using Docker Compose with local MinIO

### Kubernetes Tests
- **`test-mssql-k8s.sh`**: Tests MSSQL StatefulSet with backup sidecar (requires existing S3/MinIO)
- **`test-mssql-k8s-with-minio.sh`**: Complete automated test that deploys MinIO alongside MSSQL
- **`setup-minio-k8s.sh`**: Helper script to deploy MinIO in Kubernetes

### Kubernetes Configuration Examples
- **`k8s-statefulset-with-sidecar.yaml`**: Production-ready MSSQL StatefulSet with backup sidecar
- **`k8s-statefulset-test.yaml`**: Test StatefulSet configuration used by automated test scripts
- **`k8s-mssql-configmap-example.yaml`**: Example ConfigMap for non-sensitive configuration
- **`k8s-mssql-secret-example.yaml`**: Example Secret for sensitive credentials

## Usage

### Quick Start (Recommended)
Run the complete automated test with MinIO:
```bash
./tests/test-mssql-k8s-with-minio.sh
```

This will:
- Create a test namespace (`mssql-backup-test`)
- Deploy MinIO
- Deploy MSSQL StatefulSet with backup sidecar
- Run backup and restore tests
- Verify encryption is working

### Manual Kubernetes Test
If you have an existing S3 endpoint:
```bash
NAMESPACE=mssql-backup-test \
S3_ENDPOINT=http://your-s3:9000 \
S3_ACCESS_KEY_ID=your-key \
S3_SECRET_ACCESS_KEY=your-secret \
./tests/test-mssql-k8s.sh
```

### Docker Compose Test
```bash
./tests/test-mssql.sh
```

## Cleanup
Delete the test namespace to remove all resources:
```bash
kubectl delete namespace mssql-backup-test
```

