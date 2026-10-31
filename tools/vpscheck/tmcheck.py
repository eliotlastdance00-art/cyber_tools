#!/usr/bin/env python3
"""
tmcheck.py — "Bu IP/domen Türkmenistandan işleýärmi?"

Daşarky garaşlylyk ýok: diňe Python 3.9+ we internet.

Çeşmeler:
  · OONI API      — TM-de hakyky ölçegler (probe_cc=TM), iň güýçli subut
  · check-host.net— serweriň diri-däldigini dünýäniň dürli düwünlerinden barlamak
  · ipwho.is      — ASN / ýurt / provayder
  · TLS handshake — Reality üçin TLS 1.3, sertifikat, SNI
  · port syýasaty — TM-de 65k portdan diňe ~1.1k açyk (ValdikSS, AGTS 2021)

Ulanylyşy:
  python3 tmcheck.py 203.0.113.10
  python3 tmcheck.py 203.0.113.10 --port 443 --domain vpn.example.com
  python3 tmcheck.py --batch ips.txt --port 443 --json
  python3 tmcheck.py example.com
  python3 tmcheck.py 203.0.113.10 --no-network    # diňe heuristika

Bellik: netije ähtimallyk, kepillik däl. TM ak sanaw (whitelist) ulanyp,
täze IP-leri birnäçe gün/sagatdan ýapýar — 1–2 hepde synag iň dogry ýol.
"""
from __future__ import annotations

import argparse
import json
import os
import socket
import ssl
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field

UA = "tmcheck/1.0 (+https://github.com/eliotlastdance00-art/cyber_tools)"
TIMEOUT = 12

# Synag/mirror üçin çeşme salgylaryny üýtgedip bolýar
OONI_BASE = os.environ.get("OONI_API_BASE", "https://api.ooni.io").rstrip("/")
CHECKHOST_BASE = os.environ.get("CHECKHOST_BASE", "https://check-host.net").rstrip("/")
GEO_BASE = os.environ.get("GEO_BASE", "").rstrip("/")

# TM-de köplenç açyk bolýan portlar (ägirtlik: web, poçta, DNS, XMPP, STUN).
TM_LIKELY_OPEN_PORTS = {22, 25, 53, 80, 110, 123, 143, 443, 465, 587, 993, 995,
                        5222, 8080, 8443, 3478, 5060, 5061}

# Ak sanawda köplenç bolýan CDN/cloud ASN-ler (ady boýunça).
CDN_HINTS = ("cloudflare", "gcore", "akamai", "fastly", "google", "amazon",
             "cloudfront", "microsoft", "azure", "apple", "cdn77", "bunny",
             "stackpath", "limelight")

C = {"g": "\033[32m", "y": "\033[33m", "r": "\033[31m", "c": "\033[36m",
     "d": "\033[2m", "b": "\033[1m", "0": "\033[0m"}


def col(key: str, text: str, enabled: bool = True) -> str:
    return f"{C[key]}{text}{C['0']}" if enabled else text


# ------------------------------- HTTP --------------------------------------
def get_json(url: str, timeout: int = TIMEOUT, headers: dict | None = None):
    req = urllib.request.Request(url, headers={"User-Agent": UA,
                                               "Accept": "application/json",
                                               **(headers or {})})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


def get_status(url: str, timeout: int = TIMEOUT) -> tuple[int, int]:
    """(status, ms) — 0 bolsa ýalňyş."""
    start = time.time()
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, int((time.time() - start) * 1000)
    except urllib.error.HTTPError as e:
        return e.code, int((time.time() - start) * 1000)
    except Exception:
        return 0, int((time.time() - start) * 1000)


