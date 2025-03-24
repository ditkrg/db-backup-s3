

backup() {

    if [[ "$DATABASE_SERVER" == "postgres" ]]; then
        backup_postgres
    elif [[ "$DATABASE_SERVER" == "mariadb" ]]; then
        backup_mariadb
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
