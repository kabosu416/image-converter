import os
import uuid
import time
import struct
import logging
from logging.handlers import RotatingFileHandler
from flask import Flask, request, render_template, send_file, jsonify, url_for
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from PIL import Image
import pillow_heif
import requests
from werkzeug.utils import secure_filename
from dotenv import load_dotenv

load_dotenv()

# Register HEIF opener so PIL can open HEIC files natively
pillow_heif.register_heif_opener()

app = Flask(__name__)

# ============================================================
# 【5. ログ・監視】構造化ログの設定
# ============================================================
os.makedirs('logs', exist_ok=True)

# アクセスログ（IP, User-Agent, ステータス, パス）
access_handler = RotatingFileHandler(
    'logs/access.log', maxBytes=10*1024*1024, backupCount=5
)
access_handler.setFormatter(logging.Formatter(
    '%(asctime)s | %(message)s'
))
access_logger = logging.getLogger('access')
access_logger.setLevel(logging.INFO)
access_logger.addHandler(access_handler)

# セキュリティイベントログ（攻撃検知、レートリミット超過等）
security_handler = RotatingFileHandler(
    'logs/security.log', maxBytes=10*1024*1024, backupCount=5
)
security_handler.setFormatter(logging.Formatter(
    '%(asctime)s | SECURITY | %(message)s'
))
security_logger = logging.getLogger('security')
security_logger.setLevel(logging.WARNING)
security_logger.addHandler(security_handler)

# Discord Webhook エラー通知ハンドラー
class DiscordWebhookHandler(logging.Handler):
    def __init__(self, webhook_url):
        super().__init__()
        self.webhook_url = webhook_url

    def emit(self, record):
        try:
            msg = self.format(record)
            payload = {
                "content": f"🚨 **System Alert** 🚨\n```\n{msg}\n```"
            }
            requests.post(self.webhook_url, json=payload, timeout=5)
        except Exception:
            pass

DISCORD_WEBHOOK_URL = os.environ.get('DISCORD_WEBHOOK_URL')
if DISCORD_WEBHOOK_URL:
    discord_handler = DiscordWebhookHandler(DISCORD_WEBHOOK_URL)
    discord_handler.setLevel(logging.ERROR)
    discord_handler.setFormatter(logging.Formatter(
        '%(asctime)s [%(levelname)s] %(message)s'
    ))
    
    # 既存のロガーに Discord 通知をアタッチ
    app.logger.addHandler(discord_handler)
    security_logger.addHandler(discord_handler)

# ============================================================
# 【1. レートリミット】Flask-Limiter
# ============================================================
def get_real_ip():
    """nginx の X-Forwarded-For からクライアントIPを取得"""
    forwarded = request.headers.get('X-Forwarded-For')
    if forwarded:
        return forwarded.split(',')[0].strip()
    return request.remote_addr

limiter = Limiter(
    key_func=get_real_ip,
    app=app,
    default_limits=["200 per day", "50 per hour"],
    storage_uri="memory://",
    strategy="fixed-window"
)

# ============================================================
# 基本設定
# ============================================================
UPLOAD_FOLDER = 'uploads'
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER

# 【セキュリティ強化】最大アップロードサイズを16MBに制限（DoS攻撃対策）
app.config['MAX_CONTENT_LENGTH'] = 16 * 1024 * 1024

# 【セキュリティ】.envファイルからキーを読み込む。未設定の場合はテストキーを使用
RECAPTCHA_SITE_KEY = os.environ.get('RECAPTCHA_SITE_KEY', '6LeIxAcTAAAAAJcZVRqyHh71UMIEGNQ_MXjiZKhI')
RECAPTCHA_SECRET_KEY = os.environ.get('RECAPTCHA_SECRET_KEY', '6LeIxAcTAAAAAGG-vFI1TnRWxMZNFuojJ4WifJWe')

ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'heic'}
TARGET_ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'webp', 'gif', 'heic'}

