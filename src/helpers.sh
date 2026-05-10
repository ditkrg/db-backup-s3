
# Returns 0 = skip restore (target database already exists), 1 = proceed with restore.
# Runs only when AUTO_RESTORE is true|1 (same env as run.sh uses for startup restore). Otherwise always proceeds.
restore_should_skip_target_database() {
    case "${AUTO_RESTORE:-}" in true|1)
        echo "[restore] AUTO_RESTORE is enabled: checking whether database '${DATABASE_NAME}' already exists before restoring."
        ;;
    *)
        echo "[restore] AUTO_RESTORE is '${AUTO_RESTORE:-}' (not true/1): skip-if-exists logic is off — will restore from backup source."
        return 1
        ;;
    esac
    if [[ "$DATABASE_SERVER" == "postgres" ]]; then
        restore_postgres_should_skip
    elif [[ "$DATABASE_SERVER" == "mariadb" ]]; then
        restore_mariadb_should_skip
    elif [[ "$DATABASE_SERVER" == "mssql" ]]; then
        restore_mssql_should_skip
    else
        echo "[restore] DATABASE_SERVER='${DATABASE_SERVER}' has no skip check — proceeding with restore."
        return 1
    fi
}

restore_mssql_should_skip() {
    # 1 = database exists -> skip restore
    val=$(
        sqlcmd -S "${DATABASE_HOST},${DATABASE_PORT}" \
            -U "${DATABASE_USER}" \
            -P "${DATABASE_PASSWORD}" \
            -C -h-1 -W -Q "SET NOCOUNT ON;
DECLARE @db sysname = N'${DATABASE_NAME}';
SELECT CASE WHEN DB_ID(@db) IS NOT NULL THEN 1 ELSE 0 END;" 2>/dev/null | tr -d '\r' | tail -n 1 | tr -d '[:space:]'
    ) || val=""
    if [ -z "$val" ]; then
        echo "[restore] MSSQL: could not read database existence (sqlcmd failed or empty result); proceeding with restore." >&2
        return 1
    fi
    case "$val" in 1)
        echo "[restore] MSSQL: database '${DATABASE_NAME}' already exists on ${DATABASE_HOST},${DATABASE_PORT} — skipping restore."
        return 0
        ;;
    *)
        echo "[restore] MSSQL: database '${DATABASE_NAME}' does not exist yet — restore from backup is required."
        return 1
        ;;
    esac
}

restore_postgres_should_skip() {
    val=$(
        PGPASSWORD="$DATABASE_PASSWORD" psql -h "$DATABASE_HOST" -p "$DATABASE_PORT" -U "$DATABASE_USER" -d postgres -t -A -c \
            "SELECT CASE WHEN EXISTS (
               SELECT 1 FROM pg_database WHERE datname = '$DATABASE_NAME') THEN 1 ELSE 0 END;" 2>/dev/null | tr -d '[:space:]'
    ) || val=""
    if [ -z "$val" ]; then
        echo "[restore] PostgreSQL: could not query pg_database (psql failed); proceeding with restore." >&2
        return 1
    fi
    case "$val" in 1)
        echo "[restore] PostgreSQL: database '${DATABASE_NAME}' already exists — skipping restore."
        return 0
        ;;
    *)
        echo "[restore] PostgreSQL: database '${DATABASE_NAME}' does not exist — restore from backup is required."
        return 1
        ;;
    esac
}

restore_mariadb_should_skip() {
    val=$(
        mariadb -N -h "$DATABASE_HOST" -P "$DATABASE_PORT" -u "$DATABASE_USER" --password="$DATABASE_PASSWORD" \
            -e \
            "SELECT CASE WHEN EXISTS (
               SELECT 1 FROM information_schema.schemata WHERE schema_name = '$DATABASE_NAME') THEN 1 ELSE 0 END;" 2>/dev/null | tr -d '[:space:]'
    ) || val=""
    if [ -z "$val" ]; then
        echo "[restore] MariaDB: could not query information_schema (client failed); proceeding with restore." >&2
        return 1
    fi
    case "$val" in 1)
        echo "[restore] MariaDB: schema/database '${DATABASE_NAME}' already exists — skipping restore."
        return 0
        ;;
    *)
        echo "[restore] MariaDB: schema/database '${DATABASE_NAME}' does not exist — restore from backup is required."
        return 1
        ;;
    esac
}

