#!/usr/bin/env python3
"""Проверка MCP-сервера «Озвучка и липсинк»: initialize + tools/list.

    ./check-lipsync-mcp.py vl_XXXX          # или LIPSYNC_TOKEN=vl_XXXX ./check-lipsync-mcp.py
    MCP_URL=... ./check-lipsync-mcp.py vl_XXXX

Печатает имя сервера, версию протокола и список инструментов.
"""
import json
import os
import sys
import urllib.error
import urllib.request

URL = os.environ.get("MCP_URL", "https://lipsync.kachanov.io/mcp")
# Cloudflare отдаёт 403 (Error 1010) на «браузерную подпись» python-urllib,
# поэтому представляемся обычным клиентом.
USER_AGENT = os.environ.get("LIPSYNC_UA", "curl/8.7.1 lipsync-mcp-check/1.0")


def parse(raw: str):
    """Ответ может быть как JSON, так и SSE (data: {...})."""
    for line in raw.splitlines():
        if line.startswith("data:"):
            payload = line[5:].strip()
            if payload:
                return json.loads(payload)
    return json.loads(raw) if raw.strip() else None


def rpc(token: str, method: str, params=None, session=None, rid: int = 1):
    body = json.dumps(
        {"jsonrpc": "2.0", "id": rid, "method": method, "params": params or {}}
    ).encode()
    req = urllib.request.Request(URL, data=body, method="POST")
    req.add_header("content-type", "application/json")
    req.add_header("accept", "application/json, text/event-stream")
    req.add_header("authorization", f"Bearer {token}")
    req.add_header("user-agent", USER_AGENT)
    if session:
        req.add_header("mcp-session-id", session)
    with urllib.request.urlopen(req, timeout=90) as resp:
        return parse(resp.read().decode()), resp.headers.get("mcp-session-id")


def main() -> int:
    token = (sys.argv[1] if len(sys.argv) > 1 else os.environ.get("LIPSYNC_TOKEN", "")).strip()
    if not token:
        print("нужен токен: ./check-lipsync-mcp.py vl_XXXX", file=sys.stderr)
        return 2

    print(f"→ {URL}")
    try:
        init, session = rpc(
            token,
            "initialize",
            {
                "protocolVersion": "2025-06-18",
                "capabilities": {},
                "clientInfo": {"name": "lipsync-check", "version": "1.0"},
            },
        )
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")[:300]
        print(f"✗ HTTP {e.code}: {detail}", file=sys.stderr)
        if e.code == 401:
            print("  Токен не принят. Создайте новый: lipsync.kachanov.io → «Агенты».", file=sys.stderr)
        elif e.code == 403:
            print("  Похоже, запрос отбил Cloudflare. Попробуйте другой User-Agent: LIPSYNC_UA=...", file=sys.stderr)
        return 1
    except urllib.error.URLError as e:
        print(f"✗ сеть: {e.reason}", file=sys.stderr)
        return 1

    if not init or "result" not in init:
        print(f"✗ неожиданный ответ: {init}", file=sys.stderr)
        return 1

    info = init["result"].get("serverInfo", {})
    print(f"✓ подключено: {info.get('name', '?')} v{info.get('version', '?')}")
    print(f"  протокол: {init['result'].get('protocolVersion', '?')}")

    tools, _ = rpc(token, "tools/list", {}, session=session, rid=2)
    items = (tools or {}).get("result", {}).get("tools", [])
    if not items:
        print("  инструменты не объявлены")
        return 0
    print(f"  инструментов: {len(items)}")
    for t in items:
        desc = (t.get("description") or "").splitlines()[0][:90]
        print(f"    • {t['name']}{' — ' + desc if desc else ''}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