# ------------------------------ geo / ASN ----------------------------------
def geo_lookup(ip: str) -> dict:
    urls = ([f"{GEO_BASE}/ipwho/{ip}"] if GEO_BASE else
            [f"https://ipwho.is/{ip}", f"https://ipapi.co/{ip}/json/"])
    for url in urls:
        try:
            d = get_json(url)
            if d.get("success") is False or d.get("error"):
                continue
            conn = d.get("connection") or {}
            return {
                "country": d.get("country") or d.get("country_name"),
                "cc": (d.get("country_code") or d.get("country") or "").upper()[:2],
                "city": d.get("city"),
                "asn": conn.get("asn") or d.get("asn"),
                "org": conn.get("org") or conn.get("isp") or d.get("org"),
            }
        except Exception:
            continue
    return {}


# -------------------------------- OONI -------------------------------------
def ooni_domain(domain: str, days: int = 60) -> dict:
    """TM-de şu domen boýunça ölçegleri jemleýär."""
    until = time.strftime("%Y-%m-%d")
    since = time.strftime("%Y-%m-%d", time.localtime(time.time() - days * 86400))
    out = {"source": "ooni", "domain": domain, "measurements": 0,
           "blocked_rate": None, "networks": set(), "last_seen": None,
           "window_days": days}
    try:
        q = urllib.parse.urlencode({
            "probe_cc": "TM", "domain": domain, "test_name": "web_connectivity",
            "since": since, "until": until, "limit": 200,
        })
        d = get_json(f"{OONI_BASE}/api/v1/measurements?{q}")
        results = d.get("results") or []
        if not results:
            return out
        blocked = 0
        for m in results:
            out["measurements"] += 1
            if m.get("confirmed") or m.get("anomaly"):
                blocked += 1
            if m.get("probe_asn"):
                out["networks"].add(str(m["probe_asn"]))
            ts = m.get("test_start_time") or ""
            if ts and (out["last_seen"] is None or ts > out["last_seen"]):
                out["last_seen"] = ts
        if out["measurements"]:
            out["blocked_rate"] = blocked / out["measurements"]
    except Exception as e:  # tor/API ýalňyşlygy — jedel däl
        out["error"] = str(e)[:120]
    out["networks"] = sorted(out["networks"])
    return out


def ooni_ip(ip: str, days: int = 60) -> dict:
    """OONI-de göni IP boýunça ölçeg bar-my (seýrek bolýar)."""
    for inp in (f"https://{ip}/", f"http://{ip}/", ip):
        try:
            q = urllib.parse.urlencode({"probe_cc": "TM", "input": inp, "limit": 50})
            d = get_json(f"{OONI_BASE}/api/v1/measurements?{q}")
            res = d.get("results") or []
            if res:
                blocked = sum(1 for m in res if m.get("confirmed") or m.get("anomaly"))
                return {"source": "ooni-ip", "input": inp, "measurements": len(res),
                        "blocked_rate": blocked / len(res)}
        except Exception:
            continue
    return {"source": "ooni-ip", "measurements": 0, "blocked_rate": None}


# ----------------------------- check-host ----------------------------------
def _ch_success(v) -> bool:
    """check-host dürli formatda gaýtarýar:
    [[0.13, "1.2.3.4"]], [{"time": 0.13}], [null, "Timeout"] ..."""
    if v is None:
        return False
    if isinstance(v, dict):
        return v.get("time") is not None
    if isinstance(v, list):
        if not v:
            return False
        first = v[0]
        if isinstance(first, dict):
            return first.get("time") is not None
        if isinstance(first, list):
            if not first:
                return False
            head = first[0]
            return isinstance(head, (int, float)) or (isinstance(head, dict) and head.get("time") is not None)
        return isinstance(first, (int, float))
    return False

