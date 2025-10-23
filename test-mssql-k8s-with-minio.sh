#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Complete MSSQL Backup Test with MinIO${NC}"
echo -e "${BLUE}=========================================${NC}"
echo ""

# Use same namespace for everything
TEST_NAMESPACE="${NAMESPACE:-mssql-backup-test}"
MINIO_USER="minioadmin"
MINIO_PASSWORD="minioadmin"
BUCKET_NAME="backups"
MINIO_ENDPOINT="http://minio:9000"  # Simple service name (same namespace)

echo -e "${GREEN}📦 Test Configuration:${NC}"
echo -e "  Namespace:       ${YELLOW}$TEST_NAMESPACE${NC}"
echo -e "  Resources:       MinIO + MSSQL (both in same namespace)"
echo -e "  S3 Endpoint:     $MINIO_ENDPOINT"
echo ""

# Check if MinIO is already running
MINIO_EXISTS=$(kubectl get pod minio -n $TEST_NAMESPACE 2>/dev/null | grep -c "minio" || true)

if [ "$MINIO_EXISTS" -eq 0 ]; then
    echo -e "${YELLOW}📦 MinIO not found. Deploying MinIO in $TEST_NAMESPACE...${NC}"
    NAMESPACE=$TEST_NAMESPACE ./setup-minio-k8s.sh
else
    echo -e "${GREEN}✅ MinIO already running in $TEST_NAMESPACE namespace${NC}"

    # Verify MinIO is ready
    echo -e "${YELLOW}⏳ Checking MinIO status...${NC}"
    kubectl wait --for=condition=ready pod/minio -n $TEST_NAMESPACE --timeout=60s

    # Ensure bucket exists
    echo -e "${YELLOW}📦 Ensuring bucket exists: $BUCKET_NAME${NC}"
    kubectl exec -n $TEST_NAMESPACE minio -- sh -c "
      mc alias set local http://localhost:9000 $MINIO_USER $MINIO_PASSWORD 2>/dev/null && \
      mc mb local/$BUCKET_NAME --ignore-existing 2>/dev/null
    " || echo "Bucket already exists or created"
fi

echo ""
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}🧪 Running MSSQL Backup Test${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# Run the test with MinIO configuration (same namespace)
NAMESPACE="$TEST_NAMESPACE" \
STATEFULSET_FILE="k8s-statefulset-test.yaml" \
S3_ENDPOINT="$MINIO_ENDPOINT" \
S3_ACCESS_KEY_ID="$MINIO_USER" \
S3_SECRET_ACCESS_KEY="$MINIO_PASSWORD" \
S3_BUCKET="$BUCKET_NAME" \
./test-mssql-k8s.sh

echo ""
echo -e "${GREEN}🎉 All tests completed successfully!${NC}"
echo ""
echo -e "${BLUE}📊 View backups in MinIO:${NC}"
echo -e "  kubectl exec -n $TEST_NAMESPACE minio -- mc ls local/$BUCKET_NAME/mssql-backups/"
echo ""
echo -e "${BLUE}🌐 Access MinIO Console:${NC}"
echo -e "  kubectl port-forward -n $TEST_NAMESPACE pod/minio 9001:9001"
echo -e "  Then open: http://localhost:9001"
echo -e "  Login: $MINIO_USER / $MINIO_PASSWORD"
echo ""
echo -e "${BLUE}🧹 Cleanup (everything in one namespace):${NC}"
echo -e "  kubectl delete namespace $TEST_NAMESPACE"
echo ""

