#!/bin/bash
apt update -y
apt install -y nginx certbot python3-certbot-nginx

# Creează pagina HTML
cat > /var/www/html/index.html <<EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>Hello Foxminded</title>

    <style>
        body {
            margin: 0;
            height: 100vh;

            display: flex;
            justify-content: center;
            align-items: center;
            flex-direction: column;

            background-color: #f2f5f7; /* culoare pală */
            font-family: Arial, sans-serif;
        }

        h1 {
            font-size: 64px;
            color: #4a5568;
            margin: 0;
            font-weight: 600;
        }

        p {
            margin-top: 20px;
            font-size: 24px;
            color: #718096;
        }
    </style>
</head>
<body>
    <h1>Hello Foxminded</h1>
    <p>Task 3.2.4 Getting started with EC2</p>
</body>
</html>
EOF

systemctl start nginx
systemctl enable nginx