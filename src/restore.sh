#! /bin/sh

set -u # `-e` omitted intentionally, but i can't remember why exactly :'(
set -o pipefail

source ./env.sh
source ./helpers.sh

s3_uri_base="s3://${S3_BUCKET}/${S3_PREFIX}"

echo "[restore] Pipeline: DATABASE_SERVER=${DATABASE_SERVER} HOST=${DATABASE_HOST}:${DATABASE_PORT} S3_URI_BASE=${s3_uri_base}/ DATABASE_NAMES_LIST=${DATABASE_NAMES_LIST}"

# MSSQL uses .bak extension, other databases use .dump
if [ "$DATABASE_SERVER" = "mssql" ]; then
  if [ -z "${PASSPHRASE:-}" ]; then
    file_type=".bak"
  else
    file_type=".bak.gpg"
  fi
else
  if [ -z "${PASSPHRASE:-}" ]; then
    file_type=".dump"
  else
    file_type=".dump.gpg"
  fi
fi

db_count=0
for _ in $DATABASE_NAMES_LIST; do
  db_count=$((db_count + 1))
done

if [ "$db_count" -gt 1 ] && [ -n "${RESTORE_BACKUP_FILENAME:-}" ]; then
  echo "RESTORE_BACKUP_FILENAME is not supported with multiple databases; unset it or configure a single database." >&2
  exit 1
fi

for CURRENT_DATABASE in $DATABASE_NAMES_LIST; do
  DATABASE_NAME="$CURRENT_DATABASE"
  unset MSSQL_RESTORE_BAK
  backup_file="${MSSQL_DATA_DIR}/db.bak"
  if [ "$DATABASE_SERVER" != "mssql" ]; then
    backup_file="db.dump"
  fi

  echo "=== Restoring database: $DATABASE_NAME ==="

  if restore_should_skip_target_database; then
    echo "[restore] Done with '${DATABASE_NAME}' (skipped — see messages above)."
    continue
  fi

  if [ $# -eq 1 ]; then
    timestamp="$1"
    key_suffix="${DATABASE_NAME}_${timestamp}${file_type}"
    echo "[restore] Using backup object from CLI argument (timestamp): ${s3_uri_base}/${key_suffix}"
  elif [ -n "${RESTORE_BACKUP_FILENAME:-}" ]; then
    key_suffix="${RESTORE_BACKUP_FILENAME}"
    echo "[restore] Using RESTORE_BACKUP_FILENAME as exact object key: ${s3_uri_base}/${key_suffix}"
  else
    echo "[restore] No timestamp argument or RESTORE_BACKUP_FILENAME; selecting latest object under ${s3_uri_base}/${DATABASE_NAME}/ ..."
    key_suffix=$(
      aws $aws_args s3 ls "${s3_uri_base}/${DATABASE_NAME}" \
        | sort \
        | tail -n 1 \
        | awk '{ print $4 }'
    )
    echo "[restore] Latest backup key for '${DATABASE_NAME}': ${key_suffix:-<none found>}"
  fi

  echo "[restore] Downloading from S3 then applying restore for '${DATABASE_NAME}' ..."
  if [ -n "${PASSPHRASE:-}" ]; then
    aws $aws_args s3 cp "${s3_uri_base}/${key_suffix}" "${backup_file}.gpg"
    echo "Decrypting backup..."
    gpg --decrypt --batch --passphrase "$PASSPHRASE" "${backup_file}.gpg" > "${backup_file}"
    rm -f "${backup_file}.gpg"
  else
    aws $aws_args s3 cp "${s3_uri_base}/${key_suffix}" "${backup_file}"
  fi

  echo "[restore] Backup file ready at '${backup_file}'; invoking restore() for ${DATABASE_SERVER}."
  restore

  if [ "$DATABASE_SERVER" != "mssql" ]; then
    rm -f "${backup_file}"
  fi

  echo "[restore] Finished restore step for '$DATABASE_NAME'."
done

echo "[restore] Restore pipeline finished for all databases in DATABASE_NAMES_LIST."
