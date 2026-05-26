#!/bin/bash
yum update -y
yum install -y nginx certbot python3-certbot-nginx

# index
cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html>
  <head>
    <title>My Website</title>
  </head>
  <body>
    <h1>Task 3.2.4 Getting started with EC2</h1>
  </body>
</html>
EOF

systemctl start nginx
systemctl enable nginx