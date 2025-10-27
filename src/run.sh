#! /bin/sh

set -eu

sh env.sh

if [ "$S3_S3V4" = "yes" ]; then
  aws configure set default.s3.signature_version s3v4
fi

if [ -z "$SCHEDULE" ]; then
  sh backup.sh
else
  # For non-root users, use a writable directory for crontabs
  # busybox crond supports -c option to specify crontab directory
  CRON_USER=$(id -u)
  CRON_DIR="${HOME}/crontabs"

  # Create crontab directory
  mkdir -p "$CRON_DIR"

  # Write crontab entry
  echo "$SCHEDULE /bin/sh $(pwd)/backup.sh" > "$CRON_DIR/$CRON_USER"
  chmod 600 "$CRON_DIR/$CRON_USER"

  echo "Backup schedule configured: $SCHEDULE"
  echo "Crontab file: $CRON_DIR/$CRON_USER"
  echo "Starting crond..."

  # Start crond in foreground mode with custom crontab directory
  exec crond -f -d 8 -c "$CRON_DIR"
fi
