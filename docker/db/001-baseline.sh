#!/bin/bash
# Audit history rows are ~80% of the dump and unused locally; their tables are still created.
set -eo pipefail

gzip -dc /baseline/baseline.sql.gz \
  | LC_ALL=C grep -Ev '^INSERT INTO `(auditGeneric|auditFormData)' \
  | mariadb --protocol=socket --socket=/run/mysqld/mysqld.sock -uroot -p"$MARIADB_ROOT_PASSWORD" "$MARIADB_DATABASE"
