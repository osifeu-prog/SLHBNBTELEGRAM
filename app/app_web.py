import os, logging, sys, asyncio
from flask import Flask, request, jsonify
from pythonjsonlogger import jsonlogger
from dotenv import load_dotenv

from .bot import application, bot
from . import wallet_web3 as w3w

# logging
load_dotenv()
handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(jsonlogger.JsonFormatter("%(asctime)s %(levelname)s %(name)s %(message)s"))
root = logging.getLogger()
root.handlers = [handler]
root.setLevel(getattr(logging, os.getenv("LOG_LEVEL","INFO").upper(), logging.INFO))
log = logging.getLogger("slh.web")

WEBHOOK_URL = (os.getenv("WEBHOOK_URL") or "").rstrip("/")
CHAIN_ID = int(os.getenv("CHAIN_ID","56"))

app = Flask(__name__)

@app.get("/")
def root():
    return jsonify({"ok": True, "service": "SLH Telegram Bot", "chain_id": CHAIN_ID})

@app.get("/version")
def version():
    return jsonify({"ok": True, "version": "prod-pack-1", "ptb": "21.6"})

@app.get("/health")
def health():
    return jsonify({"ok": True, "rpc_connected": w3w.ok(), "chain_id": CHAIN_ID})

@app.get("/set_webhook")
def set_webhook():
    if not WEBHOOK_URL:
        return jsonify({"ok": False, "error": "WEBHOOK_URL missing"}), 400
    url = f"{WEBHOOK_URL}/webhook"
    try:
        res = asyncio.run(bot.set_webhook(url=url, drop_pending_updates=True))
        return jsonify({"ok": bool(res), "set_to": url})
    except Exception as e:
        log.exception("set_webhook failed")
        return jsonify({"ok": False, "error": str(e)}), 500

@app.post("/webhook")
def webhook():
    try:
        data = request.get_json(force=True, silent=True) or {}
        update = application.bot._unfreeze({'update_id': 0})  # no-op; PTB needs Update instance
        # Proper way:
        from telegram import Update as TgUpdate
        upd = TgUpdate.de_json(data, bot)
        asyncio.run(application.process_update(upd))
        return jsonify({"ok": True})
    except Exception as e:
        log.exception("webhook error")
        return jsonify({"ok": False, "error": str(e)}), 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT","8080")))