backup() {

    if [[ "$DATABASE_SERVER" == "postgres" ]]; then
        backup_postgres
    elif [[ "$DATABASE_SERVER" == "mariadb" ]]; then
        backup_mariadb
    elif [[ "$DATABASE_SERVER" == "mssql" ]]; then
        backup_mssql
    else
        echo "Unknown database server: $DATABASE_SERVER"
        exit 1
    fi
}

restore() {
    if [[ "$DATABASE_SERVER" == "postgres" ]]; then
        restore_postgres
    elif [[ "$DATABASE_SERVER" == "mariadb" ]]; then
        restore_mariadb
    elif [[ "$DATABASE_SERVER" == "mssql" ]]; then
        restore_mssql
    else
        echo "Unknown database server: $DATABASE_SERVER"
        exit 1
    fi
}

restore_postgres() {
    echo "[restore] Running pg_restore into database '${DATABASE_NAME}' on ${DATABASE_HOST}:${DATABASE_PORT}."
    conn_opts="-h $DATABASE_HOST -p $DATABASE_PORT -U $DATABASE_USER -d $DATABASE_NAME"
    pg_restore $conn_opts --clean --if-exists db.dump
}

backup_postgres() {
    pg_dump --format=custom \
        -h $DATABASE_HOST \
        -p $DATABASE_PORT \
        -U $DATABASE_USER \
        -d $DATABASE_NAME \
        ${PGDUMP_EXTRA_OPTS:-} > db.dump
}

backup_mariadb() {
    mariadb-dump \
        --host "$DATABASE_HOST" \
        --port "$DATABASE_PORT" \
        --user "$DATABASE_USER" \
        --password="$DATABASE_PASSWORD" ${MARIADB_DUMP_EXTRA_OPTS:-} \
        $DATABASE_NAME > db.dump
}

restore_mariadb() {
    echo "[restore] Importing dump into schema/database '${DATABASE_NAME}' on ${DATABASE_HOST}:${DATABASE_PORT}."
    mariadb \
        -h $DATABASE_HOST \
        -P $DATABASE_PORT \
        -u $DATABASE_USER \
        --password="$DATABASE_PASSWORD" ${MARIADB_EXTRA_OPTS:-} \
        $DATABASE_NAME < db.dump
}

backup_mssql() {
    # Use native BACKUP DATABASE command
    # Note: Requires shared volume mounted at MSSQL_DATA_DIR
    sqlcmd -S ${DATABASE_HOST},${DATABASE_PORT} \
        -U ${DATABASE_USER} \
        -P "${DATABASE_PASSWORD}" \
        -C \
        -Q "BACKUP DATABASE [${DATABASE_NAME}] TO DISK = N'${MSSQL_DATA_DIR}/db.bak' WITH INIT;" \
        ${MSSQL_EXTRA_OPTS:-}
}

restore_mssql() {
    mssql_bak_path="${MSSQL_RESTORE_BAK:-${MSSQL_DATA_DIR}/db.bak}"
    echo "[restore] Running SQL Server RESTORE for [${DATABASE_NAME}] from '${mssql_bak_path}' (target data files under '${MSSQL_DATA_DIR}')."
    # Get logical file names from the backup
    logical_files=$(sqlcmd -S ${DATABASE_HOST},${DATABASE_PORT} \
        -U ${DATABASE_USER} \
        -P "${DATABASE_PASSWORD}" \
        -C -W \
        -Q "SET NOCOUNT ON; RESTORE FILELISTONLY FROM DISK = N'${mssql_bak_path}';" \
        | grep -v '^$' | awk '{print $1}' | tail -n +3)

    # Parse logical names (first two lines after headers)
    data_file=$(echo "$logical_files" | sed -n '1p')
    log_file=$(echo "$logical_files" | sed -n '2p')

    # Restore database with MOVE options
    sqlcmd -S ${DATABASE_HOST},${DATABASE_PORT} \
        -U ${DATABASE_USER} \
        -P "${DATABASE_PASSWORD}" \
        -C \
        -Q "RESTORE DATABASE [${DATABASE_NAME}] FROM DISK = N'${mssql_bak_path}' WITH REPLACE, MOVE N'${data_file}' TO N'${MSSQL_DATA_DIR}/${DATABASE_NAME}.mdf', MOVE N'${log_file}' TO N'${MSSQL_DATA_DIR}/${DATABASE_NAME}_log.ldf';" \
        ${MSSQL_EXTRA_OPTS:-}

    # Clean up backup file
    rm -f "${mssql_bak_path}"
}
