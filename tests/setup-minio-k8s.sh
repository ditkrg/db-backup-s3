#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Setting up MinIO in Kubernetes for testing...${NC}"

MINIO_NAMESPACE="${NAMESPACE:-mssql-backup-test}"
MINIO_USER="minioadmin"
MINIO_PASSWORD="minioadmin"
BUCKET_NAME="backups"

echo ""
echo -e "${YELLOW}📦 Creating namespace: $MINIO_NAMESPACE${NC}"
kubectl create namespace $MINIO_NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo -e "${YELLOW}🗄️  Deploying MinIO...${NC}"
kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: minio
  namespace: $MINIO_NAMESPACE
  labels:
    app: minio
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: minio
    image: minio/minio:latest
    args:
    - server
    - /data
    - --console-address
    - :9001
    ports:
    - containerPort: 9000
      name: api
    - containerPort: 9001
      name: console
    env:
    - name: MINIO_ROOT_USER
      value: "$MINIO_USER"
    - name: MINIO_ROOT_PASSWORD
      value: "$MINIO_PASSWORD"
    securityContext:
      allowPrivilegeEscalation: false
      capabilities:
        drop:
        - ALL
      readOnlyRootFilesystem: false
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: minio
  namespace: $MINIO_NAMESPACE
spec:
  type: ClusterIP
  ports:
  - port: 9000
    targetPort: 9000
    name: api
  - port: 9001
    targetPort: 9001
    name: console
  selector:
    app: minio
EOF

echo ""
echo -e "${YELLOW}⏳ Waiting for MinIO to be ready...${NC}"
kubectl wait --for=condition=ready pod/minio -n $MINIO_NAMESPACE --timeout=120s

echo ""
echo -e "${YELLOW}⏳ Waiting for MinIO to start (5 seconds)...${NC}"
sleep 5

echo ""
echo -e "${YELLOW}📦 Creating bucket: $BUCKET_NAME${NC}"
kubectl exec -n $MINIO_NAMESPACE minio -- sh -c "
  mc alias set local http://localhost:9000 $MINIO_USER $MINIO_PASSWORD && \
  mc mb local/$BUCKET_NAME --ignore-existing && \
  mc ls local/
"

echo ""
echo -e "${GREEN}✅ MinIO is ready!${NC}"
echo ""
echo -e "${BLUE}MinIO Details:${NC}"
echo -e "  Namespace:      $MINIO_NAMESPACE"
echo -e "  Service:        minio:9000 (within namespace)"
echo -e "  Full Service:   minio.$MINIO_NAMESPACE.svc.cluster.local:9000"
echo -e "  Access Key:     $MINIO_USER"
echo -e "  Secret Key:     $MINIO_PASSWORD"
echo -e "  Bucket:         $BUCKET_NAME"
echo ""
echo -e "${BLUE}To access MinIO Console:${NC}"
echo -e "  kubectl port-forward -n $MINIO_NAMESPACE pod/minio 9001:9001"
echo -e "  Then open: http://localhost:9001"
echo ""
echo -e "${BLUE}To run the MSSQL backup test (same namespace):${NC}"
echo -e "  NAMESPACE=$MINIO_NAMESPACE \\"
echo -e "  S3_ENDPOINT=http://minio:9000 \\"
echo -e "  S3_ACCESS_KEY_ID=$MINIO_USER \\"
echo -e "  S3_SECRET_ACCESS_KEY=$MINIO_PASSWORD \\"
echo -e "  S3_BUCKET=$BUCKET_NAME \\"
echo -e "  ./test-mssql-k8s.sh"
echo ""

