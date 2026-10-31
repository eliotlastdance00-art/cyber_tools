#!/usr/bin/env python3
"""
cyber_tools · vpn/dev/mock-xui-api.py

3X-UI paneliniň **test üçin** ýönekeý API emulýatory. Hakyky panel ýok wagtynda
`vpn/provision.sh`-yň işleýşini barlamaga ýarar.

Näme goldaýar:
  GET  /                      → HTML dashboard (inbound/müşderi sanawy)
  GET  /health                → {"ok": true}
  GET  /csrf-token            → CSRF token + çörek (session auth üçin)
  POST /login                 → admin/secret ýa-da admin/<sha256(secret)>
  GET  /panel/api/inbounds/list
  GET  /panel/api/inbounds/get/<id>
  POST /panel/api/inbounds/add
  POST /panel/api/inbounds/addClient      (köne v2 ýoly)
  GET  /panel/api/clients/list
  POST /panel/api/clients/add
  POST /panel/api/clients/del/<email>
  POST /__reset               → ähli maglumatlary arassala

Auth: Authorization: Bearer <TOKEN>  ýa-da login arkaly alnan cookie.
Token: MOCK_TOKEN (adaty: testtoken).

Işletmek:
  MOCK_TOKEN=testtoken PORT=18080 python3 vpn/dev/mock-xui-api.py

Bellik: bu hakyky panel DÄL — diňe ýerli synag üçin. Önümçilikde ulanma!
"""
from __future__ import annotations

import html
import json
import os
import re
import secrets
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, unquote, urlparse

TOKEN = os.environ.get("MOCK_TOKEN", "testtoken")
PANEL_BASE = os.environ.get("MOCK_PANEL_BASE", "/panelx").rstrip("/")
HOST = os.environ.get("HOST", "0.0.0.0")
PORT = int(os.environ.get("PORT", "18080"))
ADMIN_USER = os.environ.get("MOCK_USER", "admin")
ADMIN_PASS = os.environ.get("MOCK_PASS", "secret")

NEXT_ID = [1]
INBOUNDS: dict[int, dict] = {}


# ----------------------------- helpers -------------------------------------
def as_json_obj(value):
    """3X-UI settings/streamSettings hem setir, hem obýekt bolup biler."""
    if isinstance(value, str):
        try:
            return json.loads(value)
        except json.JSONDecodeError:
            return {}
    return value or {}


def slim(ib: dict) -> dict:
    out = {k: v for k, v in ib.items() if k not in ("settings", "streamSettings", "sniffing")}
    return out


def clients_of(ib: dict) -> list[dict]:
    return as_json_obj(ib.get("settings")).get("clients", []) or []


def all_clients() -> list[dict]:
    out = []
    for ib in INBOUNDS.values():
        for c in clients_of(ib):
            out.append(
                {
                    "id": c.get("id"),
                    "email": c.get("email"),
                    "subId": c.get("subId"),
                    "uuid": c.get("id"),
                    "flow": c.get("flow", ""),
                    "totalGB": c.get("totalGB", 0),
                    "expiryTime": c.get("expiryTime", 0),
                    "enable": c.get("enable", True),
                    "inboundIds": [ib["id"]],
                    "traffic": {"up": 0, "down": 0, "enable": True},
                }
            )
    return out


def find_inbound_for(email: str):
    for ib in INBOUNDS.values():
        if any(c.get("email") == email for c in clients_of(ib)):
            return ib
    return None


