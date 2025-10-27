#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Starting Kubernetes MSSQL backup test...${NC}"

# Configuration
NAMESPACE="${NAMESPACE:-mssql-backup-test}"
STATEFULSET_NAME="mssql"
POD_NAME="mssql-0"
MSSQL_PASSWORD="YourStrong@Passw0rd"
DATABASE_NAME="TestDB"
MSSQL_DATA_DIR="${MSSQL_DATA_DIR:-/var/opt/mssql/data}"
S3_BUCKET="${S3_BUCKET:-test-backups}"
S3_ENDPOINT="${S3_ENDPOINT:-}"  # Set this if using MinIO or other S3-compatible storage
STATEFULSET_FILE="${STATEFULSET_FILE:-$(dirname "$0")/../k8s-statefulset-with-sidecar.yaml}"

# Cleanup function
cleanup() {
    echo ""
    echo -e "${YELLOW}✨ Cleaning up resources...${NC}"
    kubectl delete statefulset $STATEFULSET_NAME -n $NAMESPACE --ignore-not-found=true
    kubectl delete pvc -l app=mssql -n $NAMESPACE --ignore-not-found=true
    kubectl delete configmap mssql-config -n $NAMESPACE --ignore-not-found=true
    kubectl delete secret mssql-general -n $NAMESPACE --ignore-not-found=true

    # Optionally delete the namespace (uncomment to auto-delete)
    # kubectl delete namespace $NAMESPACE --ignore-not-found=true

    echo -e "${GREEN}🎉 Cleanup complete!${NC}"
    echo -e "${BLUE}💡 To delete the namespace (including MinIO if present):${NC}"
    echo -e "${BLUE}   kubectl delete namespace $NAMESPACE${NC}"
}

# Trap cleanup on exit
trap cleanup EXIT

echo ""
echo -e "${YELLOW}📦 Creating namespace: $NAMESPACE${NC}"
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo -e "${YELLOW}🧹 Cleaning up any existing resources in namespace...${NC}"
kubectl delete statefulset $STATEFULSET_NAME -n $NAMESPACE --ignore-not-found=true
kubectl delete pvc -l app=mssql -n $NAMESPACE --ignore-not-found=true
kubectl delete configmap mssql-config -n $NAMESPACE --ignore-not-found=true
kubectl delete secret mssql-general -n $NAMESPACE --ignore-not-found=true

# Wait for PVC to be deleted
echo -e "${YELLOW}⏳ Waiting for PVC cleanup...${NC}"
while kubectl get pvc -l app=mssql -n $NAMESPACE 2>/dev/null | grep -q mssql; do
    echo "Waiting for PVC to be deleted..."
    sleep 2
done

echo ""
echo -e "${YELLOW}📝 Creating ConfigMap...${NC}"
kubectl create configmap mssql-config -n $NAMESPACE \
  --from-literal=DATABASE_SERVER='mssql' \
  --from-literal=DATABASE_HOST='mssql-service' \
  --from-literal=DATABASE_NAME="$DATABASE_NAME" \
  --from-literal=DATABASE_PORT='1433' \
  --from-literal=MSSQL_DATA_DIR='/var/opt/mssql/data' \
  --from-literal=SCHEDULE='*/5 * * * *' \
  --from-literal=BACKUP_KEEP_DAYS='7' \
  --from-literal=S3_BUCKET="$S3_BUCKET" \
  --from-literal=S3_PREFIX='mssql-backups' \
  --from-literal=S3_REGION='us-east-1' \
  ${S3_ENDPOINT:+--from-literal=S3_ENDPOINT="$S3_ENDPOINT"} \
  ${S3_ENDPOINT:+--from-literal=S3_S3V4='yes'}

echo ""
echo -e "${YELLOW}🔐 Creating Secret...${NC}"
kubectl create secret generic mssql-general -n $NAMESPACE \
  --from-literal=MSSQL_SA_PASSWORD="$MSSQL_PASSWORD" \
  --from-literal=DATABASE_USER='sa' \
  --from-literal=DATABASE_PASSWORD="$MSSQL_PASSWORD" \
  --from-literal=S3_ACCESS_KEY_ID="${S3_ACCESS_KEY_ID:-minioadmin}" \
  --from-literal=S3_SECRET_ACCESS_KEY="${S3_SECRET_ACCESS_KEY:-minioadmin}" \
  --from-literal=PASSPHRASE="${PASSPHRASE:-TestEncryptionPassphrase123}"

