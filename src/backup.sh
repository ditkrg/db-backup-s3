#! /bin/sh

set -eu
set -o pipefail

source ./env.sh
source ./helpers.sh

echo "Creating backup of $DATABASE_NAME database..."
backup

timestamp=$(date +"%Y-%m-%dT%H:%M:%S")

# MSSQL uses .bak extension, other databases use .dump
if [ "$DATABASE_SERVER" = "mssql" ]; then
  local_file="${MSSQL_BACKUP_DIR}/db.bak"
  s3_uri_base="s3://${S3_BUCKET}/${S3_PREFIX}/${DATABASE_NAME}_${timestamp}.bak"
else
  local_file="db.dump"
  s3_uri_base="s3://${S3_BUCKET}/${S3_PREFIX}/${DATABASE_NAME}_${timestamp}.dump"
fi

if [ -n "$PASSPHRASE" ]; then
  echo "Encrypting backup..."
  gpg --symmetric --batch --passphrase "$PASSPHRASE" "$local_file"
  rm "$local_file"
  local_file="${local_file}.gpg"
  s3_uri="${s3_uri_base}.gpg"
else
  s3_uri="$s3_uri_base"
fi

echo "Uploading backup to $S3_BUCKET..."
aws $aws_args s3 cp "$local_file" "$s3_uri"
rm "$local_file"

echo "Backup complete."

if [ -n "$BACKUP_KEEP_DAYS" ]; then
  sec=$((86400*BACKUP_KEEP_DAYS))
  date_from_remove=$(date -d "@$(($(date +%s) - sec))" +%Y-%m-%d)
  backups_query="Contents[?LastModified<='${date_from_remove} 00:00:00'].{Key: Key}"

  echo "Removing old backups from $S3_BUCKET..."
  aws $aws_args s3api list-objects \
    --bucket "${S3_BUCKET}" \
    --prefix "${S3_PREFIX}" \
    --query "${backups_query}" \
    --output text \
    | xargs -n1 -t -I 'KEY' aws $aws_args s3 rm s3://"${S3_BUCKET}"/'KEY'
  echo "Removal complete."
fi
