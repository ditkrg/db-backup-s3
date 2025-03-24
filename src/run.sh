#! /bin/sh

set -eu

sh env.sh

if [ "$S3_S3V4" = "yes" ]; then
  aws configure set default.s3.signature_version s3v4
fi

if [ -z "$SCHEDULE" ]; then
  sh backup.sh
else
  # Use crond from busybox which is available in Alpine
  echo "$SCHEDULE /bin/sh $(pwd)/backup.sh" > /etc/crontabs/root
  # Start crond in foreground mode
  exec crond -f -d 8
fi