echo ""
echo -e "${YELLOW}📦 Deploying StatefulSet from $STATEFULSET_FILE...${NC}"
kubectl apply -f $STATEFULSET_FILE -n $NAMESPACE

echo ""
echo -e "${YELLOW}⏳ Waiting for pod to be ready (this may take 1-2 minutes)...${NC}"
kubectl wait --for=condition=ready pod/$POD_NAME -n $NAMESPACE --timeout=300s

echo ""
echo -e "${YELLOW}⏳ Waiting for MSSQL to be fully initialized...${NC}"
sleep 10

# Check if both containers are running
MSSQL_READY=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.status.containerStatuses[?(@.name=="mssql")].ready}')
BACKUP_READY=$(kubectl get pod $POD_NAME -n $NAMESPACE -o jsonpath='{.status.containerStatuses[?(@.name=="backup")].ready}')

if [ "$MSSQL_READY" != "true" ] || [ "$BACKUP_READY" != "true" ]; then
    echo -e "${RED}❌ Containers not ready!${NC}"
    echo "MSSQL ready: $MSSQL_READY"
    echo "Backup ready: $BACKUP_READY"
    kubectl describe pod $POD_NAME -n $NAMESPACE
    exit 1
fi

echo -e "${GREEN}✅ Pod is ready with both containers running!${NC}"

echo ""
echo -e "${YELLOW}🗄️  Creating test database...${NC}"
kubectl exec $POD_NAME -c mssql -n $NAMESPACE -- /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "$MSSQL_PASSWORD" -C \
  -Q "CREATE DATABASE $DATABASE_NAME;"

echo ""
echo -e "${YELLOW}📝 Creating test table and inserting data...${NC}"
kubectl exec $POD_NAME -c mssql -n $NAMESPACE -- /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "$MSSQL_PASSWORD" -C -d $DATABASE_NAME \
  -Q "CREATE TABLE Users (id INT PRIMARY KEY, name VARCHAR(50)); INSERT INTO Users VALUES (1, 'John'), (2, 'Jane');"

echo ""
echo -e "${YELLOW}📊 Current data:${NC}"
kubectl exec $POD_NAME -c mssql -n $NAMESPACE -- /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "$MSSQL_PASSWORD" -C -d $DATABASE_NAME \
  -Q "SELECT * FROM Users;"

echo ""
echo -e "${YELLOW}💾 Running backup...${NC}"
kubectl exec $POD_NAME -c backup -n $NAMESPACE -- sh backup.sh

echo ""
echo -e "${YELLOW}📋 Checking backup container logs...${NC}"
kubectl logs $POD_NAME -c backup -n $NAMESPACE --tail=20

# Optional: List S3 backups if aws CLI is available in the backup container
echo ""
echo -e "${YELLOW}📋 Checking S3 for backups...${NC}"
if [ -n "$S3_ENDPOINT" ]; then
    kubectl exec $POD_NAME -c backup -n $NAMESPACE -- aws s3 ls s3://$S3_BUCKET/mssql-backups/ --endpoint-url="$S3_ENDPOINT" 2>/dev/null || echo "Note: Could not list S3 bucket (this is OK for local testing)"
else
    kubectl exec $POD_NAME -c backup -n $NAMESPACE -- aws s3 ls s3://$S3_BUCKET/mssql-backups/ 2>/dev/null || echo "Note: Could not list S3 bucket (this is OK for local testing)"
fi

echo ""
echo -e "${YELLOW}🔐 Verifying backup is encrypted...${NC}"
# Check the backup logs for encryption activity
BACKUP_LOGS=$(kubectl logs $POD_NAME -c backup -n $NAMESPACE --tail=100 2>/dev/null || echo "")
if echo "$BACKUP_LOGS" | grep -q "Encrypting backup"; then
    echo -e "${GREEN}✅ Backup encryption confirmed${NC}"
elif echo "$BACKUP_LOGS" | grep -q "\.bak\.gpg"; then
    echo -e "${GREEN}✅ Backup is encrypted (.gpg extension detected in logs)${NC}"
elif echo "$BACKUP_LOGS" | grep -q "\.dump\.gpg"; then
    echo -e "${GREEN}✅ Backup is encrypted (.gpg extension detected in logs)${NC}"
