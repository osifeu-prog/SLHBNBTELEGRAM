import os, json, base64, logging
from typing import Optional, Dict, Any
from cryptography.fernet import Fernet, InvalidToken

log = logging.getLogger("slh.store")

def _fernet_from_secret(secret: str) -> Fernet:
    # Accept raw 32+ char secret, convert to urlsafe base64 if needed
    try:
        # try direct fernet key
        Fernet(secret.encode())
        return Fernet(secret.encode())
    except Exception:
        # derive a key from arbitrary string by zero-padding/truncating
        b = secret.encode('utf-8')
        if len(b) < 32:
            b = b + b'0'*(32-len(b))
        key = base64.urlsafe_b64encode(b[:32])
        return Fernet(key)

class Store:
    def __init__(self, data_dir: str, secret: str):
        self.data_dir = data_dir or "./data"
        os.makedirs(self.data_dir, exist_ok=True)
        self.path = os.path.join(self.data_dir, "users.json")
        self._fernet = _fernet_from_secret(secret or "changeme-changeme-changeme-32bytes")
        self._cache: Dict[str, Any] = {}
        self._load()

    def _load(self):
        if os.path.exists(self.path):
            try:
                with open(self.path, "r", encoding="utf-8") as f:
                    self._cache = json.load(f)
            except Exception as e:
                log.error("failed loading users store: %s", e)
                self._cache = {}
        else:
            self._cache = {}

    def _save(self):
        tmp = self.path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(self._cache, f, ensure_ascii=False, indent=2)
        os.replace(tmp, self.path)

    def set_wallet(self, tg_user_id: int, address: str):
        u = self._cache.get(str(tg_user_id), {})
        u["address"] = address
        self._cache[str(tg_user_id)] = u
        self._save()

    def get_wallet(self, tg_user_id: int) -> Optional[str]:
        u = self._cache.get(str(tg_user_id), {})
        return u.get("address")

    def set_pk(self, tg_user_id: int, pk_hex: str):
        token = self._fernet.encrypt(pk_hex.encode("utf-8")).decode("utf-8")
        u = self._cache.get(str(tg_user_id), {})
        u["pk"] = token
        self._cache[str(tg_user_id)] = u
        self._save()

    def get_pk(self, tg_user_id: int) -> Optional[str]:
        u = self._cache.get(str(tg_user_id), {})
        token = u.get("pk")
        if not token:
            return None
        try:
            return self._fernet.decrypt(token.encode("utf-8")).decode("utf-8")
        except (InvalidToken, Exception) as e:
            log.error("failed decrypting pk: %s", e)
            return None