def check_host_tcp(ip: str, port: int, nodes: int = 6) -> dict:
    """Dünýäniň dürli düwünlerinden TCP barlagy (TM düwüni ýok!)."""
    out = {"source": "check-host", "nodes": {}, "ok_count": 0, "total": 0}
    try:
        d = get_json(f"{CHECKHOST_BASE}/check-tcp"
                     f"?host={urllib.parse.quote(f'{ip}:{port}')}&max_nodes={nodes}",
                     headers={"Accept": "application/json"})
        rid = d.get("request_id")
        if not rid:
            return out
        for attempt in range(4):
            time.sleep(2.0 if attempt == 0 else 2.5)
            res = get_json(f"{CHECKHOST_BASE}/check-result/{rid}",
                           headers={"Accept": "application/json"})
            out["nodes"] = {k: v for k, v in res.items() if v}
            if len(out["nodes"]) >= min(nodes, len(d.get("nodes") or {})):
                break
        for v in out["nodes"].values():
            out["total"] += 1
            if _ch_success(v):
                out["ok_count"] += 1
    except Exception as e:
        out["error"] = str(e)[:120]
    return out


# ------------------------------- TLS ---------------------------------------
def tls_probe(host: str, port: int = 443, sni: str | None = None) -> dict:
    out = {"tls_version": None, "sans": [], "subject": None, "ok": False}
    ctx = ssl.create_default_context()
    try:
        with socket.create_connection((host, port), timeout=8) as sock:
            with ctx.wrap_socket(sock, server_hostname=sni or None) as ss:
                out["tls_version"] = ss.version()
                cert = ss.getpeercert() or {}
                out["ok"] = True
                for k, v in cert.get("subject", ()):
                    if k == "commonName":
                        out["subject"] = v
                out["sans"] = [v for k, v in cert.get("subjectAltName", ())
                               if k == "DNS"][:12]
    except Exception as e:
        out["error"] = str(e)[:120]
    return out


def rdns(ip: str) -> str | None:
    try:
        return socket.gethostbyaddr(ip)[0]
    except Exception:
        return None


# ------------------------------ scoring ------------------------------------
@dataclass
class Report:
    target: str
    ip: str | None = None
    port: int = 443
    domain: str | None = None
    score: int = 50
    verdict: str = "UNCERTAIN"
    reasons: list = field(default_factory=list)
    advice: list = field(default_factory=list)
    data: dict = field(default_factory=dict)


