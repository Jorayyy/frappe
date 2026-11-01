#!/usr/bin/env bash
set -uo pipefail

sudo service mariadb start >/dev/null 2>&1 || (sudo mysqld_safe --user=mysql >/dev/null 2>&1 &)
sudo service redis-server start >/dev/null 2>&1 || true

for i in $(seq 1 30); do
  sudo mysqladmin ping >/dev/null 2>&1 && break
  sleep 2
done

cd "$HOME/frappe-bench"
bench use hrms.localhost >/dev/null 2>&1 || true
exec bench start
