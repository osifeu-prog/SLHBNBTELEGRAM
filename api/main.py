import os, json
from fastapi import FastAPI, HTTPException
from fastapi.responses import JSONResponse
import httpx

RPC = os.getenv("BSC_RPC_URL", "https://data-seed-prebsc-1-s1.binance.org:8545")
CHAIN_ID = int(os.getenv("CHAIN_ID", "97") or 97)
TOKEN = os.getenv("SELA_TOKEN_ADDRESS", "")
app = FastAPI()

def _rpc_payload(method, params, id=1):
    return {"jsonrpc":"2.0","method":method,"params":params,"id":id}

async def rpc(method, params):
    async with httpx.AsyncClient(timeout=20) as client:
        r = await client.post(RPC, json=_rpc_payload(method, params))
        r.raise_for_status()
        return r.json()

@app.get("/")
def root(): return {"ok": True, "chain_id": CHAIN_ID}

@app.get("/healthz")
def healthz(): return {"status": "ok"}

@app.get("/token/info")
async def token_info():
    if not TOKEN: raise HTTPException(400, "SELA_TOKEN_ADDRESS missing")
    def call(data): return rpc("eth_call", [{"to": TOKEN, "data": data}, "latest"])
    name = await call("0x06fdde03")
    symbol = await call("0x95d89b41")
    decimals = await call("0x313ce567")
    total = await call("0x18160ddd")
    return JSONResponse({
        "token": TOKEN,
        "name_raw": name.get("result"),
        "symbol_raw": symbol.get("result"),
        "decimals_raw": decimals.get("result"),
        "totalSupply_raw": total.get("result")
    })

def _balance_of_calldata(addr: str) -> str:
    a = addr.lower().replace("0x","")
    return "0x70a08231" + ("0"*(64-len(a))) + a

@app.get("/token/balance/{address}")
async def balance(address: str):
    if not TOKEN: raise HTTPException(400, "SELA_TOKEN_ADDRESS missing")
    data = _balance_of_calldata(address)
    r = await rpc("eth_call", [{"to": TOKEN, "data": data}, "latest"])
    return {"address": address, "token": TOKEN, "balance_raw": r.get("result")}
