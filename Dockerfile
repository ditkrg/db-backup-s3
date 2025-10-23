ARG ALPINE_VERSION=3.21

FROM alpine:${ALPINE_VERSION}

WORKDIR /

# Install tools for PostgreSQL, MariaDB, and AWS CLI
RUN apk update && \
    apk add --no-cache \
    gnupg \
    aws-cli \
    postgresql-client \
    mysql-client mariadb-connector-c \
    curl

# Install MSSQL tools (sqlcmd) for Microsoft SQL Server on Alpine
# Source: https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-setup-tools
RUN curl -O https://download.microsoft.com/download/b/9/f/b9f3cce4-3925-46d4-9f46-da08869c6486/msodbcsql18_18.1.1.1-1_amd64.apk && \
    curl -O https://download.microsoft.com/download/b/9/f/b9f3cce4-3925-46d4-9f46-da08869c6486/mssql-tools18_18.1.1.1-1_amd64.apk && \
    apk add --allow-untrusted msodbcsql18_18.1.1.1-1_amd64.apk && \
    apk add --allow-untrusted mssql-tools18_18.1.1.1-1_amd64.apk && \
    rm msodbcsql18_18.1.1.1-1_amd64.apk mssql-tools18_18.1.1.1-1_amd64.apk

RUN rm -rf /var/cache/apk/*

ENV PATH="${PATH}:/opt/mssql-tools18/bin"

ENV DATABASE_NAME ''
ENV DATABASE_HOST ''
ENV DATABASE_PORT ''
ENV DATABASE_USER ''
ENV DATABASE_SERVER ''
ENV DATABASE_PASSWORD ''
ENV PGDUMP_EXTRA_OPTS ''
ENV MARIADB_DUMP_EXTRA_OPTS ''
ENV MARIADB_EXTRA_OPTS ''
ENV MSSQL_EXTRA_OPTS ''
ENV MSSQL_BACKUP_DIR '/var/opt/mssql/data'
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
