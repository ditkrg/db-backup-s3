if [ -z "${S3_BUCKET:-}" ]; then
  echo "You need to set the S3_BUCKET environment variable."
  exit 1
fi

if [ -z "${DATABASE_SERVER:-}" ]; then
  echo "You need to set the DATABASE_SERVER environment variable. (postgres, mariadb, mssql)"
  exit 1
fi

database_names_env="${DATABASE_NAMES:-}"
database_name_env="${DATABASE_NAME:-}"

if [ -n "$database_names_env" ]; then
  sanitized_names=$(printf "%s" "$database_names_env" | tr ',' ' ')
  DATABASE_NAMES_LIST=$(printf "%s" "$sanitized_names" | awk '{$1=$1; print}')
else
  DATABASE_NAMES_LIST=""
fi

if [ -n "$database_name_env" ]; then
  if [ -z "$DATABASE_NAMES_LIST" ]; then
    DATABASE_NAMES_LIST="$database_name_env"
  fi
else
  if [ -z "$DATABASE_NAMES_LIST" ]; then
    echo "You need to set the DATABASE_NAME or DATABASE_NAMES environment variable."
    exit 1
  fi
fi

if [ -z "$database_name_env" ]; then
  for first_database in $DATABASE_NAMES_LIST; do
    DATABASE_NAME="$first_database"
    break
  done
else
  DATABASE_NAME="$database_name_env"
fi

export DATABASE_NAMES_LIST
export DATABASE_NAME

if [ -z "${DATABASE_HOST:-}" ]; then
  echo "You need to set the DATABASE_HOST environment variable."
  exit 1
fi

if [ -z "${DATABASE_PORT:-}" ]; then
  echo "You need to set the DATABASE_PORT environment variable."
  exit 1
fi

if [ -z "${DATABASE_USER:-}" ]; then
  echo "You need to set the DATABASE_USER environment variable."
  exit 1
fi

if [ -z "${DATABASE_PASSWORD:-}" ]; then
  echo "You need to set the DATABASE_PASSWORD environment variable."
  exit 1
fi

if [ -z "${S3_ENDPOINT:-}" ]; then
  echo "No S3_ENDPOINT set, using default aws region."
  aws_args=""
else
  aws_args="--endpoint-url $S3_ENDPOINT"
fi


if [ -n "${S3_ACCESS_KEY_ID:-}" ]; then
  export AWS_ACCESS_KEY_ID=$S3_ACCESS_KEY_ID
fi
if [ -n "${S3_SECRET_ACCESS_KEY:-}" ]; then
  export AWS_SECRET_ACCESS_KEY=$S3_SECRET_ACCESS_KEY
fi

export AWS_DEFAULT_REGION=$S3_REGION
export PGPASSWORD=$DATABASE_PASSWORD
