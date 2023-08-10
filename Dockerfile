
# Download go-cron
ARG ALPINE_VERSION=3.18

FROM curlimages/curl AS go-cron-downloader
ARG GOCRON_VERSION=0.0.5
ARG TARGETARCH=amd64

RUN curl -sL https://github.com/ivoronin/go-cron/releases/download/v${GOCRON_VERSION}/go-cron_${GOCRON_VERSION}_linux_${TARGETARCH}.tar.gz -O
RUN tar xvf go-cron_${GOCRON_VERSION}_linux_${TARGETARCH}.tar.gz

FROM alpine:${ALPINE_VERSION}
ARG TARGETARCH=amd64
ARG DATABASE_SERVER=postgres

RUN apk update && \
    apk add --no-cache \
    gnupg \
    aws-cli

RUN if [[ "${DATABASE_SERVER}" == "mysql" ]]; then apk add --no-cache mysql-client mariadb-connector-c; fi
RUN if [[ "${DATABASE_SERVER}" == "postgres" ]]; then apk add --no-cache postgresql-client ; fi

RUN rm -rf /var/cache/apk/*

COPY --from=go-cron-downloader /home/curl_user/go-cron /usr/local/bin/go-cron

ENV DATABASE_NAME ''
ENV DATABASE_HOST ''
ENV DATABASE_PORT ''
ENV DATABASE_USER ''
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
ENV DATABASE_SERVER=${DATABASE_SERVER}

ADD src/run.sh run.sh
ADD src/env.sh env.sh
ADD src/backup.sh backup.sh
ADD src/helpers.sh helpers.sh
ADD src/restore.sh restore.sh

CMD ["sh", "run.sh"]
