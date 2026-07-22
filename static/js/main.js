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
    themeToggle.addEventListener('click', () => {
        const root = document.documentElement;
        const newTheme = root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
        root.setAttribute('data-theme', newTheme);
    });

    // File Upload Handlers
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

    function handleFile(file) {
        currentFile = file;
        fileName.textContent = file.name;
        dropZone.style.display = 'none';
        settingsArea.style.display = 'block';
    }

    // Convert Image
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

    // Copy URL
    copyBtn.addEventListener('click', () => {
        downloadUrl.select();
        document.execCommand('copy');
        
        const icon = copyBtn.querySelector('i');
        icon.className = 'ph-bold ph-check';
        setTimeout(() => {
            icon.className = 'ph-bold ph-copy';
        }, 2000);
    });

    // Convert Another
    convertAnotherBtn.addEventListener('click', () => {
        currentFile = null;
        fileInput.value = '';
        resultArea.style.display = 'none';
        dropZone.style.display = 'block';
        grecaptcha.reset();
    });
});
