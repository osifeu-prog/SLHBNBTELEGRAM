import os, sys, logging, asyncio
from typing import Optional
from dotenv import load_dotenv
from pythonjsonlogger import jsonlogger
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import Application, CommandHandler, MessageHandler, CallbackQueryHandler, ContextTypes, filters

from .util_store import Store
from . import wallet_web3 as w3w

# ========== logging ==========
load_dotenv()
handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(jsonlogger.JsonFormatter("%(asctime)s %(levelname)s %(name)s %(message)s"))
root = logging.getLogger()
root.handlers = [handler]
root.setLevel(getattr(logging, os.getenv("LOG_LEVEL","INFO").upper(), logging.INFO))
log = logging.getLogger("slh.bot")

TOKEN = os.getenv("BOT_TOKEN") or os.getenv("TELEGRAM_BOT_TOKEN") or ""
WEBHOOK_URL = (os.getenv("WEBHOOK_URL") or "").rstrip("/")
DATA_DIR = os.getenv("DATA_DIR","/app/data")
SECRET_KEY = os.getenv("SECRET_KEY","changeme-changeme-changeme")
ADMIN_USER_ID = int(os.getenv("ADMIN_USER_ID","0") or "0")
PRICE_SHEKEL_PER_SLH = float(os.getenv("PRICE_SHEKEL_PER_SLH","444"))

store = Store(DATA_DIR, SECRET_KEY)

application = Application.builder().token(TOKEN).build()
bot = application.bot

async def start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    kb = [[InlineKeyboardButton("👛 הארנק שלי", callback_data="act:wallet"),
           InlineKeyboardButton("💸 העבר SLH", callback_data="act:send_slh")],
          [InlineKeyboardButton("⚙️ הגדרות", callback_data="act:settings")]]
    await update.effective_message.reply_text(
        "👋 ברוך הבא!\nSLH Platform — ארנק, העברות, מתנות וקהילה.",
        reply_markup=InlineKeyboardMarkup(kb)
    )

async def act_wallet(update: Update, context: ContextTypes.DEFAULT_TYPE):
    uid = update.effective_user.id
    addr = store.get_wallet(uid)
    if not addr:
        await update.effective_message.reply_text("לא הוגדרה כתובת. שלח עכשיו את כתובת ה‑BSC שלך (0x…).")
        return
    try:
        b = w3w.get_balances(addr)
        slh_val = b.get("slh",{}).get("value")
        text = f"👛 הארנק שלך\n\nכתובת:\n{addr}\n\n💰 יתרת SLH: {slh_val if slh_val is not None else '—'}"
    except Exception as e:
        log.error("get_balance error: %s", e)
        text = "❌ שגיאה בשליפת יתרה."
    await update.effective_message.reply_text(text)

async def act_settings(update: Update, context: ContextTypes.DEFAULT_TYPE):
    kb = [[InlineKeyboardButton("🔑 שמור PK", callback_data="act:set_pk"),
           InlineKeyboardButton("🏷️ כתובת", callback_data="act:set_addr")]]
    await update.effective_message.reply_text("⚙️ הגדרות", reply_markup=InlineKeyboardMarkup(kb))

async def cb_router(update: Update, context: ContextTypes.DEFAULT_TYPE):
    cq = update.callback_query
    data = cq.data if cq else ""
    await cq.answer()
    if data == "act:wallet":
        return await act_wallet(update, context)
    if data == "act:settings":
        return await act_settings(update, context)
    if data == "act:set_addr":
        context.user_data["awaiting_addr"] = True
        return await update.effective_message.reply_text("שלח עכשיו את כתובת ה‑BSC שלך (0x…).")
    if data == "act:set_pk":
        context.user_data["awaiting_pk"] = True
        return await update.effective_message.reply_text("שלח עכשיו את ה‑Private Key שלך (0x… 66 תווים).")
    if data == "act:send_slh":
        return await update.effective_message.reply_text("פורמט: /send_slh <to> <amount>")
    return await update.effective_message.reply_text("בקרוב…")

async def on_text(update: Update, context: ContextTypes.DEFAULT_TYPE):
    text = (update.effective_message.text or "").strip()
    uid = update.effective_user.id

    if context.user_data.pop("awaiting_addr", False):
        if text.startswith("0x") and len(text) == 42:
            store.set_wallet(uid, text)
            return await update.effective_message.reply_text("✅ כתובת נשמרה.")
        else:
            return await update.effective_message.reply_text("❌ כתובת לא תקינה.")

    if context.user_data.pop("awaiting_pk", False):
        if text.startswith("0x") and len(text) == 66:
            store.set_pk(uid, text)
            return await update.effective_message.reply_text("✅ PK נשמר (מוצפן).")
        else:
            return await update.effective_message.reply_text("❌ PK לא תקין.")

    return  # ignore other text

async def cmd_balance(update: Update, context: ContextTypes.DEFAULT_TYPE):
    uid = update.effective_user.id
    addr = store.get_wallet(uid)
    if not addr:
        await update.effective_message.reply_text("לא הוגדרה כתובת. /start ואז ⚙️ ➜ כתובת")
        return
    b = w3w.get_balances(addr)
    slh_val = b.get("slh",{}).get("value")
    bnb_val = b.get("bnb",{}).get("eth")
    await update.effective_message.reply_text(f"BNB: {bnb_val}\nSLH: {slh_val}")

async def cmd_send_slh(update: Update, context: ContextTypes.DEFAULT_TYPE):
    uid = update.effective_user.id
    parts = (update.effective_message.text or "").split()
    if len(parts) != 3:
        await update.effective_message.reply_text("שימוש: /send_slh <to> <amount>")
        return
    to, amount_s = parts[1], parts[2]
    try:
        amount = float(amount_s)
    except:
        await update.effective_message.reply_text("כמות לא תקינה.")
        return
    pk = store.get_pk(uid)
    if not pk:
        await update.effective_message.reply_text("❌ נדרש PK שמור בהגדרות.")
        return
    try:
        tx = w3w.send_token(pk, to, amount)
        await update.effective_message.reply_text(f"✅ נשלח. tx: {tx['tx_hash']}")
    except Exception as e:
        log.error("send_slh failed: %s", e)
        await update.effective_message.reply_text("❌ שליחה נכשלה. בדוק BNB לגז, כתובת, סכום.")

def setup_handlers():
    application.add_handler(CommandHandler("start", start))
    application.add_handler(CommandHandler("balance", cmd_balance))
    application.add_handler(CommandHandler("send_slh", cmd_send_slh))
    application.add_handler(CallbackQueryHandler(cb_router))
    application.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, on_text))
    log.info("✅ Handlers registered")

setup_handlers()
log.info("✅ SLH Wallet initialized")