# ------------------------------- dashboard ---------------------------------
def render_index() -> str:
    rows_in = []
    for ib in sorted(INBOUNDS.values(), key=lambda i: i["id"]):
        st = as_json_obj(ib.get("streamSettings"))
        rs = st.get("realitySettings", {}) or {}
        rows_in.append(
            "<tr>"
            f"<td>{ib['id']}</td>"
            f"<td>{html.escape(str(ib.get('protocol', '')))}</td>"
            f"<td>{html.escape(str(ib.get('port', '')))}</td>"
            f"<td>{html.escape(str(ib.get('remark', '')))}</td>"
            f"<td>{html.escape(', '.join(rs.get('serverNames', []) or []))}</td>"
            f"<td><code>{html.escape((rs.get('shortIds') or [''])[0])}</code></td>"
            f"<td>{len(clients_of(ib))}</td>"
            "</tr>"
        )
    if not rows_in:
        rows_in.append('<tr><td colspan="7" class="muted">Inbound ýok — '
                       '<code>provision.sh reality</code> işledip döret</td></tr>')

    rows_cl = []
    for c in all_clients():
        rows_cl.append(
            "<tr>"
            f"<td>{html.escape(str(c['email']))}</td>"
            f"<td><code>{html.escape(str(c['uuid']))[:8]}…</code></td>"
            f"<td>{html.escape(str(c['flow'] or '—'))}</td>"
            f"<td>{c['totalGB'] // (1024 ** 3) if c['totalGB'] else 0} GB</td>"
            f"<td>{html.escape(str(c['inboundIds']))}</td>"
            "</tr>"
        )
    if not rows_cl:
        rows_cl.append('<tr><td colspan="5" class="muted">Müşderi ýok</td></tr>')

    endpoints = [
        ("GET", "/health"),
        ("GET", "/panel/api/inbounds/list"),
        ("GET", "/panel/api/inbounds/get/{id}"),
        ("POST", "/panel/api/inbounds/add"),
        ("GET", "/panel/api/clients/list"),
        ("POST", "/panel/api/clients/add"),
        ("POST", "/panel/api/clients/del/{email}"),
        ("GET", "/csrf-token"),
        ("POST", "/login"),
        ("POST", "/__reset"),
    ]
    rows_ep = "".join(
        f'<tr><td><span class="m {m.lower()}">{m}</span></td><td><code>{html.escape(p)}</code></td></tr>'
        for m, p in endpoints
    )

    return f"""<!doctype html>
<html lang="tk"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>3X-UI mock API · cyber_tools</title>
<style>
  :root {{ color-scheme: dark; }}
  * {{ box-sizing: border-box; }}
  body {{ margin:0; padding:32px 20px 60px; font:15px/1.55 ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;
         background:#0b1020; color:#e6edf7; }}
  .wrap {{ max-width:1040px; margin:0 auto; }}
  h1 {{ font-size:22px; margin:0 0 6px; letter-spacing:.2px; }}
  h2 {{ font-size:15px; margin:32px 0 10px; color:#9fb3d1; text-transform:uppercase; letter-spacing:.08em; }}
  .sub {{ color:#8aa0bf; margin:0 0 22px; }}
  .pill {{ display:inline-block; padding:3px 10px; border-radius:999px; font-size:12px; font-weight:600;
           background:#10361f; color:#5ee7a0; border:1px solid #1d6b3d; vertical-align:middle; }}
  .grid {{ display:grid; grid-template-columns:repeat(auto-fit,minmax(210px,1fr)); gap:12px; margin:18px 0 4px; }}
  .card {{ background:#121a2e; border:1px solid #1e2a45; border-radius:12px; padding:14px 16px; }}
  .card .k {{ font-size:12px; color:#8aa0bf; text-transform:uppercase; letter-spacing:.06em; }}
  .card .v {{ font-size:20px; font-weight:650; margin-top:4px; }}
  table {{ width:100%; border-collapse:collapse; background:#121a2e; border:1px solid #1e2a45;
           border-radius:12px; overflow:hidden; }}
  th,td {{ text-align:left; padding:9px 12px; border-bottom:1px solid #1a2540; font-size:13.5px; }}
  th {{ background:#16203a; color:#9fb3d1; font-weight:600; }}
  tr:last-child td {{ border-bottom:none; }}
  code {{ font-family:ui-monospace,SFMono-Regular,Menlo,monospace; font-size:12.5px; color:#a8d5ff; }}
  .muted {{ color:#7185a3; }}
  .m {{ font-size:11px; font-weight:700; padding:2px 7px; border-radius:5px; }}
  .m.get {{ background:#0f2b46; color:#6cb6ff; }}
  .m.post {{ background:#3a2410; color:#ffb86b; }}
  pre {{ background:#0f1526; border:1px solid #1e2a45; border-radius:12px; padding:14px 16px;
         overflow:auto; font-size:12.5px; color:#c8d8ef; }}
  button {{ background:#1d2b4a; color:#dce9ff; border:1px solid #2c3f66; border-radius:9px;
            padding:8px 14px; font-size:13px; cursor:pointer; }}
  button:hover {{ background:#24365c; }}
  .foot {{ margin-top:34px; color:#7185a3; font-size:12.5px; }}
</style>
</head><body><div class="wrap">
  <h1>3X-UI mock API <span class="pill">preview</span></h1>
  <p class="sub">3X-UI paneliniň test emulýatory — <code>vpn/provision.sh</code> bilen
     hakyky VPS-siz synag etmek üçin. Önümçilikde ulanma.</p>

  <div class="grid">
    <div class="card"><div class="k">Panel base</div><div class="v"><code>{html.escape(PANEL_BASE or '/')}</code></div></div>
    <div class="card"><div class="k">Inbound</div><div class="v">{len(INBOUNDS)}</div></div>
    <div class="card"><div class="k">Müşderi</div><div class="v">{len(all_clients())}</div></div>
    <div class="card"><div class="k">Bearer token</div><div class="v"><code>{html.escape(TOKEN)}</code></div></div>
  </div>

  <h2>Inbound-lar</h2>
  <table><thead><tr><th>ID</th><th>Protokol</th><th>Port</th><th>Remark</th><th>SNI</th><th>shortId</th><th>Müşderi</th></tr></thead>
  <tbody>{''.join(rows_in)}</tbody></table>

  <h2>Müşderiler</h2>
  <table><thead><tr><th>Email</th><th>UUID</th><th>Flow</th><th>Trafik</th><th>Inbound</th></tr></thead>
  <tbody>{''.join(rows_cl)}</tbody></table>

  <h2>Şeýle hem barlap gör</h2>
  <pre>curl -s http://127.0.0.1:{PORT}/panel/api/inbounds/list \\
  -H "Authorization: Bearer {html.escape(TOKEN)}"

bash vpn/provision.sh reality --api-base http://127.0.0.1:{PORT} \\
  --token {html.escape(TOKEN)} --sni www.microsoft.com \\
  --addr 203.0.113.10 --link-dir /tmp/vpn-links</pre>

  <h2>Endpoints</h2>
  <table><thead><tr><th>Metod</th><th>Ýol</th></tr></thead><tbody>{rows_ep}</tbody></table>

  <p style="margin-top:22px"><form method="post" action="/__reset">
    <button type="submit">Maglumatlary arassala</button></form></p>

  <p class="foot">cyber_tools · vpn/dev/mock-xui-api.py · Python http.server, daşarky
     garaşlylyk ýok · <a href="/health" style="color:#6cb6ff">/health</a></p>
</div></body></html>"""


