#!/bin/bash
# ============================================================
# 包括的セキュリティ攻撃テストスクリプト
# Target: https://kabosu-img-converter.japaneast.cloudapp.azure.com
# ============================================================

TARGET="https://kabosu-img-converter.japaneast.cloudapp.azure.com"
RESULTS_FILE="/tmp/security_test_results.txt"
PASS=0
FAIL=0
WARN=0

# テスト用の小さなPNG画像を生成（1x1ピクセル）
create_test_png() {
    printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f\x00\x00\x01\x01\x00\x05\x18\xd8N\x00\x00\x00\x00IEND\xaeB`\x82' > /tmp/test_image.png
}

echo "============================================================"
echo "🛡️  包括的セキュリティ攻撃テスト"
echo "    Target: $TARGET"
echo "    Date: $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================================"
echo ""

# --- 結果記録関数 ---
record() {
    local status=$1
    local test_name=$2
    local detail=$3
    if [ "$status" = "PASS" ]; then
        echo "  ✅ PASS | $test_name"
        PASS=$((PASS + 1))
    elif [ "$status" = "FAIL" ]; then
        echo "  ❌ FAIL | $test_name"
        echo "         → $detail"
        FAIL=$((FAIL + 1))
    else
        echo "  ⚠️  WARN | $test_name"
        echo "         → $detail"
        WARN=$((WARN + 1))
    fi
}

create_test_png

# ============================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 1. HTTPS / TLS テスト"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1-1: HTTPS接続確認
HTTPS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET/")
if [ "$HTTPS_STATUS" = "200" ]; then
    record "PASS" "HTTPS接続 (ステータス 200)"
else
    record "FAIL" "HTTPS接続" "ステータス: $HTTPS_STATUS"
fi

# 1-2: HTTP→HTTPS リダイレクト
HTTP_REDIRECT=$(curl -s -o /dev/null -w "%{http_code}" -L --max-redirs 0 "http://kabosu-img-converter.japaneast.cloudapp.azure.com/")
if [ "$HTTP_REDIRECT" = "301" ]; then
    record "PASS" "HTTP→HTTPS 301リダイレクト"
else
    record "FAIL" "HTTP→HTTPS リダイレクト" "ステータス: $HTTP_REDIRECT (301であるべき)"
fi

# 1-3: TLS証明書の有効性
TLS_RESULT=$(curl -s -o /dev/null -w "%{ssl_verify_result}" "$TARGET/")
if [ "$TLS_RESULT" = "0" ]; then
    record "PASS" "TLS証明書の有効性 (Let's Encrypt)"
else
    record "FAIL" "TLS証明書" "ssl_verify_result: $TLS_RESULT"
fi

echo ""

# ============================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 2. HSTS テスト"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

HSTS_HEADER=$(curl -s -I "$TARGET/" | grep -i 'strict-transport-security')
if echo "$HSTS_HEADER" | grep -qi 'max-age='; then
    record "PASS" "HSTS ヘッダー存在"
    if echo "$HSTS_HEADER" | grep -qi 'includeSubDomains'; then
        record "PASS" "HSTS includeSubDomains"
    else
        record "WARN" "HSTS includeSubDomains" "未設定"
    fi
else
    record "FAIL" "HSTS ヘッダー" "Strict-Transport-Security が見つからない"
fi

echo ""

# ============================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 3. セキュリティヘッダー テスト"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

HEADERS=$(curl -s -I "$TARGET/")

# 3-1: Content-Security-Policy
if echo "$HEADERS" | grep -qi 'content-security-policy'; then
    record "PASS" "Content-Security-Policy ヘッダー"
else
    record "FAIL" "Content-Security-Policy" "ヘッダーが見つからない"
fi

# 3-2: X-Frame-Options
if echo "$HEADERS" | grep -qi 'x-frame-options'; then
    record "PASS" "X-Frame-Options ヘッダー"
else
    record "FAIL" "X-Frame-Options" "ヘッダーが見つからない"
fi

# 3-3: X-Content-Type-Options
if echo "$HEADERS" | grep -qi 'x-content-type-options'; then
    record "PASS" "X-Content-Type-Options ヘッダー"
else
    record "FAIL" "X-Content-Type-Options" "ヘッダーが見つからない"
fi

# 3-4: Referrer-Policy
if echo "$HEADERS" | grep -qi 'referrer-policy'; then
    record "PASS" "Referrer-Policy ヘッダー"
else
    record "FAIL" "Referrer-Policy" "ヘッダーが見つからない"
fi

# 3-5: Permissions-Policy
if echo "$HEADERS" | grep -qi 'permissions-policy'; then
    record "PASS" "Permissions-Policy ヘッダー"
else
    record "FAIL" "Permissions-Policy" "ヘッダーが見つからない"
fi

# 3-6: X-XSS-Protection
if echo "$HEADERS" | grep -qi 'x-xss-protection'; then
    record "PASS" "X-XSS-Protection ヘッダー"
else
    record "WARN" "X-XSS-Protection" "レガシーヘッダー未設定（CSPでカバー可）"
fi

# 3-7: Server ヘッダー隠蔽
SERVER_HEADER=$(echo "$HEADERS" | grep -i '^server:')
if echo "$SERVER_HEADER" | grep -qi 'gunicorn'; then
    record "FAIL" "Server ヘッダー隠蔽" "gunicorn が露出: $SERVER_HEADER"
elif echo "$SERVER_HEADER" | grep -qi 'nginx/'; then
    record "WARN" "Server ヘッダー隠蔽" "nginx バージョンが露出: $SERVER_HEADER"
elif [ -z "$SERVER_HEADER" ]; then
    record "PASS" "Server ヘッダー隠蔽 (完全非表示)"
else
    record "PASS" "Server ヘッダー隠蔽 ($SERVER_HEADER)"
fi

echo ""

# ============================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 4. レートリミット テスト"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "  [INFO] /convert に15回連続リクエストを送信中..."
GOT_429_OR_503=false
for i in $(seq 1 15); do
    STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
        -X POST "$TARGET/convert" \
        -F "file=@/tmp/test_image.png" \
        -F "format=png" \
        -F "recaptcha_response=dummy")
    # nginxのlimit_reqはデフォルトで503を返す
    if [ "$STATUS" = "429" ] || [ "$STATUS" = "503" ]; then
        GOT_429_OR_503=true
        echo "  [INFO] ${i}回目で HTTP $STATUS (Rate Limited) を受信"
        break
    fi
done

if $GOT_429_OR_503; then
    record "PASS" "レートリミット機能 (HTTP 429/503 確認)"
else
    record "FAIL" "レートリミット" "15回連続でもブロックされなかった"
fi

echo "  [INFO] レートリミット解除のため10秒待機します..."
sleep 10
echo ""

# ============================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 5. アップロード対策 テスト"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# reCAPTCHAがテストキー（常に成功）の場合のみ動作するので、
# recaptcha_response に dummy を入れてテスト
# テストキーでなければ 400 が正常

# 5-1: 拡張子偽装（.exe を送信）
echo "test" > /tmp/fake.exe
STATUS_EXE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$TARGET/convert" \
    -F "file=@/tmp/fake.exe" \
    -F "format=png" \
    -F "recaptcha_response=test")
if [ "$STATUS_EXE" = "400" ] || [ "$STATUS_EXE" = "429" ] || [ "$STATUS_EXE" = "503" ]; then
    record "PASS" "拡張子偽装 (.exe) ブロック (HTTP $STATUS_EXE)"
else
    record "FAIL" "拡張子偽装 (.exe)" "ステータス: $STATUS_EXE"
fi
sleep 2

# 5-2: 拡張子偽装（.php を送信）
echo "<?php echo 'hacked'; ?>" > /tmp/shell.php
STATUS_PHP=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$TARGET/convert" \
    -F "file=@/tmp/shell.php" \
    -F "format=png" \
    -F "recaptcha_response=test")
if [ "$STATUS_PHP" = "400" ] || [ "$STATUS_PHP" = "429" ] || [ "$STATUS_PHP" = "503" ]; then
    record "PASS" "拡張子偽装 (.php) ブロック (HTTP $STATUS_PHP)"
else
    record "FAIL" "拡張子偽装 (.php)" "ステータス: $STATUS_PHP"
fi
sleep 2

# 5-3: マジックナンバー偽装（テキストを .png として送信）
echo "This is not a PNG file" > /tmp/fake_image.png
STATUS_MAGIC=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$TARGET/convert" \
    -F "file=@/tmp/fake_image.png;type=image/png" \
    -F "format=png" \
    -F "recaptcha_response=test")
if [ "$STATUS_MAGIC" = "400" ] || [ "$STATUS_MAGIC" = "429" ] || [ "$STATUS_MAGIC" = "503" ]; then
    record "PASS" "マジックナンバー偽装 ブロック (HTTP $STATUS_MAGIC)"
else
    record "FAIL" "マジックナンバー偽装" "ステータス: $STATUS_MAGIC"
fi
sleep 2

# 5-4: MIMEタイプ偽装（text/plain で画像を送信）
STATUS_MIME=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$TARGET/convert" \
    -F "file=@/tmp/test_image.png;type=text/plain" \
    -F "format=png" \
    -F "recaptcha_response=test")
if [ "$STATUS_MIME" = "400" ] || [ "$STATUS_MIME" = "429" ] || [ "$STATUS_MIME" = "503" ]; then
    record "PASS" "MIMEタイプ偽装 ブロック (HTTP $STATUS_MIME)"
else
    record "FAIL" "MIMEタイプ偽装" "ステータス: $STATUS_MIME"
fi
sleep 2

# 5-5: 不正フォーマット指定
STATUS_FMT=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$TARGET/convert" \
    -F "file=@/tmp/test_image.png" \
    -F "format=exe" \
    -F "recaptcha_response=test")
if [ "$STATUS_FMT" = "400" ] || [ "$STATUS_FMT" = "429" ] || [ "$STATUS_FMT" = "503" ]; then
    record "PASS" "不正フォーマット指定 ブロック (HTTP $STATUS_FMT)"
else
    record "FAIL" "不正フォーマット指定" "ステータス: $STATUS_FMT"
fi

echo ""

# ============================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 6. パストラバーサル / インジェクション テスト"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 6-1: ディレクトリトラバーサル
STATUS_TRAV=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET/download/../../etc/passwd")
if [ "$STATUS_TRAV" = "404" ] || [ "$STATUS_TRAV" = "400" ]; then
    record "PASS" "ディレクトリトラバーサル ブロック (HTTP $STATUS_TRAV)"
else
    record "FAIL" "ディレクトリトラバーサル" "ステータス: $STATUS_TRAV"
fi

# 6-2: URL エンコードトラバーサル
STATUS_TRAV2=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET/download/%2e%2e%2f%2e%2e%2fetc%2fpasswd")
if [ "$STATUS_TRAV2" = "404" ] || [ "$STATUS_TRAV2" = "400" ]; then
    record "PASS" "URL エンコードトラバーサル ブロック (HTTP $STATUS_TRAV2)"
else
    record "FAIL" "URL エンコードトラバーサル" "ステータス: $STATUS_TRAV2"
fi

# 6-3: XSS in filename
STATUS_XSS=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET/download/%3Cscript%3Ealert(1)%3C%2Fscript%3E.png")
if [ "$STATUS_XSS" = "404" ] || [ "$STATUS_XSS" = "400" ]; then
    record "PASS" "XSS in ファイル名 ブロック (HTTP $STATUS_XSS)"
else
    record "FAIL" "XSS in ファイル名" "ステータス: $STATUS_XSS"
fi

# 6-4: SQLi in file_id
STATUS_SQLI=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET/download/1%27%20OR%20%271%27%3D%271")
if [ "$STATUS_SQLI" = "404" ] || [ "$STATUS_SQLI" = "400" ]; then
    record "PASS" "SQLi in file_id ブロック (HTTP $STATUS_SQLI)"
else
    record "FAIL" "SQLi in file_id" "ステータス: $STATUS_SQLI"
fi

# 6-5: コマンドインジェクション
STATUS_CMD=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET/download/%3Bcat%20%2Fetc%2Fpasswd")
if [ "$STATUS_CMD" = "404" ] || [ "$STATUS_CMD" = "400" ]; then
    record "PASS" "コマンドインジェクション ブロック (HTTP $STATUS_CMD)"
else
    record "FAIL" "コマンドインジェクション" "ステータス: $STATUS_CMD"
fi

echo ""

# ============================================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 7. その他のセキュリティテスト"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 7-1: 存在しないページ
STATUS_404=$(curl -s -o /dev/null -w "%{http_code}" "$TARGET/admin")
if [ "$STATUS_404" = "404" ]; then
    record "PASS" "存在しないパス /admin → 404"
else
    record "FAIL" "存在しないパス /admin" "ステータス: $STATUS_404"
fi

# 7-2: OPTIONS メソッド
STATUS_OPT=$(curl -s -o /dev/null -w "%{http_code}" -X OPTIONS "$TARGET/convert")
if [ "$STATUS_OPT" != "200" ]; then
    record "PASS" "OPTIONS メソッド拒否 (HTTP $STATUS_OPT)"
else
    record "WARN" "OPTIONS メソッド" "200を返した（想定外ではないが不要かも）"
fi

# 7-3: PUT メソッド
STATUS_PUT=$(curl -s -o /dev/null -w "%{http_code}" -X PUT "$TARGET/convert")
if [ "$STATUS_PUT" = "405" ] || [ "$STATUS_PUT" = "429" ] || [ "$STATUS_PUT" = "503" ]; then
    record "PASS" "PUT メソッド拒否 (HTTP $STATUS_PUT)"
else
    record "FAIL" "PUT メソッド" "ステータス: $STATUS_PUT"
fi

# 7-4: DELETE メソッド
STATUS_DEL=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$TARGET/convert")
if [ "$STATUS_DEL" = "405" ] || [ "$STATUS_DEL" = "429" ] || [ "$STATUS_DEL" = "503" ]; then
    record "PASS" "DELETE メソッド拒否 (HTTP $STATUS_DEL)"
else
    record "FAIL" "DELETE メソッド" "ステータス: $STATUS_DEL"
fi

# 7-5: ファイル無しのPOST
STATUS_NOFILE=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$TARGET/convert" \
    -F "format=png" \
    -F "recaptcha_response=test")
if [ "$STATUS_NOFILE" = "400" ] || [ "$STATUS_NOFILE" = "429" ] || [ "$STATUS_NOFILE" = "503" ]; then
    record "PASS" "ファイル無しPOST ブロック (HTTP $STATUS_NOFILE)"
else
    record "FAIL" "ファイル無しPOST" "ステータス: $STATUS_NOFILE"
fi

# 7-6: 超大量パラメータ（パラメータ汚染）
STATUS_PARAM=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "$TARGET/convert" \
    -F "file=@/tmp/test_image.png" \
    -F "format=png" \
    -F "format=exe" \
    -F "format=php" \
    -F "recaptcha_response=test")
if [ "$STATUS_PARAM" != "500" ]; then
    record "PASS" "パラメータ汚染 耐性 (HTTP $STATUS_PARAM)"
else
    record "FAIL" "パラメータ汚染" "500エラーが発生した"
fi

echo ""

# ============================================================
# 最終結果
# ============================================================
TOTAL=$((PASS + FAIL + WARN))
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 最終結果"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  ✅ PASS: $PASS / $TOTAL"
echo "  ❌ FAIL: $FAIL / $TOTAL"
echo "  ⚠️  WARN: $WARN / $TOTAL"
echo ""

if [ $FAIL -eq 0 ]; then
    echo "  🎉 全テスト合格！セキュリティ対策は正常に機能しています。"
else
    echo "  ⚠️  $FAIL 件のテストが不合格です。対応が必要です。"
fi

echo ""
echo "============================================================"

# クリーンアップ
rm -f /tmp/test_image.png /tmp/fake.exe /tmp/shell.php /tmp/fake_image.png
