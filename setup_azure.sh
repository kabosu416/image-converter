#!/bin/bash

# Install dependencies
sudo apt update
sudo apt install -y nginx certbot python3-certbot-nginx

# Configure nginx
sudo tee /etc/nginx/sites-available/image_converter > /dev/null << 'EOF'
server {
    listen 80;
    server_name kabosu-img-converter.japaneast.cloudapp.azure.com;

    # Hide nginx version
    server_tokens off;

    location / {
        proxy_pass http://127.0.0.1:5050;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Security Headers
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-XSS-Protection "1; mode=block" always;
        add_header X-Content-Type-Options "nosniff" always;
    }
}
EOF

# Enable site
sudo ln -sf /etc/nginx/sites-available/image_converter /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# Restart nginx
sudo nginx -t
sudo systemctl restart nginx

# Run certbot for SSL
sudo certbot --nginx -d kabosu-img-converter.japaneast.cloudapp.azure.com --non-interactive --agree-tos -m 104502472+kabosu416@users.noreply.github.com

# Update python dependencies and restart gunicorn (internal only)
cd ~/image_converter
pip3 install -r requirements.txt
pkill gunicorn
gunicorn --bind 127.0.0.1:5050 --workers 2 --timeout 60 app:app --daemon
