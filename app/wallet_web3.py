import os, logging, time
from typing import Dict, Any, Optional
from web3 import Web3
from hexbytes import HexBytes
import json

log = logging.getLogger("slh.wallet")

RPC_URL = os.getenv("BSC_RPC_URL", "https://bsc-dataseed.binance.org")
CHAIN_ID = int(os.getenv("CHAIN_ID", "56"))
TOKEN_ADDR = Web3.to_checksum_address(os.getenv("SELA_TOKEN_ADDRESS", "0x0000000000000000000000000000000000000000"))

_w3 = Web3(Web3.HTTPProvider(RPC_URL, request_kwargs={"timeout": 15}))
with open(os.path.join(os.path.dirname(__file__), "abi", "erc20.json"), "r", encoding="utf-8") as f:
    _ERC20_ABI = json.load(f)

_token = _w3.eth.contract(address=TOKEN_ADDR, abi=_ERC20_ABI)

def ok() -> bool:
    try:
        return _w3.is_connected()
    except Exception:
        return False

def checksum(addr: str) -> str:
    return Web3.to_checksum_address(addr)

def get_balances(address: str) -> Dict[str, Any]:
    addr = checksum(address)
    out: Dict[str, Any] = {"address": addr, "chain_id": CHAIN_ID, "rpc": RPC_URL}
    try:
        bnb_wei = _w3.eth.get_balance(addr)
        out["bnb"] = {"wei": bnb_wei, "eth": Web3.from_wei(bnb_wei, "ether")}
    except Exception as e:
        log.error("get_balance bnb failed: %s", e)
        out["bnb"] = {"error": str(e)}

    try:
        bal = _token.functions.balanceOf(addr).call()
        decimals = _token.functions.decimals().call()
        symbol = _token.functions.symbol().call()
        value = bal / (10**decimals)
        out["slh"] = {"symbol": symbol, "decimals": decimals, "raw": bal, "value": float(value)}
    except Exception as e:
        log.error("get_balance token failed: %s", e)
        out["slh"] = {"error": str(e)}

    return out

def send_bnb(pk_hex: str, to_addr: str, amount_bnb: float, gas_limit: int = 21000) -> Dict[str, Any]:
    acct = _w3.eth.account.from_key(pk_hex)
    to = checksum(to_addr)
    nonce = _w3.eth.get_transaction_count(acct.address)
    gas_price = _w3.eth.gas_price
    tx = {
        "to": to,
        "value": Web3.to_wei(amount_bnb, "ether"),
        "gas": gas_limit,
        "gasPrice": gas_price,
        "nonce": nonce,
        "chainId": CHAIN_ID,
    }
    signed = acct.sign_transaction(tx)
    tx_hash = _w3.eth.send_raw_transaction(signed.rawTransaction)
    return {"tx_hash": tx_hash.hex(), "gas_price": int(gas_price), "nonce": nonce}

def send_token(pk_hex: str, to_addr: str, amount_token: float) -> Dict[str, Any]:
    acct = _w3.eth.account.from_key(pk_hex)
    to = checksum(to_addr)
    decimals = _token.functions.decimals().call()
    amount = int(amount_token * (10**decimals))
    nonce = _w3.eth.get_transaction_count(acct.address)
    gas_price = _w3.eth.gas_price
    tx = _token.functions.transfer(to, amount).build_transaction({
        "from": acct.address,
        "nonce": nonce,
        "gasPrice": gas_price,
        "chainId": CHAIN_ID,
    })
    # estimate gas
    try:
        tx["gas"] = _w3.eth.estimate_gas(tx)
    except Exception:
        tx["gas"] = 100000
    signed = acct.sign_transaction(tx)
    tx_hash = _w3.eth.send_raw_transaction(signed.rawTransaction)
    return {"tx_hash": tx_hash.hex(), "gas_price": int(gas_price), "nonce": nonce}