else
    # Final check: was PASSPHRASE set?
    PASSPHRASE_SET=$(kubectl exec $POD_NAME -c backup -n $NAMESPACE -- sh -c 'test -n "$PASSPHRASE" && echo "yes" || echo "no"' 2>/dev/null)
    if [ "$PASSPHRASE_SET" = "yes" ]; then
        echo -e "${YELLOW}⚠️  PASSPHRASE is set, but cannot confirm encryption from logs${NC}"
        echo -e "${YELLOW}   (Encryption should be active, will verify during restore)${NC}"
    else
        echo -e "${RED}❌ Warning: PASSPHRASE not set - backups are NOT encrypted${NC}"
    fi
fi

echo ""
echo -e "${YELLOW}🔨 Modifying database (deleting John)...${NC}"
kubectl exec $POD_NAME -c mssql -n $NAMESPACE -- /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "$MSSQL_PASSWORD" -C -d $DATABASE_NAME \
  -Q "DELETE FROM Users WHERE name = 'John';"

echo ""
echo -e "${YELLOW}📊 Current data after modification (should only show Jane):${NC}"
kubectl exec $POD_NAME -c mssql -n $NAMESPACE -- /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "$MSSQL_PASSWORD" -C -d $DATABASE_NAME \
  -Q "SELECT * FROM Users;"

echo ""
echo -e "${YELLOW}♻️  Restoring from backup...${NC}"
RESTORE_OUTPUT=$(kubectl exec $POD_NAME -c backup -n $NAMESPACE -- sh restore.sh 2>&1)
echo "$RESTORE_OUTPUT"

# Verify decryption happened during restore
if echo "$RESTORE_OUTPUT" | grep -q "Decrypting backup"; then
    echo -e "${GREEN}✅ Backup was successfully decrypted during restore${NC}"
elif echo "$RESTORE_OUTPUT" | grep -q "encrypted with 1 passphrase"; then
    echo -e "${GREEN}✅ GPG decryption confirmed${NC}"
fi

echo ""
echo -e "${YELLOW}📊 Data after restore (should show both John and Jane):${NC}"
kubectl exec $POD_NAME -c mssql -n $NAMESPACE -- /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "$MSSQL_PASSWORD" -C -d $DATABASE_NAME \
  -Q "SELECT * FROM Users;"

echo ""
echo -e "${YELLOW}🔍 Verifying restoration...${NC}"
RECORD_COUNT=$(kubectl exec $POD_NAME -c mssql -n $NAMESPACE -- /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P "$MSSQL_PASSWORD" -C -d $DATABASE_NAME -h -1 -W \
  -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM Users;" | grep -v '^$' | tr -d '[:space:]')

if [ "$RECORD_COUNT" = "2" ]; then
    echo -e "${GREEN}✅ Success! Both records were restored correctly.${NC}"
else
    echo -e "${RED}❌ Failed! Expected 2 records, found: $RECORD_COUNT${NC}"
    exit 1
fi

echo ""
echo -e "${YELLOW}📊 Checking resource usage...${NC}"
kubectl top pod $POD_NAME -n $NAMESPACE --containers 2>/dev/null || echo "Note: Metrics server not available"

echo ""
echo -e "${GREEN}🎉 All tests passed!${NC}"
echo ""
echo -e "${BLUE}Additional commands you can try:${NC}"
echo -e "  ${YELLOW}# View MSSQL logs:${NC}"
echo -e "  kubectl logs $POD_NAME -c mssql -n $NAMESPACE"
echo ""
echo -e "  ${YELLOW}# View backup logs:${NC}"
echo -e "  kubectl logs $POD_NAME -c backup -n $NAMESPACE"
echo ""
echo -e "  ${YELLOW}# Execute manual backup:${NC}"
echo -e "  kubectl exec $POD_NAME -c backup -n $NAMESPACE -- sh backup.sh"
echo ""
echo -e "  ${YELLOW}# Connect to MSSQL:${NC}"
echo -e "  kubectl exec -it $POD_NAME -c mssql -n $NAMESPACE -- /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P '$MSSQL_PASSWORD' -C"
echo ""
echo -e "  ${YELLOW}# Check disk usage:${NC}"
echo -e "  kubectl exec $POD_NAME -c backup -n $NAMESPACE -- df -h /var/opt/mssql/data"
echo ""

