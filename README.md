# SLH Telegram Bot — Production Pack

**Status:** generated 2025-10-29 10:45:57 UTC

This pack includes:
- Flask + Gunicorn webhook server (`app/app_web.py`)
- python-telegram-bot v21 handlers (`app/bot.py`)
- On‑chain BSC integration via web3.py (`app/wallet_web3.py`)
- Minimal ERC‑20 ABI (`app/abi/erc20.json`)
- Encrypted per‑user PK store (Fernet with `SECRET_KEY`) in `DATA_DIR/users.json`
- Railway compatible: `Procfile`, `runtime.txt`, `railway.json`
- One‑shot PowerShell scripts in `scripts/`

## Quick start (local)

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt

# copy .env.example to .env and fill values
Copy-Item .env.example .env

# run dev server
$env:FLASK_ENV="development"
python -m flask --app app/app_web.py run --host 0.0.0.0 --port 8080
```

Visit `http://localhost:8080/health`. Then set the webhook:
```
GET /set_webhook
```

## Railway (prod)
- Create a Python service, add repository, set envs from `.env.example`.
- `Procfile` runs: `gunicorn -w 1 -k gthread -b 0.0.0.0:$PORT app.app_web:app`.

## Main environment variables
See `.env.example` for descriptions.

## Notes
- The bot stores **only** an encrypted PK (if user chooses to provide it) and wallet address per Telegram user id in `users.json` under `DATA_DIR` (default `/app/data`).
- For mainnet safety, token transfer requires PIN flow unless `ALLOW_TRANSFER_WITHOUT_PIN=true`.
