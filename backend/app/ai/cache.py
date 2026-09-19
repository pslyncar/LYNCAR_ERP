"""Small process-local cache for public documentation only.

Never cache tenant financial, customer, supplier, stock or fiscal records here.
"""

from __future__ import annotations

from collections import OrderedDict
from threading import RLock
import time
from typing import Any


class TtlCache:
    def __init__(self, max_items: int = 128):
        self._items: OrderedDict[str, tuple[float, Any]] = OrderedDict()
        self._max_items = max_items
        self._lock = RLock()

    def get(self, key: str) -> Any | None:
        now = time.monotonic()
        with self._lock:
            item = self._items.get(key)
            if not item:
                return None
            expires, value = item
            if expires <= now:
                self._items.pop(key, None)
                return None
            self._items.move_to_end(key)
            return value

    def set(self, key: str, value: Any, ttl_seconds: int) -> Any:
        with self._lock:
            self._items[key] = (time.monotonic() + ttl_seconds, value)
            self._items.move_to_end(key)
            while len(self._items) > self._max_items:
                self._items.popitem(last=False)
        return value


public_knowledge_cache = TtlCache(max_items=256)
