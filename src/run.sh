#! /bin/sh

set -eu

sh env.sh

if [ "$S3_S3V4" = "yes" ]; then
  aws configure set default.s3.signature_version s3v4
fi

if [ -z "$SCHEDULE" ]; then
  sh backup.sh
else
  echo "Backup schedule configured: $SCHEDULE"
  echo "Starting go-cron..."

  # Use go-cron to run backup.sh on the specified schedule
  # go-cron takes schedule and command as arguments
  exec go-cron "$SCHEDULE" /bin/sh "$(pwd)/backup.sh"
fi
