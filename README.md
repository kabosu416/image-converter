# 🪄 Magic Image Converter

HEIC対応の画像フォーマット変換Webアプリケーションです。  
変換後にダウンロード用URLが発行され、別の端末（スマホなど）からダウンロードできます。

## ✨ 機能
- **画像フォーマット変換**: HEIC, JPG, PNG, WEBP, GIF に対応
- **ダウンロードURL発行**: 変換後のファイルを別端末からダウンロード可能
- **ダーク/ライトモード**: ワンクリックでテーマ切り替え
- **reCAPTCHA v2**: ボット対策を実装済み
- **セキュリティ対策**: アップロードサイズ制限、自動クリーンアップ、ディレクトリトラバーサル防止

## 🚀 セットアップ

```bash
# リポジトリをクローン
git clone https://github.com/kabosu416/image-converter.git
cd image-converter

# 依存パッケージをインストール
pip install -r requirements.txt

# アプリを起動
python app.py
```

ブラウザで `http://localhost:5050` にアクセスしてください。

## ⚙️ 環境変数の設定

`app.py` 内の以下の値をご自身のreCAPTCHAキーに書き換えてください。

```python
RECAPTCHA_SECRET_KEY = 'あなたのシークレットキー'
```

`templates/index.html` 内の `data-sitekey` も同様に書き換えてください。

## 🛡️ セキュリティ
- reCAPTCHA v2 によるボット防止
- アップロードサイズ上限: 16MB
- 1時間経過したファイルの自動削除
- ファイル拡張子のホワイトリスト検証
- ディレクトリトラバーサル防止
- デバッグモード無効（本番）

## 📦 技術スタック
- **Backend**: Flask, Gunicorn
- **Image Processing**: Pillow, pillow-heif
- **Frontend**: Vanilla JS/CSS (Glassmorphism UI)
- **Security**: Google reCAPTCHA v2