# --------------------------------- HTTP ------------------------------------
class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "MockXUI/1.0"

    # ---- output helpers
    def _send(self, code: int, body: bytes, ctype: str, extra: dict | None = None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def json(self, code: int, obj, extra: dict | None = None):
        self._send(code, json.dumps(obj, ensure_ascii=False).encode(), "application/json; charset=utf-8", extra)

    def html_page(self, text: str):
        self._send(200, text.encode(), "text/html; charset=utf-8")

    def log_message(self, fmt, *args):  # goşmaça sessiya üçin gysga log
        print(f"  {self.command} {self.path} → {args[1] if len(args) > 1 else ''}", flush=True)

    # ---- request helpers
    def _body(self) -> dict:
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""
        try:
            return json.loads(raw or b"{}")
        except json.JSONDecodeError:
            return {}

    def _cookie(self, name: str) -> str:
        raw = self.headers.get("Cookie") or ""
        for part in raw.split(";"):
            k, _, v = part.strip().partition("=")
            if k == name:
                return v
        return ""

    def _authed(self) -> bool:
        if self.headers.get("Authorization", "") == f"Bearer {TOKEN}":
            return True
        return self._cookie("3xui") == "ok"

    def _rest(self, path: str) -> str | None:
        """PANEL_BASE-i aýryp berýär; näsaz ýol bolsa None."""
        if PANEL_BASE and path.startswith(PANEL_BASE + "/"):
            return path[len(PANEL_BASE):]
        if not PANEL_BASE:
            return path
        if path.startswith("/panel/api"):
            return path
        return None

    # ---- GET
    def do_GET(self):
        path = urlparse(self.path).path

        if path == "/health":
            return self.json(200, {"ok": True, "inbounds": len(INBOUNDS), "clients": len(all_clients())})
        if path in ("/", "/index.html", "/dashboard"):
            return self.html_page(render_index())
        if path in ("/csrf-token", f"{PANEL_BASE}/csrf-token"):
            return self.json(200, {"success": True, "obj": secrets.token_urlsafe(24)},
                             {"Set-Cookie": "3xui=ok; Path=/; SameSite=Lax"})

        rest = self._rest(path)
        if rest is None:
            return self.json(404, {"success": False, "msg": "not found"})
        if not self._authed():
            return self.json(401, {"success": False, "msg": "unauthorized"})

        if rest in ("/panel/api/inbounds/list", "/panel/api/inbounds/list/slim"):
            return self.json(200, {"success": True, "obj": [slim(i) for i in INBOUNDS.values()]})
        if rest == "/panel/api/clients/list":
            return self.json(200, {"success": True, "obj": all_clients()})
        if m := re.fullmatch(r"/panel/api/inbounds/get/(\d+)", rest):
            ib = INBOUNDS.get(int(m.group(1)))
            if not ib:
                return self.json(200, {"success": False, "msg": "inbound not found"})
            return self.json(200, {"success": True, "obj": ib})
        if m := re.fullmatch(r"/panel/api/clients/links/(.+)", rest):
            email = unquote(m.group(1))
            ib = find_inbound_for(email)
            if not ib:
                return self.json(200, {"success": False, "msg": "client not found"})
            st = as_json_obj(ib.get("streamSettings"))
            rs = st.get("realitySettings", {}) or {}
            return self.json(200, {"success": True, "obj": [
                f"vless://{uuid.uuid4()}@127.0.0.1:{ib['port']}?type=tcp&security=reality"
                f"&pbk={(rs.get('settings') or {}).get('publicKey', '')}"
                f"&sni={(rs.get('serverNames') or [''])[0]}&sid={(rs.get('shortIds') or [''])[0]}#{email}"
            ]})
        return self.json(404, {"success": False, "msg": "not found"})

    # ---- POST
    def do_POST(self):
        path = urlparse(self.path).path

        if path in ("/login", f"{PANEL_BASE}/login"):
            b = self._body()
            if b.get("username") == ADMIN_USER and b.get("password") == ADMIN_PASS:
                return self.json(200, {"success": True, "msg": "ok"},
                                 {"Set-Cookie": "3xui=ok; Path=/; SameSite=Lax"})
            return self.json(200, {"success": False, "msg": "wrong username or password"})

        if path == "/__reset":
            INBOUNDS.clear()
            NEXT_ID[0] = 1
            # forma iberilse yza gaýtar, API çağyryşy bolsa JSON
            if (self.headers.get("Content-Type") or "").startswith("application/x-www-form-urlencoded"):
                self.send_response(303)
                self.send_header("Location", "/")
                self.send_header("Content-Length", "0")
                self.end_headers()
                return
            return self.json(200, {"success": True, "msg": "reset"})

        rest = self._rest(path)
        if rest is None:
            return self.json(404, {"success": False, "msg": "not found"})
        if not self._authed():
            return self.json(401, {"success": False, "msg": "unauthorized"})

        if rest == "/panel/api/inbounds/add":
            b = self._body()
            if b.get("protocol") != "vless":
                return self.json(200, {"success": False, "msg": "only vless is supported by the mock"})
            st = as_json_obj(b.get("streamSettings"))
            rs = st.get("realitySettings", {}) or {}
            if st.get("security") != "reality":
                return self.json(200, {"success": False, "msg": "security must be reality"})
            if not rs.get("privateKey"):
                return self.json(200, {"success": False, "msg": "reality privateKey required"})
            if not rs.get("serverNames") or not rs.get("shortIds"):
                return self.json(200, {"success": False, "msg": "reality serverNames/shortIds required"})
            if not (rs.get("settings") or {}).get("publicKey"):
                return self.json(200, {"success": False, "msg": "reality publicKey required"})
            if any(ib.get("port") == b.get("port") for ib in INBOUNDS.values()):
                return self.json(200, {"success": False, "msg": "port in use"})

            b["id"] = NEXT_ID[0]
            NEXT_ID[0] += 1
            b.setdefault("enable", True)
            b["settings"] = as_json_obj(b.get("settings"))   # obýekt hökmünde sakla
            b["streamSettings"] = st
            INBOUNDS[b["id"]] = b
            print(f"  + inbound #{b['id']} :{b.get('port')} {b.get('remark')}", flush=True)
            return self.json(200, {"success": True, "msg": "inbound added", "obj": b})

        if rest == "/panel/api/clients/add":
            b = self._body()
            client = b.get("client") or {}
            ids = b.get("inboundIds") or []
            if not client.get("email"):
                return self.json(200, {"success": False, "msg": "client.email required"})
            if not ids:
                return self.json(200, {"success": False, "msg": "inboundIds required"})
            targets = []
            for i in ids:
                ib = INBOUNDS.get(int(i))
                if not ib:
                    return self.json(200, {"success": False, "msg": f"inbound {i} not found"})
                targets.append(ib)
            client.setdefault("id", str(uuid.uuid4()))
            for ib in targets:
                s = as_json_obj(ib.get("settings"))
                s.setdefault("clients", []).append(dict(client))
                ib["settings"] = s
            print(f"  + client {client['email']} → {ids}", flush=True)
            return self.json(200, {"success": True, "msg": "client added"})

        if rest == "/panel/api/inbounds/addClient":   # köne v2 ýoly
            b = self._body()
            ib = INBOUNDS.get(int(b.get("id", 0)))
            if not ib:
                return self.json(200, {"success": False, "msg": "inbound not found"})
            add = as_json_obj(b.get("settings"))
            s = as_json_obj(ib.get("settings"))
            s.setdefault("clients", []).extend(add.get("clients", []))
            ib["settings"] = s
            return self.json(200, {"success": True, "msg": "client added (legacy)"})

        if m := re.fullmatch(r"/panel/api/clients/del/(.+)", rest):
            email = unquote(m.group(1))
            found = False
            for ib in INBOUNDS.values():
                s = as_json_obj(ib.get("settings"))
                before = len(s.get("clients", []))
                s["clients"] = [c for c in s.get("clients", []) if c.get("email") != email]
                found = found or len(s["clients"]) != before
                ib["settings"] = s
            print(f"  - client {email} ({'ok' if found else 'not found'})", flush=True)
            return self.json(200, {"success": found, "msg": "deleted" if found else "not found"})

        return self.json(404, {"success": False, "msg": "not found"})

    def do_HEAD(self):
        self.do_GET()


def main() -> None:
    srv = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"3X-UI mock API · http://{HOST}:{PORT}")
    print(f"  dashboard : http://127.0.0.1:{PORT}/")
    print(f"  panel base: {PANEL_BASE or '/'}")
    print(f"  token     : {TOKEN}")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\nbye")
    finally:
        srv.server_close()


if __name__ == "__main__":
    main()
