
# Download go-cron
ARG ALPINE_VERSION=3.18

FROM curlimages/curl AS go-cron-downloader
ARG GOCRON_VERSION=0.0.5

RUN curl -sL https://github.com/ivoronin/go-cron/releases/download/v${GOCRON_VERSION}/go-cron_${GOCRON_VERSION}_linux_amd64.tar.gz -O
RUN tar xvf go-cron_${GOCRON_VERSION}_linux_amd64.tar.gz

FROM alpine:${ALPINE_VERSION}

RUN apk update && \
    apk add --no-cache \
    gnupg \
    aws-cli \
    postgresql-client \
    mysql-client mariadb-connector-c

RUN rm -rf /var/cache/apk/*

COPY --from=go-cron-downloader /home/curl_user/go-cron /usr/local/bin/go-cron

ENV DATABASE_NAME ''
ENV DATABASE_HOST ''
ENV DATABASE_PORT ''
ENV DATABASE_USER ''
ENV DATABASE_SERVER ''
ENV DATABASE_PASSWORD ''
ENV PGDUMP_EXTRA_OPTS ''
ENV MYSQLDUMP_EXTRA_OPTS ''
ENV S3_ACCESS_KEY_ID ''
ENV S3_SECRET_ACCESS_KEY ''
ENV S3_BUCKET ''
ENV S3_REGION 'us-west-1'
ENV S3_PATH 'backup'
ENV S3_ENDPOINT ''
ENV S3_S3V4 'no'
ENV SCHEDULE ''
ENV PASSPHRASE ''
ENV BACKUP_KEEP_DAYS ''

ADD src/run.sh run.sh
ADD src/env.sh env.sh
ADD src/backup.sh backup.sh
ADD src/helpers.sh helpers.sh
ADD src/restore.sh restore.sh

CMD ["sh", "run.sh"]
