#!/bin/bash
apt update -y
apt install -y nginx certbot python3-certbot-nginx

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
