#!/bin/bash
set -e

echo "=== [1/5] Nginx セキュリティ設定を更新 ==="

# certbot が既にSSL設定済みの場合を考慮し、SSL部分はcertbotの自動設定に任せ
# セキュリティヘッダーのみ追加で書き込む

# まずnginx.conf レベルで server_tokens off を設定
sudo sed -i '/http {/a\\tserver_tokens off;' /etc/nginx/nginx.conf 2>/dev/null || true

# メインのサイト設定を更新（certbot が管理するSSL設定は維持）
sudo tee /etc/nginx/sites-available/image_converter > /dev/null << 'NGINX_CONF'
server {
    listen 80;
    server_name kabosu-img-converter.japaneast.cloudapp.azure.com;

    # HTTP → HTTPS リダイレクト
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name kabosu-img-converter.japaneast.cloudapp.azure.com;

    # --- SSL (Let's Encrypt / certbot) ---
    ssl_certificate /etc/letsencrypt/live/kabosu-img-converter.japaneast.cloudapp.azure.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/kabosu-img-converter.japaneast.cloudapp.azure.com/privkey.pem;
    include /etc/letsencrypt/options-ssl-nginx.conf;
    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;

    # --- Server Header 隠蔽 ---
    server_tokens off;
    # more_set_headers だと nginx-extras が必要なので proxy_hide_header で対処
    proxy_hide_header X-Powered-By;

    # --- HSTS (2. HTTPS化) ---
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload" always;

    # --- セキュリティヘッダー (3.) ---
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=(), usb=(), magnetometer=()" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' https://www.google.com https://www.gstatic.com https://unpkg.com; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; frame-src https://www.google.com; img-src 'self' data:; connect-src 'self'; object-src 'none'; base-uri 'self'; form-action 'self'" always;

    # --- アップロードサイズ制限 ---
    client_max_body_size 16M;

    # --- レートリミット (nginxレベル, 6. WAF的な役割) ---
    # /convert に対して 10r/m (= 1r/6s) のバースト許可5
    limit_req zone=convert burst=5 nodelay;

    location / {
        proxy_pass http://127.0.0.1:5050;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        # レスポンスからの Server ヘッダーを上書き
        proxy_hide_header Server;
    }
}
NGINX_CONF

echo "=== [2/5] Nginx rate-limit zone を追加 ==="
# nginx.conf の http {} ブロック内に limit_req_zone を追加（重複回避）
if ! grep -q 'limit_req_zone.*convert' /etc/nginx/nginx.conf; then
    sudo sed -i '/http {/a\\tlimit_req_zone $binary_remote_addr zone=convert:10m rate=10r/m;' /etc/nginx/nginx.conf
fi

echo "=== [3/5] Nginx 設定テスト ==="
sudo nginx -t

echo "=== [4/5] Nginx 再起動 ==="
sudo systemctl reload nginx

echo "=== [5/5] アプリケーション更新 & Gunicorn 再起動 ==="
cd ~/image_converter
pip3 install -r requirements.txt --quiet

# ログディレクトリ作成
mkdir -p logs

# Gunicorn を再起動（パスを明示）
pkill -f gunicorn || true
sleep 1
~/.local/bin/gunicorn \
    --bind 127.0.0.1:5050 \
    --workers 2 \
    --timeout 60 \
    --access-logfile logs/gunicorn_access.log \
    --error-logfile logs/gunicorn_error.log \
    app:app --daemon

echo ""
echo "✅ デプロイ完了！"
echo "  URL: https://kabosu-img-converter.japaneast.cloudapp.azure.com"
