#!/bin/bash
set -e  # Exit on error (but we'll handle specific commands)

echo "🚀 Starting test of MSSQL backup functionality..."

echo "🧹 Cleaning up any existing containers..."
docker compose down -v 2>/dev/null || true

echo "📦 Starting MinIO and MSSQL..."
docker compose up -d minio mssql

echo "⏳ Waiting for MinIO to be ready..."
for i in {1..10}; do
  if docker exec db-backup-s3-minio-1 mc alias set local http://localhost:9000 miniouser minioroot &>/dev/null; then
    echo "✅ MinIO is ready!"
    break
  fi
  echo -n "."
  sleep 1
done
echo ""

echo "📦 Creating backups bucket..."
docker exec db-backup-s3-minio-1 mc mb local/backups --ignore-existing || true

echo "⏳ Waiting for MSSQL to be ready (this takes about 30 seconds)..."
for i in {1..30}; do
  if docker exec db-backup-s3-mssql-1 /opt/mssql-tools18/bin/sqlcmd \
    -S localhost -U sa -P 'YourStrong@Passw0rd' -C \
    -Q "SELECT 1" &>/dev/null; then
    echo "✅ MSSQL is ready!"
    break
  fi
  echo -n "."
  sleep 1
done
echo ""

echo "🗄️  Creating test database..."
docker exec db-backup-s3-mssql-1 /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'YourStrong@Passw0rd' -C \
  -Q "CREATE DATABASE TestDB;"

echo "📝 Creating test table and inserting data..."
docker exec db-backup-s3-mssql-1 /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'YourStrong@Passw0rd' -C -d TestDB \
  -Q "CREATE TABLE Users (id INT, name VARCHAR(50)); INSERT INTO Users VALUES (1, 'John'), (2, 'Jane');"

echo "📊 Current data:"
docker exec db-backup-s3-mssql-1 /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'YourStrong@Passw0rd' -C -d TestDB \
  -Q "SELECT * FROM Users;"

echo ""
echo "💾 Running backup..."
docker compose run --rm backup-mssql sh backup.sh

echo ""
echo "📋 Checking MinIO for backup..."
echo "Backups in bucket:"
docker exec db-backup-s3-minio-1 mc ls local/backups/mssql-backups/

echo ""
echo "🔨 Modifying database (deleting John)..."
docker exec db-backup-s3-mssql-1 /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'YourStrong@Passw0rd' -C -d TestDB \
  -Q "DELETE FROM Users WHERE id = 1;"

echo "📊 Current data after modification (should only show Jane):"
docker exec db-backup-s3-mssql-1 /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'YourStrong@Passw0rd' -C -d TestDB \
  -Q "SELECT * FROM Users;"

echo ""
echo "♻️  Restoring from backup..."
docker compose run --rm backup-mssql sh restore.sh

echo ""
echo "📊 Data after restore (should show both John and Jane):"
docker exec db-backup-s3-mssql-1 /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'YourStrong@Passw0rd' -C -d TestDB \
  -Q "SELECT * FROM Users;"

echo ""
echo "✨ Test complete! Cleaning up..."
# docker compose down -v

echo "🎉 All done!"