def analyze(target: str, port: int, domain: str | None, no_network: bool) -> Report:
    rep = Report(target=target, port=port, domain=domain)

    # 1) IP / domen anyklamak
    ip = target
    if not target.replace(".", "").isdigit():
        try:
            ip = socket.gethostbyname(target)
            rep.domain = domain or target
        except Exception:
            rep.reasons.append(f"DNS: {target} çözülmedi")
            rep.verdict = "UNKNOWN"
            return rep
    rep.ip = ip

    if no_network:
        return heuristic_only(rep)

    # 2) geo/ASN
    g = geo_lookup(ip)
    rep.data["geo"] = g
    if g.get("cc") == "TM":
        rep.reasons.append("IP-iň özi TM-den (serwer TM içinde) — daşarky hyzmat hökmünde ýaramaz")
        rep.score -= 25

    # 3) domen tapmak (OONI üçin)
    if not rep.domain:
        r = rdns(ip)
        rep.data["rdns"] = r
        if r and not any(x in r.lower() for x in ("static", "host", "vps", "server", "ip-")):
            rep.domain = r

    t = tls_probe(ip, port, sni=rep.domain)
    rep.data["tls"] = t
    if t.get("tls_version"):
        if t["tls_version"] == "TLSv1.3":
            rep.score += 6
            rep.reasons.append("TLS 1.3 bar — Reality üçin ýaramly")
        else:
            rep.reasons.append(f"TLS: {t['tls_version']} (1.3 maslahat)")
    else:
        rep.reasons.append(f"TLS baglanyşygy ýok ({t.get('error', 'näbelli')})")
        rep.score -= 10

    if not rep.domain and t.get("sans"):
        cand = [s for s in t["sans"] if not s.startswith("*.")]
        if cand:
            rep.domain = cand[0]
            rep.reasons.append(f"Domen sertifikatdan tapyldy: {rep.domain}")
    rep.data["domain"] = rep.domain

    # 4) OONI — iň güýçli subut
    oon = {"measurements": 0, "blocked_rate": None}
    if rep.domain:
        oon = ooni_domain(rep.domain)
        rep.data["ooni"] = oon
        rate, n = oon.get("blocked_rate"), oon.get("measurements", 0)
        if n and rate is not None:
            if rate >= 0.6:
                rep.score -= 45
                rep.reasons.append(f"OONI: TM-de {n} ölçegiň {rate:.0%} ýapyk (soňky {oon['window_days']} gün)")
            elif rate >= 0.2:
                rep.score -= 20
                rep.reasons.append(f"OONI: TM-de bölekleýin ýapyk ({rate:.0%} / {n} ölçeg)")
            else:
                rep.score += 25
                rep.reasons.append(f"OONI: TM-de açyk görünýär ({rate:.0%} ýapyk / {n} ölçeg)")
            if oon.get("last_seen"):
                rep.reasons.append(f"OONI soňky ölçeg: {oon['last_seen'][:16]}")
        else:
            rep.reasons.append("OONI: TM-de bu domen boýunça subut ýok (ölçeg tapylmady) — netije diňe heuristika")
    else:
        oip = ooni_ip(ip)
        rep.data["ooni"] = oip
        if oip.get("measurements"):
            rate = oip["blocked_rate"] or 0
            rep.score += 25 if rate < 0.2 else -40
            rep.reasons.append(f"OONI (IP): {oip['measurements']} ölçeg, ýapyk {rate:.0%}")

    # 5) global elýeterlilik
    ch = check_host_tcp(ip, port)
    rep.data["check_host"] = ch
    if ch.get("total"):
        ratio = ch["ok_count"] / ch["total"]
        if ratio >= 0.6:
            rep.score += 8
            rep.reasons.append(f"Global: {ch['ok_count']}/{ch['total']} düwünden açyk (serwer diri)")
        else:
            rep.score -= 15
            rep.reasons.append(f"Global: diňe {ch['ok_count']}/{ch['total']} düwünden açyk — serwer/port problemasy")

    # 6) port syýasaty
    if port in TM_LIKELY_OPEN_PORTS:
        rep.score += 10
        rep.reasons.append(f"Port {port}: TM-de açyk bolmagy ähtimal (web/poçta portlary)")
    else:
        rep.score -= 18
        rep.reasons.append(f"Port {port}: ýokary/ýörite port — TM-de ýapyk bolmagy ähtimal (~1.1k/65k açyk)")

    # 7) ASN
    org = (g.get("org") or "").lower()
    if any(h in org for h in CDN_HINTS):
        rep.score += 12
        rep.reasons.append(f"ASN {g.get('asn')} {g.get('org')}: CDN/cloud — ak sanawda bolmagy ähtimal")
    elif g.get("asn"):
        rep.reasons.append(f"ASN {g.get('asn')} {g.get('org')}: kiçi hoster — ak sanawda däl bolmagy ähtimal")

    finalize(rep)
    return rep


def heuristic_only(rep: Report) -> Report:
    if rep.port in TM_LIKELY_OPEN_PORTS:
        rep.score += 10
        rep.reasons.append(f"Port {rep.port}: adaty açyk portlaryň hatarynda")
    else:
        rep.score -= 18
        rep.reasons.append(f"Port {rep.port}: ýapyk bolmagy ähtimal")
    finalize(rep)
    return rep


