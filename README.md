# SLH Telegram Bot + API (Railway / TESTNET)

## Services (railway.json)
- **SLH_bot** → Python polling + /healthz
- **slh_API** → FastAPI (Uvicorn), endpoints: `/healthz`, `/token/info`, `/token/balance/{address}`

## ENV (לשתי הסרוויסים)
- `BSC_RPC_URL=https://data-seed-prebsc-1-s1.binance.org:8545`
- `CHAIN_ID=97`
- `SELA_TOKEN_ADDRESS=0xEf633c34715A5A581741379C9D690628A1C82B74`
- API: `SECRET_KEY`, `PORT=8080`
- BOT: `TELEGRAM_BOT_TOKEN`, `DATA_DIR=/app/data`, (אופציונלי) `API_BASE=https://<api-domain>.up.railway.app`

## Deploy
1) צור פרויקט ב-Railway → ייקלט אוטומטית מ-railway.json לשני services  
2) קבע Variables כנ"ל בשני ה-services (בוט + API)  
3) Deploy → בדוק `/healthz` של שניהם  
4) **בוט רץ ב-polling** (לא צריך webhook). אם בכל זאת תרצה webhook  אמליץ אחרי שנאשר יציבות.

## פקודות בדיקה
- API: `GET /healthz` → 200, `GET /token/info`
- BOT: שלח `/start`, ו-`/balance 0xYourAddress`
