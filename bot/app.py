import os, logging, asyncio, httpx, threading
from http.server import BaseHTTPRequestHandler, HTTPServer
from dotenv import load_dotenv
from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes

load_dotenv()
LOG_LEVEL = getattr(logging, os.getenv("LOG_LEVEL","INFO").upper(), logging.INFO)
logging.basicConfig(level=LOG_LEVEL)
log = logging.getLogger("slh.bot")

BOT_TOKEN   = os.getenv("TELEGRAM_BOT_TOKEN","")
API_BASE    = os.getenv("API_BASE","")
DATA_DIR    = os.getenv("DATA_DIR","/app/data")
os.makedirs(DATA_DIR, exist_ok=True)
PORT        = int(os.getenv("PORT","8080"))

# --- tiny health server (Railway healthcheck) ---
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/", "/healthz"):
            self.send_response(200); self.end_headers(); self.wfile.write(b"OK"); return
        self.send_response(404); self.end_headers()
def _serve():
    HTTPServer(("0.0.0.0", PORT), Handler).serve_forever()
threading.Thread(target=_serve, daemon=True).start()

async def main():
    if not BOT_TOKEN:
        log.error("TELEGRAM_BOT_TOKEN missing"); return
    app = Application.builder().token(BOT_TOKEN).build()

    async def start(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        await update.effective_message.reply_text("SLH Bot online (TESTNET). Use /balance <address>")

    async def balance(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        if not ctx.args:
            await update.effective_message.reply_text("usage: /balance 0xYourAddress"); return
        addr = ctx.args[0]
        api = API_BASE
        if not api:
            # נסה לנחש דומיין API מקביל (bot → api)
            host = os.environ.get("RAILWAY_STATIC_URL") or os.environ.get("RAILWAY_PUBLIC_DOMAIN","")
            if host:
                api = "https://" + host.replace("-bot","-api").rstrip("/")
        if not api:
            await update.effective_message.reply_text("API_BASE not configured"); return
        url = f"{api}/token/balance/{addr}"
        try:
            async with httpx.AsyncClient(timeout=20) as client:
                r = await client.get(url)
                await update.effective_message.reply_text(str(r.json()))
        except Exception as e:
            await update.effective_message.reply_text(f"API error: {e}")

    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("balance", balance))

    # ---- POLLING mode (אמין בריילווי, לא דורש webhook) ----
    await app.initialize()
    await app.start()
    log.info("Bot started (polling).")
    await app.updater.start_polling(allowed_updates=Update.ALL_TYPES)
    try:
        while True:
            await asyncio.sleep(3600)
    finally:
        await app.updater.stop()
        await app.stop()
        await app.shutdown()

if __name__ == "__main__":
    asyncio.run(main())