def finalize(rep: Report) -> None:
    rep.score = max(0, min(100, rep.score))
    if rep.score >= 70:
        rep.verdict = "LIKELY_OK"
    elif rep.score >= 40:
        rep.verdict = "UNCERTAIN"
    else:
        rep.verdict = "LIKELY_BLOCKED"

    rep.advice = [
        "Reality-ni 443/TCP-de goý — TM-de beýleki portlar köplenç ýapyk.",
        "AmneziaWG/WireGuard UDP 51820 TM-de agyr throttling/ýapyk — diňe ätiýaçlyk.",
        "Bir serwerde 2–3 dürli protokol + 2–3 SNI goý; biri ýapylsa beýlekisi işlär.",
        "Müşderiniň torbasyndan barla (VPN-siz): domen/IP açylýarmy? Bu iň dogry synag.",
    ]
    if rep.verdict != "LIKELY_BLOCKED":
        rep.advice.insert(0, "1–2 hepde dowamy synap gör — TM ak sanawy täze IP-leri soňra ýapyp biler.")


# ------------------------------- output ------------------------------------
def print_report(r: Report, color: bool = True) -> None:
    vmap = {"LIKELY_OK": ("g", "ÄHTIMAL AÇYK"),
            "UNCERTAIN": ("y", "NÄBELLI"),
            "LIKELY_BLOCKED": ("r", "ÄHTIMAL ÝAPYK"),
            "UNKNOWN": ("d", "ANYKSYZ")}
    key, label = vmap.get(r.verdict, ("d", r.verdict))
    print()
    print(col("b", f"tmcheck · {r.target}") + col("d", f"   port {r.port}"))
    print("  " + col(key, f"● {label}") + f"   ball: {r.score}/100")
    if r.ip:
        print(f"  IP: {r.ip}" + (f"   domen: {r.domain}" if r.domain else ""))
    g = r.data.get("geo") or {}
    if g:
        print(f"  Ýer: {g.get('country')} {g.get('city') or ''} · ASN {g.get('asn')} · {g.get('org')}")
    print(col("c", "  Deliller:"))
    for x in r.reasons:
        print(f"    · {x}")
    print(col("c", "  Maslahat:"))
    for x in r.advice:
        print(f"    → {x}")


def main() -> int:
    ap = argparse.ArgumentParser(
        description="IP/domen Türkmenistandan işleýärmi — OONI + check-host + TLS/port analizi",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Mysallar:\n"
               "  python3 tmcheck.py 203.0.113.10 --port 443\n"
               "  python3 tmcheck.py vpn.example.com --domain example.com\n"
               "  python3 tmcheck.py --batch ips.txt --json\n")
    ap.add_argument("target", nargs="?", help="IP ýa-da domen")
    ap.add_argument("--port", type=int, default=443)
    ap.add_argument("--domain", help="OONI barlagy üçin domen (IP-den tapylmasa)")
    ap.add_argument("--batch", help="Her setirde bir IP/domen bolan faýl")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--no-network", action="store_true", help="diňe ýerli heuristika")
    ap.add_argument("--no-color", action="store_true")
    a = ap.parse_args()

    targets = []
    if a.batch:
        with open(a.batch, encoding="utf-8") as f:
            targets = [ln.strip() for ln in f if ln.strip() and not ln.startswith("#")]
    elif a.target:
        targets = [a.target]
    else:
        ap.print_help()
        return 2

    reports = []
    for t in targets:
        rep = analyze(t, a.port, a.domain, a.no_network)
        reports.append(rep)
        if not a.json:
            print_report(rep, color=not a.no_color)
        else:
            print(json.dumps({
                "target": rep.target, "ip": rep.ip, "port": rep.port,
                "domain": rep.domain, "score": rep.score, "verdict": rep.verdict,
                "reasons": rep.reasons, "advice": rep.advice, "data": rep.data,
            }, ensure_ascii=False, default=str))

    if len(reports) > 1 and not a.json:
        print("\n" + col("b", "  Jemleme"))
        for r in sorted(reports, key=lambda x: -x.score):
            print(f"    {r.score:3d}/100  {r.verdict:<15} {r.target}:{r.port}")
    return 0 if all(r.verdict in ("LIKELY_OK", "UNCERTAIN") for r in reports) else 1


if __name__ == "__main__":
    sys.exit(main())
