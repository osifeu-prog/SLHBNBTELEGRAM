# SLH TelegramBot + API (TESTNET)

סטאק מינימלי לפריסה ב-Railway: שירות **bot** (webhook) ושירות **api** (FastAPI).
מוגדר ל-BSC **Testnet**: \BSC_RPC_URL\ ו-\CHAIN_ID=97\.

## פריסה ל-Railway (שני שירותים)
1. צור פרויקט Railway עם שני Services:
   - **SLH_bot** (Root: \ot/\)
   - **slh_API** (Root: \pi/\)
   Railway יקרא את \ailway.json\ ויבנה אוטומטית.

2. הגדר משתני סביבה (לשני השירותים, אלא אם מצוין אחרת):
   **חובה לבוט:**
   - \TELEGRAM_BOT_TOKEN\ = הטוקן של הבוט
   - \WEBHOOK_BASE\ = דומיין Railway של הבוט (ללא סלאש בסוף), למשל: \https://slhtelegrambot-production.up.railway.app\
   - \APPROVED_CHAT_ID\ (לא חובה), \ADMIN_USER_ID\ (לא חובה)
   - \DATA_DIR\ = \/app/data\ (ברירת מחדל)
   - \LOG_LEVEL\ = \INFO\ או \DEBUG\

   **ל-API + לבוט (שניהם):**
   - \BSC_RPC_URL\ = \https://data-seed-prebsc-1-s1.binance.org:8545\
   - \CHAIN_ID\ = \97\
   - \SELA_TOKEN_ADDRESS\ = כתובת הטוקן בטסטנט (EIP55)
   - \SECRET_KEY\ (ל-api בלבד, ערך כלשהו)
   - \PORT\ — Railway מספק, אין צורך לשנות.

3. דפלוי. בדיקות:
   - API: \GET /healthz\ מחזיר 200 (למשל \https://<api-domain>/healthz\)
   - Bot: \GET /healthz\ 200; \GET /webhook\ יחזיר 405 (תקין; הקצה מיועד ל-POST מטלגרם).

4. קביעת webhook (במחשב שלך/ב-Railway shell):

> אם ה-push נכשל בהרשאות/URL — עדכן את ה-remote ונסה שוב:
\git remote set-url origin https://github.com/osifeu-prog/SLHBNBTELEGRAM.git\

