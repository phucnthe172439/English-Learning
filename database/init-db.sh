#!/bin/bash
# Runs inside the one-shot "db-init" container (see docker-compose.yml),
# after the "db" container reports healthy.
#
#   * No tables yet            -> run 01-schema.sql (one transaction: all tables or none).
#   * Some tables, not all     -> stop with an error: never guess on a half-built database.
#   * All tables, all empty    -> run 02-seed.sql (also covers a seed that failed last time).
#   * Tables with data         -> leave them alone (your data is never overwritten).
#   * Always                   -> run 03-app-login.sql (create or repair the API login).
set -euo pipefail

DB_NAME="EnglishVocabularyTraining"
TABLES="N'WordType', N'Topic', N'Vocabulary', N'Quiz', N'QuizQuestion'"
TABLE_COUNT=5

# -C: trust the server's self-signed certificate. -b: stop on the first SQL error.
run_sql() {
    /opt/mssql-tools18/bin/sqlcmd -S db -U sa -P "$MSSQL_SA_PASSWORD" -C -b "$@"
}

# Prints the single value returned by a query.
query() {
    run_sql -h -1 -W -Q "SET NOCOUNT ON; $1" | tr -d '[:space:]'
}

db_exists=$(query "SELECT COUNT(*) FROM sys.databases WHERE name = N'$DB_NAME'")
tables=0
if [ "$db_exists" = "1" ]; then
    tables=$(query "SELECT COUNT(*) FROM [$DB_NAME].sys.tables WHERE name IN ($TABLES)")
fi

if [ "$tables" = "0" ]; then
    echo "No tables in $DB_NAME: creating the schema..."
    run_sql -i /scripts/01-schema.sql
elif [ "$tables" != "$TABLE_COUNT" ]; then
    echo "ERROR: $DB_NAME has $tables of $TABLE_COUNT tables (half-built database)." >&2
    echo "       Fix it by hand, or start over with: docker compose down -v (deletes ALL data)." >&2
    exit 1
else
    echo "Schema already exists: skipping."
fi

rows=$(query "SELECT (SELECT COUNT(*) FROM [$DB_NAME].dbo.WordType)
                   + (SELECT COUNT(*) FROM [$DB_NAME].dbo.Topic)
                   + (SELECT COUNT(*) FROM [$DB_NAME].dbo.Vocabulary)")
if [ "$rows" = "0" ]; then
    echo "Tables are empty: adding seed data..."
    run_sql -i /scripts/02-seed.sql
else
    echo "Data already exists: skipping seed."
fi

# A ' in the password would end the SQL string early, so double it ('') as SQL expects.
echo "Creating/updating the english_app login..."
run_sql -v APP_DB_PASSWORD="${APP_DB_PASSWORD//\'/\'\'}" -i /scripts/03-app-login.sql

echo "Database is ready."
