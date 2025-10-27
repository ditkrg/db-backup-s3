

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
    conn_opts="-h $DATABASE_HOST -p $DATABASE_PORT -U $DATABASE_USER -d $DATABASE_NAME"
    pg_restore $conn_opts --clean --if-exists db.dump
}

backup_postgres() {
    pg_dump --format=custom \
        -h $DATABASE_HOST \
        -p $DATABASE_PORT \
        -U $DATABASE_USER \
        -d $DATABASE_NAME \
        $PGDUMP_EXTRA_OPTS > db.dump
}

backup_mariadb() {
    mariadb-dump \
        --host "$DATABASE_HOST" \
        --port "$DATABASE_PORT" \
        --user "$DATABASE_USER" \
        --password="$DATABASE_PASSWORD" "$MARIADB_DUMP_EXTRA_OPTS" \
        $DATABASE_NAME > db.dump
}

restore_mariadb() {
    echo "Restoring from backup..."
    mariadb \
        -h $DATABASE_HOST \
        -P $DATABASE_PORT \
        -u $DATABASE_USER \
        --password="$DATABASE_PASSWORD" "$MARIADB_EXTRA_OPTS" \
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
        $MSSQL_EXTRA_OPTS
}

restore_mssql() {
    echo "Restoring from backup..."
    # Get logical file names from the backup
    logical_files=$(sqlcmd -S ${DATABASE_HOST},${DATABASE_PORT} \
        -U ${DATABASE_USER} \
        -P "${DATABASE_PASSWORD}" \
        -C -W \
        -Q "SET NOCOUNT ON; RESTORE FILELISTONLY FROM DISK = N'${MSSQL_DATA_DIR}/db.bak';" \
        | grep -v '^$' | awk '{print $1}' | tail -n +3)

    # Parse logical names (first two lines after headers)
    data_file=$(echo "$logical_files" | sed -n '1p')
    log_file=$(echo "$logical_files" | sed -n '2p')

    # Restore database with MOVE options
    sqlcmd -S ${DATABASE_HOST},${DATABASE_PORT} \
        -U ${DATABASE_USER} \
        -P "${DATABASE_PASSWORD}" \
        -C \
        -Q "RESTORE DATABASE [${DATABASE_NAME}] FROM DISK = N'${MSSQL_DATA_DIR}/db.bak' WITH REPLACE, MOVE N'${data_file}' TO N'${MSSQL_DATA_DIR}/${DATABASE_NAME}.mdf', MOVE N'${log_file}' TO N'${MSSQL_DATA_DIR}/${DATABASE_NAME}_log.ldf';" \
        $MSSQL_EXTRA_OPTS

    # Clean up backup file
    rm "${MSSQL_DATA_DIR}/db.bak"
}
