#!/bin/bash
set -e

echo "=== UPDATE SYSTEM ==="
apt update -y && apt upgrade -y

echo "=== INSTALL DEPENDENCIES ==="
apt install -y python3.10 python3.10-dev python3-venv python3-pip build-essential \
libssl-dev libffi-dev pkg-config libmysqlclient-dev curl mysql-server

echo "=== CONFIGURE MYSQL & DATABASE ==="
mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY 'SupersetDBpass123!';"
mysql -uroot -pSupersetDBpass123! -e "CREATE DATABASE superset DEFAULT CHARACTER SET utf8mb4 DEFAULT COLLATE utf8mb4_unicode_ci;"
mysql -uroot -pSupersetDBpass123! -e "CREATE USER 'superset'@'localhost' IDENTIFIED BY 'SupersetDBpass123!';"
mysql -uroot -pSupersetDBpass123! -e "GRANT ALL PRIVILEGES ON superset.* TO 'superset'@'localhost'; FLUSH PRIVILEGES;"

echo "=== CREATE SUPERSET USER ==="
useradd -m -s /bin/bash superset || true
mkdir -p /home/superset/.superset/cache
chown -R superset:superset /home/superset

echo "=== CREATE PYTHON VENV & INSTALL SUPERSET ==="
sudo -u superset bash <<'EOF'
cd /home/superset
python3 -m venv superset-venv
source superset-venv/bin/activate

pip install --upgrade pip setuptools wheel
pip install "marshmallow<4.0.0" "marshmallow-enum<2.0.0"

pip install apache-superset==4.1.4 mysqlclient
EOF

echo "=== CREATE SUPERSET CONFIG ==="
cat <<'EOF' >/home/superset/.superset/superset_config.py
from cachelib.file import FileSystemCache

SECRET_KEY = "supersecret_long_key_123456789$(openssl rand -hex 16)"

SQLALCHEMY_DATABASE_URI = "mysql://superset:SupersetDBpass123!@localhost/superset"

CACHE_CONFIG = {
  "CACHE_TYPE": "FileSystemCache",
  "CACHE_DIR": "/home/superset/.superset/cache",
}
EOF

chown -R superset:superset /home/superset/.superset

echo "=== INITIALIZING SUPERSET ==="
sudo -u superset bash <<'EOF'
source /home/superset/superset-venv/bin/activate
export FLASK_APP="superset.app:create_app()"
export SUPERSET_CONFIG_PATH="/home/superset/.superset/superset_config.py"

superset db upgrade
superset fab create-admin --username admin --password Admin123! \
 --firstname Admin --lastname User --email admin@example.com
superset init
EOF

echo "=== CREATE SYSTEMD SERVICE ==="
cat <<'EOF' >/etc/systemd/system/superset.service
[Unit]
Description=Apache Superset
After=network.target

[Service]
User=superset
Group=superset
Environment="FLASK_APP=superset.app:create_app()"
Environment="SUPERSET_CONFIG_PATH=/home/superset/.superset/superset_config.py"
WorkingDirectory=/home/superset
ExecStart=/bin/bash -c "source /home/superset/superset-venv/bin/activate && superset run -h 0.0.0.0 -p 8088"
Restart=always

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable superset
systemctl restart superset

echo "✅ Installation complete!"
echo "🌐 Visit: http://SERVER-IP:8088"
echo "👤 Username: admin"
echo "🔑 Password: Admin123!"
