# One-shot dev helper
param([string]$Port="8080")

python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt

if(-not (Test-Path ".env")) { Copy-Item ".env.example" ".env" }

$env:FLASK_ENV="development"
python -m flask --app app/app_web.py run --host 0.0.0.0 --port $Port
