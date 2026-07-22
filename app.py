import os
import uuid
import time
from flask import Flask, request, render_template, send_file, jsonify, url_for
from PIL import Image
import pillow_heif
import requests

# Register HEIF opener so PIL can open HEIC files natively
pillow_heif.register_heif_opener()

app = Flask(__name__)
UPLOAD_FOLDER = 'uploads'
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER

# 【セキュリティ強化】最大アップロードサイズを16MBに制限（DoS攻撃対策）
app.config['MAX_CONTENT_LENGTH'] = 16 * 1024 * 1024

# 【セキュリティ】ご自身のシークレットキーに書き換えてください
RECAPTCHA_SECRET_KEY = '6LeIxAcTAAAAAGG-vFI1TnRWxMZNFuojJ4WifJWe'

ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'heic'}
TARGET_ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'webp', 'gif'}

def allowed_file(filename):
    return '.' in filename and \
           filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

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

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/convert', methods=['POST'])
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
        }
    )
    result = verify_response.json()
    if not result.get('success'):
        return jsonify({'error': 'ボット判定されました。'}), 400

    if 'file' not in request.files:
        return jsonify({'error': 'ファイルが選択されていません。'}), 400
    
    file = request.files['file']
    if file.filename == '':
        return jsonify({'error': 'ファイルが選択されていません。'}), 400
        
    target_format = request.form.get('format', 'png').lower()
    if target_format == 'jpg':
        target_format = 'jpeg'

    # 【セキュリティ強化】ターゲットフォーマットの厳格なバリデーション
    if target_format not in TARGET_ALLOWED_EXTENSIONS:
        return jsonify({'error': '不正な変換フォーマットが指定されました。'}), 400

    if file and allowed_file(file.filename):
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
                
                img.save(output_path, format=target_format.upper())
            
            # Generate the download URL
            download_url = url_for('download_file', file_id=new_filename, _external=True)
            
            return jsonify({
                'success': True,
                'download_url': download_url,
                'filename': new_filename
            })
            
        except Exception as e:
            # セキュリティ上、詳細なエラー内容は返さない
            return jsonify({'error': '画像の変換処理中にエラーが発生しました。'}), 500
            
    return jsonify({'error': 'サポートされていないファイル形式です。'}), 400

@app.route('/download/<file_id>')
def download_file(file_id):
    # 【セキュリティ強化】ディレクトリトラバーサル防止 (werkzeugのセキュアな関数を使用)
    from werkzeug.utils import secure_filename
    safe_file_id = secure_filename(file_id)
    
    file_path = os.path.join(app.config['UPLOAD_FOLDER'], safe_file_id)
    if os.path.exists(file_path):
        return send_file(file_path, as_attachment=True)
    return "File not found", 404

if __name__ == '__main__':
    # 【セキュリティ強化】本番環境用に debug=False に設定
    app.run(host='0.0.0.0', port=5050, debug=False)
