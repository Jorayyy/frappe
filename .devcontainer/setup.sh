#!/usr/bin/env bash
set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BENCH_DIR="$HOME/frappe-bench"
SITE="hrms.localhost"
DB_USER="frappe"
DB_PASS="frappe"

export DEBIAN_FRONTEND=noninteractive
export PATH="$HOME/.local/bin:$PATH"

echo "==> Installing system packages"
sudo apt-get update -qq
sudo apt-get install -y -qq \
  mariadb-server mariadb-client redis-server wkhtmltopdf \
  pkg-config libmariadb-dev libffi-dev libssl-dev build-essential \
  git curl xvfb libfontconfig1 fonts-liberation pipx

echo "==> Starting MariaDB and Redis"
sudo service mariadb start || (sudo mysqld_safe --user=mysql & sleep 8)
sudo service redis-server start || true
for i in $(seq 1 30); do
  sudo mysqladmin ping >/dev/null 2>&1 && break
  sleep 2
done

echo "==> Creating database user"
sudo mysql <<SQL
CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
CREATE USER IF NOT EXISTS '${DB_USER}'@'%' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON *.* TO '${DB_USER}'@'localhost' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO '${DB_USER}'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;
SQL

if ! command -v bench >/dev/null 2>&1; then
  echo "==> Installing frappe-bench"
  pipx install frappe-bench || python3 -m pip install --user frappe-bench
  export PATH="$HOME/.local/bin:$PATH"
fi

if [ ! -d "$BENCH_DIR" ]; then
  echo "==> Initializing bench (this takes a while)"
  PY="$(command -v python3.12 || command -v python3)"
  bench init --frappe-branch develop --python "$PY" --skip-redis-config-generation "$BENCH_DIR"
fi

cd "$BENCH_DIR"

if [ ! -d "apps/hrms" ]; then
  echo "==> Adding hrms from workspace"
  bench get-app "$SRC_DIR"
fi

if [ ! -d "apps/erpnext" ]; then
  echo "==> Adding erpnext"
  bench get-app --branch develop erpnext
fi

if ! bench --site "$SITE" list-apps >/dev/null 2>&1; then
  echo "==> Creating site $SITE"
  bench new-site "$SITE" \
    --db-root-username "$DB_USER" \
    --db-root-password "$DB_PASS" \
    --admin-password admin \
    --no-mariadb-socket
  bench --site "$SITE" install-app erpnext
  bench --site "$SITE" install-app hrms
fi

echo "==> Configuring site"
bench --site "$SITE" set-config developer_mode 1
bench --site "$SITE" set-config mute_emails 1
bench --site "$SITE" set-config socketio_port 9000
bench use "$SITE"
bench set-config -g serve_default_site true || true
bash -c 'python - "$HOME/frappe-bench/sites/common_site_config.json" <<PY
import json, sys
p = sys.argv[1]
with open(p) as f:
    cfg = json.load(f)
cfg["serve_default_site"] = True
cfg["developer_mode"] = 1
with open(p, "w") as f:
    json.dump(cfg, f, indent=1)
PY'

echo "==> Building assets"
bench build --app hrms >/dev/null 2>&1 || bench build >/dev/null 2>&1 || true

echo
echo "Setup complete. Start with: bash .devcontainer/start.sh"
echo "Site: http://localhost:8000  (user: Administrator / admin)"