# ============================================================
# 【4. アップロード対策】マジックナンバー定義
# ============================================================
MAGIC_NUMBERS = {
    'jpg':  [b'\xff\xd8\xff'],
    'jpeg': [b'\xff\xd8\xff'],
    'png':  [b'\x89PNG\r\n\x1a\n'],
    'gif':  [b'GIF87a', b'GIF89a'],
    'webp': [b'RIFF'],  # RIFF????WEBP 形式
    'heic': [b'\x00\x00\x00', b'ftyp'],  # ISO BMFF (先頭4byteはサイズ、8byte目にftyp)
}

# MIMEタイプのホワイトリスト
ALLOWED_MIMES = {
    'image/jpeg', 'image/png', 'image/gif', 'image/webp',
    'image/heic', 'image/heif',
    'application/octet-stream',  # HEICは一部ブラウザでoctet-streamになる
}

# ZIP Bomb 検知用の展開後上限サイズ (100MP = 100万ピクセル)
MAX_IMAGE_PIXELS = 100_000_000  # 100メガピクセル
Image.MAX_IMAGE_PIXELS = MAX_IMAGE_PIXELS


def allowed_file(filename):
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS


def validate_mime_type(file_storage):
    """【4. アップロード対策】MIMEタイプ検証"""
    mime = file_storage.content_type
    if mime not in ALLOWED_MIMES:
        security_logger.warning(
            f"MIME_REJECT | ip={get_real_ip()} | mime={mime} | "
            f"filename={file_storage.filename}"
        )
        return False
    return True


def validate_magic_number(file_storage):
    """【4. アップロード対策】マジックナンバー（ファイルヘッダー）検証"""
    ext = file_storage.filename.rsplit('.', 1)[1].lower() if '.' in file_storage.filename else ''

    # ファイルの先頭32バイトを読み込む
    header = file_storage.read(32)
    file_storage.seek(0)  # 読み取り位置をリセット

    if len(header) < 4:
        security_logger.warning(
            f"MAGIC_REJECT_SHORT | ip={get_real_ip()} | ext={ext} | "
            f"filename={file_storage.filename}"
        )
        return False

    # HEIC/HEIF は ISO BMFF 形式で特殊なチェックが必要
    if ext in ('heic', 'heif'):
        # ftypが4〜8バイト目付近にあるかチェック
        if b'ftyp' in header[:16]:
            return True
        security_logger.warning(
            f"MAGIC_REJECT_HEIC | ip={get_real_ip()} | ext={ext} | "
            f"header={header[:16].hex()}"
        )
        return False

    # WEBP は RIFF + WEBP
    if ext == 'webp':
        if header[:4] == b'RIFF' and b'WEBP' in header[:16]:
            return True
        security_logger.warning(
            f"MAGIC_REJECT_WEBP | ip={get_real_ip()} | ext={ext} | "
            f"header={header[:16].hex()}"
        )
        return False

    # その他の画像形式（JPG, PNG, GIF）
    if ext in MAGIC_NUMBERS:
        for magic in MAGIC_NUMBERS[ext]:
            if header[:len(magic)] == magic:
                return True
        security_logger.warning(
            f"MAGIC_REJECT | ip={get_real_ip()} | ext={ext} | "
            f"header={header[:8].hex()}"
        )
        return False

    return False


def check_zip_bomb(file_storage):
    """【4. アップロード対策】ZIP Bomb / Decompression Bomb 検知"""
    try:
        file_storage.seek(0)
        img = Image.open(file_storage)
        # PIL の verify() でイメージの整合性をチェック
        img.verify()
        file_storage.seek(0)

        # 再度開いてピクセル数をチェック
        img = Image.open(file_storage)
        width, height = img.size
        file_storage.seek(0)

        if width * height > MAX_IMAGE_PIXELS:
            security_logger.warning(
                f"ZIP_BOMB | ip={get_real_ip()} | "
                f"size={width}x{height} ({width*height} pixels) | "
                f"filename={file_storage.filename}"
            )
            return False
        return True
    except Exception as e:
        security_logger.warning(
            f"ZIP_BOMB_ERROR | ip={get_real_ip()} | "
            f"error={str(e)} | filename={file_storage.filename}"
        )
        return False


