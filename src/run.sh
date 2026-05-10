#! /bin/sh

set -eu

sh env.sh

if [ "$S3_S3V4" = "yes" ]; then
  aws configure set default.s3.signature_version s3v4
fi

if [ "${AUTO_RESTORE:-}" = "true" ] || [ "${AUTO_RESTORE:-}" = "1" ]; then
  echo "AUTO_RESTORE is enabled; restoring from S3..."
  sh restore.sh
fi

if [ -z "$SCHEDULE" ]; then
  if [ "${SKIP_STARTUP_BACKUP:-}" = "true" ] || [ "${SKIP_STARTUP_BACKUP:-}" = "1" ]; then
    echo "SKIP_STARTUP_BACKUP is set; not running backup.sh (no S3 upload from this path)."
  else
    sh backup.sh
  fi
else
  echo "Backup schedule configured: $SCHEDULE"
  echo "Starting go-cron..."

  # Use go-cron to run backup.sh on the specified schedule
  # go-cron takes schedule and command as arguments
  exec go-cron "$SCHEDULE" /bin/sh "$(pwd)/backup.sh"
fi
