import os, logging, asyncio, httpx
from dotenv import load_dotenv
from http.server import BaseHTTPRequestHandler, HTTPServer
from threading import Thread
from telegram import Update
from telegram.ext import Application, CommandHandler, ContextTypes

load_dotenv()
logging.basicConfig(level=getattr(logging, os.getenv("LOG_LEVEL","INFO").upper(), logging.INFO))
log = logging.getLogger("slh.bot")

BOT_TOKEN   = os.getenv("TELEGRAM_BOT_TOKEN","")
WEBHOOK_BASE= os.getenv("WEBHOOK_BASE","")
API_BASE    = os.getenv("API_BASE","") or os.getenv("SLH_API_BASE","")
DATA_DIR    = os.getenv("DATA_DIR","/app/data")
os.makedirs(DATA_DIR, exist_ok=True)

PORT = int(os.getenv("PORT","8080"))

# --- tiny web server for healthz & webhook ---
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/" or self.path == "/healthz":
            self.send_response(200); self.end_headers(); self.wfile.write(b"OK"); return
        if self.path.startswith("/webhook"):
            self.send_response(405); self.end_headers(); self.wfile.write(b"Method Not Allowed"); return
        self.send_response(404); self.end_headers()
    def do_POST(self):
        if self.path != "/webhook":
            self.send_response(404); self.end_headers(); return
        length = int(self.headers.get("Content-Length","0"))
        body = self.rfile.read(length) if length>0 else b"{}"
        # let PTB handle via built-in webhook server is possible; here we just ACK quickly
        self.send_response(200); self.end_headers(); self.wfile.write(b"OK")

def run_http():
    httpd = HTTPServer(("0.0.0.0", PORT), Handler)
    httpd.serve_forever()

async def start_bot():
    if not BOT_TOKEN:
        log.error("TELEGRAM_BOT_TOKEN missing"); return
    app = Application.builder().token(BOT_TOKEN).build()

    async def start(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        await update.effective_message.reply_text("SLH Bot online (TESTNET). Use /balance <address>")
    async def balance(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        if not ctx.args:
            await update.effective_message.reply_text("usage: /balance 0xYourAddress")
            return
        addr = ctx.args[0]
        api = API_BASE or (WEBHOOK_BASE.replace("-production","-api").rstrip("/") if WEBHOOK_BASE else "")
        if not api: 
            await update.effective_message.reply_text("API_BASE not configured")
            return
        url = f"{api}/token/balance/{addr}"
        try:
            async with httpx.AsyncClient(timeout=20) as client:
                r = await client.get(url)
                await update.effective_message.reply_text(str(r.json()))
        except Exception as e:
            await update.effective_message.reply_text(f"API error: {e}")

    app.add_handler(CommandHandler("start", start))
    app.add_handler(CommandHandler("balance", balance))
    await app.initialize()
    log.info("Bot initialized")
    await asyncio.sleep(999999)

def main():
    Thread(target=run_http, daemon=True).start()
    asyncio.run(start_bot())

if __name__ == "__main__":
    main()