def cleanup_old_files():
    """【セキュリティ強化】1時間以上経過した古いファイルを自動削除（ストレージ枯渇対策）"""
    now = time.time()
    for filename in os.listdir(app.config['UPLOAD_FOLDER']):
        file_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        if os.path.isfile(file_path):
            # ファイルの作成/更新時刻が現在より1時間（3600秒）以上前なら削除
            if os.stat(file_path).st_mtime < now - 3600:
                try:
                    os.remove(file_path)
                except Exception:
                    pass


# ============================================================
# 【5. ログ・監視】リクエスト前後のフック
# ============================================================
@app.before_request
def log_request():
    """全リクエストのアクセスログを記録"""
    access_logger.info(
        f"ip={get_real_ip()} | method={request.method} | "
        f"path={request.path} | ua={request.user_agent.string}"
    )


@app.after_request
def add_security_headers(response):
    """【3. セキュリティヘッダー追加】全レスポンスにセキュリティヘッダーを付与"""
    # Content-Security-Policy
    response.headers['Content-Security-Policy'] = (
        "default-src 'self'; "
        "script-src 'self' https://www.google.com https://www.gstatic.com https://unpkg.com; "
        "style-src 'self' 'unsafe-inline' https:; "
        "font-src 'self' data: https:; "
        "frame-src https://www.google.com; "
        "img-src 'self' data:; "
        "connect-src 'self'; "
        "object-src 'none'; "
        "base-uri 'self'; "
        "form-action 'self'"
    )
    # X-Frame-Options
    response.headers['X-Frame-Options'] = 'SAMEORIGIN'
    # X-Content-Type-Options
    response.headers['X-Content-Type-Options'] = 'nosniff'
    # Referrer-Policy
    response.headers['Referrer-Policy'] = 'strict-origin-when-cross-origin'
    # Permissions-Policy
    response.headers['Permissions-Policy'] = (
        'camera=(), microphone=(), geolocation=(), '
        'payment=(), usb=(), magnetometer=()'
    )
    # HSTS (nginx側でも設定しているが、アプリ側でも二重防御)
    response.headers['Strict-Transport-Security'] = 'max-age=31536000; includeSubDomains'
    # X-XSS-Protection (レガシーブラウザ用)
    response.headers['X-XSS-Protection'] = '1; mode=block'

    # アクセスログにステータスコードを記録
    access_logger.info(
        f"ip={get_real_ip()} | status={response.status_code} | "
        f"path={request.path}"
    )

    return response


# ============================================================
# 【1. レートリミット】429エラーのカスタムハンドラ
# ============================================================
@app.errorhandler(429)
def ratelimit_handler(e):
    security_logger.warning(
        f"RATE_LIMIT | ip={get_real_ip()} | "
        f"path={request.path} | ua={request.user_agent.string}"
    )
    return jsonify({
        'error': 'リクエストが多すぎます。しばらく待ってから再試行してください。'
    }), 429

@app.errorhandler(Exception)
def global_exception_handler(e):
    """【監視】予期せぬエラーをすべて捕捉し、Discordへ通知（app.logger経由）"""
    import traceback
    tb = traceback.format_exc()
    app.logger.error(
        f"Unhandled Exception: {str(e)}\n"
        f"Path: {request.path}\n"
        f"IP: {get_real_ip()}\n"
        f"Traceback:\n{tb}"
    )
    return jsonify({'error': 'サーバー内部でエラーが発生しました。'}), 500


# ============================================================
# ルーティング
# ============================================================
@app.route('/')
def index():
    return render_template('index.html', recaptcha_site_key=RECAPTCHA_SITE_KEY)


