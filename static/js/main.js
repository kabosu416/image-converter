document.addEventListener('DOMContentLoaded', () => {
    const dropZone = document.getElementById('dropZone');
    const fileInput = document.getElementById('fileInput');
    const settingsArea = document.getElementById('settingsArea');
    const resultArea = document.getElementById('resultArea');
    const fileName = document.getElementById('fileName');
    const convertBtn = document.getElementById('convertBtn');
    const loadingOverlay = document.getElementById('loadingOverlay');
    const downloadUrl = document.getElementById('downloadUrl');
    const copyBtn = document.getElementById('copyBtn');
    const directDownloadBtn = document.getElementById('directDownloadBtn');
    const convertAnotherBtn = document.getElementById('convertAnotherBtn');
    const themeToggle = document.getElementById('themeToggle');

    let currentFile = null;

    // Theme Toggle (Light/Dark mode)
    if (themeToggle) {
        themeToggle.addEventListener('click', () => {
            const root = document.documentElement;
            const newTheme = root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
            root.setAttribute('data-theme', newTheme);
            localStorage.setItem('theme', newTheme);
        });
    }

    // File Upload Handlers
    if (dropZone && fileInput) {
        dropZone.addEventListener('click', () => fileInput.click());

        dropZone.addEventListener('dragover', (e) => {
            e.preventDefault();
            dropZone.classList.add('dragover');
        });

        dropZone.addEventListener('dragleave', () => {
            dropZone.classList.remove('dragover');
        });

        dropZone.addEventListener('drop', (e) => {
            e.preventDefault();
            dropZone.classList.remove('dragover');
            if (e.dataTransfer.files.length) {
                handleFile(e.dataTransfer.files[0]);
            }
        });

        fileInput.addEventListener('change', (e) => {
            if (e.target.files.length) {
                handleFile(e.target.files[0]);
            }
        });
    }

    function handleFile(file) {
        currentFile = file;
        fileName.textContent = file.name;
        dropZone.style.display = 'none';
        settingsArea.style.display = 'block';

        const ext = file.name.split('.').pop().toLowerCase();
        let targetExt = ext;
        if (targetExt === 'jpeg') targetExt = 'jpg';

        const formatOptions = document.querySelectorAll('.format-option');
        let firstVisibleInput = null;

        formatOptions.forEach(option => {
            const format = option.getAttribute('data-format');
            const input = option.querySelector('input[type="radio"]');
            
            if (format === targetExt) {
                option.style.display = 'none';
            } else {
                option.style.display = 'flex';
                if (!firstVisibleInput) {
                    firstVisibleInput = input;
                }
            }
        });

        const currentChecked = document.querySelector('input[name="format"]:checked');
        if (currentChecked && currentChecked.closest('.format-option').style.display === 'none' && firstVisibleInput) {
            firstVisibleInput.checked = true;
        }
    }

    // Convert Image
    if (convertBtn) {
        convertBtn.addEventListener('click', async () => {
            if (!currentFile) return;

            const recaptchaResponse = grecaptcha.getResponse();
            if (!recaptchaResponse) {
                alert('ボットではないことの確認（reCAPTCHA）を行ってください。');
                return;
            }

            const format = document.querySelector('input[name="format"]:checked').value;
            const formData = new FormData();
            formData.append('file', currentFile);
            formData.append('format', format);
            formData.append('recaptcha_response', recaptchaResponse);

            loadingOverlay.style.display = 'flex';

            try {
                const response = await fetch('/convert', {
                    method: 'POST',
                    body: formData
                });
                const data = await response.json();

                if (response.ok) {
                    downloadUrl.value = data.download_url;
                    directDownloadBtn.href = data.download_url;
                    settingsArea.style.display = 'none';
                    resultArea.style.display = 'block';
                } else {
                    alert('変換に失敗しました: ' + data.error);
                }
            } catch (error) {
                alert('エラーが発生しました。もう一度お試しください。');
            } finally {
                loadingOverlay.style.display = 'none';
                grecaptcha.reset();
            }
        });
    }

    // Copy URL
    if (copyBtn) {
        copyBtn.addEventListener('click', () => {
            downloadUrl.select();
            document.execCommand('copy');
            
            const icon = copyBtn.querySelector('i');
            icon.className = 'ph-bold ph-check';
            setTimeout(() => {
                icon.className = 'ph-bold ph-copy';
            }, 2000);
        });
    }

    // Convert Another
    if (convertAnotherBtn) {
        const showQrBtn = document.getElementById('showQrBtn');
        const qrCodeContainer = document.getElementById('qrCodeContainer');
        const qrImage = document.getElementById('qrImage');
        let qrGenerated = false;

        if (showQrBtn) {
            showQrBtn.addEventListener('click', async () => {
                if (qrCodeContainer.style.display === 'none') {
                    qrCodeContainer.style.display = 'block';
                    if (!qrGenerated) {
                        try {
                            const res = await fetch('/api/qrcode', {
                                method: 'POST',
                                headers: { 'Content-Type': 'application/json' },
                                body: JSON.stringify({ url: downloadUrl.value })
                            });
                            const data = await res.json();
                            if (data.qr_image) {
                                qrImage.src = data.qr_image;
                                qrGenerated = true;
                            }
                        } catch (e) {
                            console.error('QR generation failed:', e);
                        }
                    }
                } else {
                    qrCodeContainer.style.display = 'none';
                }
            });
        }

        convertAnotherBtn.addEventListener('click', () => {
            currentFile = null;
            fileInput.value = '';
            resultArea.style.display = 'none';
            dropZone.style.display = 'block';
            if (qrCodeContainer) qrCodeContainer.style.display = 'none';
            if (qrImage) qrImage.src = '';
            qrGenerated = false;
            grecaptcha.reset();
        });
    }

    // Cookie同意バナー
    const cookieBanner = document.getElementById('cookieBanner');
    const cookieAcceptBtn = document.getElementById('cookieAcceptBtn');
    if (cookieBanner && !localStorage.getItem('cookieConsent')) {
        cookieBanner.style.display = 'flex';
    }
    if (cookieAcceptBtn) {
        cookieAcceptBtn.addEventListener('click', () => {
            localStorage.setItem('cookieConsent', 'accepted');
            cookieBanner.style.display = 'none';
        });
    }

    // Easter Egg
    const appLogo = document.querySelector('.app-logo');
    if (appLogo) {
        let clickCount = 0;
        let easterEggTimeout;
        let isSpinning = false;
        
        appLogo.addEventListener('click', () => {
            // リンク内のロゴ（利用規約ページ等）や、既に回転中の場合は発動させない
            if (appLogo.closest('a') || isSpinning) return;

            clickCount++;
            clearTimeout(easterEggTimeout);
            
            if (clickCount >= 5) {
                isSpinning = true;
                appLogo.classList.add('doge-mode-logo');
                document.body.classList.add('doge-mode-rainbow');
                
                const title = document.querySelector('header h1');
                let textNode = null;
                let originalText = "";
                
                if (title) {
                    for (let node of title.childNodes) {
                        if (node.nodeType === Node.TEXT_NODE && node.textContent.trim().length > 0) {
                            textNode = node;
                            originalText = node.textContent;
                            node.textContent = " Wow. Much Converter. Such fast.";
                            break;
                        }
                    }
                }

                // 5秒後に元に戻す
                setTimeout(() => {
                    appLogo.classList.remove('doge-mode-logo');
                    document.body.classList.remove('doge-mode-rainbow');
                    if (textNode) {
                        textNode.textContent = originalText;
                    }
                    clickCount = 0;
                    isSpinning = false;
                }, 5000);
            } else {
                easterEggTimeout = setTimeout(() => {
                    clickCount = 0;
                }, 1000); // 1秒間クリックが途切れたらリセット
            }
        });
    }
});
