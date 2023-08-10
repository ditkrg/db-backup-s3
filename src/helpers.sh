

backup() {

    if [[ "$DATABASE_SERVER" == "postgres" ]]; then
        backup_postgres
    elif [[ "$DATABASE_SERVER" == "mysql" ]]; then
        backup_mysql
    else
        echo "Unknown database server: $DATABASE_SERVER"
        exit 1
    fi
}

restore() {
    if [[ "$DATABASE_SERVER" == "postgres" ]]; then
        restore_postgres
    elif [[ "$DATABASE_SERVER" == "mysql" ]]; then
        restore_mysql
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

backup_mysql() {
    mysqldump \
        --host "$DATABASE_HOST" \
        --port "$DATABASE_PORT" \
        --user "$DATABASE_USER" \
        --password="$DATABASE_PASSWORD" $MYSQLDUMP_EXTRA_OPTS \
        $DATABASE_NAME > db.dump
}

restore_mysql() {
    echo "Restoring from backup..."
    mysql \
        -h $DATABASE_HOST \
        -P $DATABASE_PORT \
        -u $DATABASE_USER \
        --password="$DATABASE_PASSWORD" \
        $DATABASE_NAME < db.dump
    rm db.dump
}