@app.route('/convert', methods=['POST'])
@limiter.limit("10 per minute")
def convert_image():
    # 変換前に古いファイルを掃除する
    cleanup_old_files()

    # reCAPTCHAの検証
    recaptcha_response = request.form.get('recaptcha_response')
    if not recaptcha_response:
        return jsonify({'error': 'reCAPTCHAを完了してください。'}), 400

    verify_response = requests.post(
        url='https://www.google.com/recaptcha/api/siteverify',
        data={
            'secret': RECAPTCHA_SECRET_KEY,
            'response': recaptcha_response
        },
        timeout=5
    )
    result = verify_response.json()
    if not result.get('success'):
        security_logger.warning(
            f"RECAPTCHA_FAIL | ip={get_real_ip()} | "
            f"ua={request.user_agent.string}"
        )
        return jsonify({'error': 'ボット判定されました。'}), 400

    if 'file' not in request.files:
        return jsonify({'error': 'ファイルが選択されていません。'}), 400

    file = request.files['file']
    if file.filename == '':
        return jsonify({'error': 'ファイルが選択されていません。'}), 400

    # 【4. アップロード対策】拡張子チェック
    if not allowed_file(file.filename):
        security_logger.warning(
            f"EXT_REJECT | ip={get_real_ip()} | "
            f"filename={file.filename}"
        )
        return jsonify({'error': 'サポートされていないファイル形式です。'}), 400

    # 【4. アップロード対策】MIMEタイプチェック
    if not validate_mime_type(file):
        return jsonify({'error': '不正なファイルタイプです。画像ファイルのみ対応しています。'}), 400

    # 【4. アップロード対策】マジックナンバーチェック
    if not validate_magic_number(file):
        return jsonify({'error': 'ファイルの内容が拡張子と一致しません。'}), 400

    # 【4. アップロード対策】ZIP Bomb チェック
    if not check_zip_bomb(file):
        return jsonify({'error': 'ファイルサイズが大きすぎるか、不正なファイルです。'}), 400

    target_format = request.form.get('format', 'png').lower()
    if target_format == 'jpg':
        target_format = 'jpeg'

    # 【セキュリティ強化】ターゲットフォーマットの厳格なバリデーション
    if target_format not in TARGET_ALLOWED_EXTENSIONS:
        security_logger.warning(
            f"FORMAT_REJECT | ip={get_real_ip()} | format={target_format}"
        )
        return jsonify({'error': '不正な変換フォーマットが指定されました。'}), 400

    try:
        # Generate unique ID for this conversion
        file_id = str(uuid.uuid4())
        new_filename = f"{file_id}.{target_format}"
        output_path = os.path.join(app.config['UPLOAD_FOLDER'], new_filename)

        # Open and convert the image
        with Image.open(file) as img:
            # Convert to RGB if saving as JPEG and image has alpha channel
            if target_format == 'jpeg' and img.mode in ('RGBA', 'P', 'LA'):
                img = img.convert('RGB')
            
            pillow_format = target_format.upper()
            if target_format == 'heic':
                pillow_format = 'HEIF'

            img.save(output_path, format=pillow_format)

        # Generate the download URL
        download_url = url_for('download_file', file_id=new_filename, _external=True)

        access_logger.info(
            f"CONVERT_OK | ip={get_real_ip()} | "
            f"src={file.filename} | dst={target_format} | "
            f"file_id={file_id}"
        )

        return jsonify({
            'success': True,
            'download_url': download_url,
            'filename': new_filename
        })

    except Exception as e:
        security_logger.warning(
            f"CONVERT_ERROR | ip={get_real_ip()} | "
            f"filename={file.filename} | error={type(e).__name__}"
        )
        # セキュリティ上、詳細なエラー内容は返さない
        return jsonify({'error': '画像の変換処理中にエラーが発生しました。'}), 500


@app.route('/download/<file_id>')
def download_file(file_id):
    # 【セキュリティ強化】ディレクトリトラバーサル防止 (werkzeugのセキュアな関数を使用)
    safe_file_id = secure_filename(file_id)

    file_path = os.path.join(app.config['UPLOAD_FOLDER'], safe_file_id)
    if os.path.exists(file_path):
        return send_file(file_path, as_attachment=True)

    security_logger.warning(
        f"DOWNLOAD_404 | ip={get_real_ip()} | requested={file_id}"
    )
    return jsonify({'error': 'ファイルが見つかりません。'}), 404


if __name__ == '__main__':
    # 【セキュリティ強化】本番環境用に debug=False に設定
    app.run(host='0.0.0.0', port=5050, debug=False)
