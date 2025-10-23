#! /bin/sh

set -u # `-e` omitted intentionally, but i can't remember why exactly :'(
set -o pipefail

source ./env.sh
source ./helpers.sh

s3_uri_base="s3://${S3_BUCKET}/${S3_PREFIX}"

# MSSQL uses .bak extension, other databases use .dump
if [ "$DATABASE_SERVER" = "mssql" ]; then
  backup_file="${MSSQL_BACKUP_DIR}/db.bak"
  if [ -z "$PASSPHRASE" ]; then
    file_type=".bak"
  else
    file_type=".bak.gpg"
  fi
else
  backup_file="db.dump"
  if [ -z "$PASSPHRASE" ]; then
    file_type=".dump"
  else
    file_type=".dump.gpg"
  fi
fi

if [ $# -eq 1 ]; then
  timestamp="$1"
  key_suffix="${DATABASE_NAME}_${timestamp}${file_type}"
else
  echo "Finding latest backup..."
  key_suffix=$(
    aws $aws_args s3 ls "${s3_uri_base}/${DATABASE_NAME}" \
      | sort \
      | tail -n 1 \
      | awk '{ print $4 }'
  )
fi

echo "Fetching backup from S3..."
if [ -n "$PASSPHRASE" ]; then
  aws $aws_args s3 cp "${s3_uri_base}/${key_suffix}" "${backup_file}.gpg"
  echo "Decrypting backup..."
  gpg --decrypt --batch --passphrase "$PASSPHRASE" "${backup_file}.gpg" > "${backup_file}"
  rm "${backup_file}.gpg"
else
  aws $aws_args s3 cp "${s3_uri_base}/${key_suffix}" "${backup_file}"
fi

echo "Restoring from backup..."
restore

# Clean up backup file
# Note: For MSSQL, the file is in MSSQL_BACKUP_DIR and cleanup happens in restore_mssql()
if [ "$DATABASE_SERVER" != "mssql" ]; then
  rm "${backup_file}"
fi

echo "Restore complete."
