#!/bin/bash
#apt update -y
#apt install -y nginx certbot python3-certbot-nginx docker.io docker-compose-plugin awscli inotify-tools

# Add Docker's official GPG key:
sudo apt install ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt update -y
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin nginx certbot python3-certbot-nginx awscli inotify-tools


systemctl start docker
systemctl enable docker

aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 449024774937.dkr.ecr.us-east-1.amazonaws.com

mkdir -p /home/ubuntu/app

# Creare fisier .env
cat > /home/ubuntu/app/.env <<EOF
COMPOSE_PROJECT_NAME=ghostfolio
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=redis123secure
POSTGRES_DB=ghostfolio-db
POSTGRES_USER=ghostfolio
POSTGRES_PASSWORD=postgres123secure
ACCESS_TOKEN_SALT=$(openssl rand -hex 32)
DATABASE_URL=postgresql://ghostfolio:postgres123secure@postgres:5432/ghostfolio-db?connect_timeout=300&sslmode=prefer
JWT_SECRET_KEY=$(openssl rand -hex 32)
EOF

chown -R ubuntu:ubuntu /home/ubuntu/app
chmod -R 755 /home/ubuntu/app

chown ubuntu:ubuntu /home/ubuntu/app/.env

# Configurare Nginx ca reverse proxy
cat > /etc/nginx/sites-available/default <<'NGINX'
server {
    listen 80;
    server_name task324.wolflife.net;

    location / {
        proxy_pass http://localhost:3333;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
NGINX

systemctl start nginx
systemctl enable nginx

cat > /usr/local/bin/watcher.sh <<'WATCHER'
#!/bin/bash

COMPOSE_FILE="/home/ubuntu/app/docker-compose.yml"

# steapta pina cind fisierul exista
echo "Astept crearea fisierului $COMPOSE_FILE..."
while [ ! -f "$COMPOSE_FILE" ]; do
    sleep 5
done

echo "Monitorizez $COMPOSE_FILE la schimbari..."

while inotifywait -e close_write "$COMPOSE_FILE"; do
    echo "docker-compose.yml changed, restarting..."
    cd /home/ubuntu/app
    docker compose --env-file .env up -d
done
WATCHER

chmod +x /usr/local/bin/watcher.sh

cat > /etc/systemd/system/watcher.service <<'SERVICE'
[Unit]
Description=Docker Compose Watcher
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/watcher.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable watcher
systemctl start watcher


DOMAIN="task324.wolflife.net"
EMAIL="lupu1025@gmail.com"

for i in {1..30}; do
    if getent hosts "${DOMAIN}" > /dev/null; then
        break
    fi
    sleep 10
done

certbot --nginx \
    --non-interactive \
    --agree-tos \
    --redirect \
    --email "${EMAIL}" \
    -d "${DOMAIN}"

systemctl reload nginx

# Script de backup
cat > /usr/local/bin/backup.sh <<'BACKUP'
#!/bin/bash

DATE=$(date +%Y-%m-%d-%H-%M-%S)
BACKUP_FILE="/tmp/ghostfolio-backup-$DATE.sql.gz"
S3_BUCKET="dorin-db-backups"
CONTAINER="gf-postgres"
DB_USER="ghostfolio"
DB_NAME="ghostfolio-db"

echo "Starting backup at $DATE..."

# Dump baza de date si comprima
docker exec $CONTAINER pg_dump -U $DB_USER $DB_NAME | gzip > $BACKUP_FILE

# Upload in S3
aws s3 cp $BACKUP_FILE s3://$S3_BUCKET/backups/$(basename $BACKUP_FILE)

# Sterge fisierul local
rm -f $BACKUP_FILE

echo "Backup completed successfully!"
BACKUP

chmod +x /usr/local/bin/backup.sh

echo "0 3 * * * root /usr/local/bin/backup.sh >> /var/log/backup.log 2>&1" > /etc/cron.d/db-backup

# Instalare CloudWatch Agent
wget https://s3.amazonaws.com/amazoncloudwatch-agent/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i amazon-cloudwatch-agent.deb
rm amazon-cloudwatch-agent.deb

# Configurare CloudWatch Agent
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'EOF'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/nginx/access.log",
            "log_group_name": "/ec2/nginx/access",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/nginx/error.log",
            "log_group_name": "/ec2/nginx/error",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
EOF

