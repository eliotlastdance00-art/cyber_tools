#!/usr/bin/env python3
"""
provider-audit.py — VPS/hosting provider-leri VPN hyzmaty üçin barlamak.

Näme edýär:
  · providers.json-daky API we looking glass URL-lerini CANLY barlaýar (HTTP status/ms)
  · her provider-e bal berýär: API, LG, kripto, no-KYC, KVM/root, agent/cloud-init,
    TM-a ýakyn ýerleşiş, arzanlyk
  · tablisa ýa-da JSON çykarýar

Ulanylyşy:
  python3 provider-audit.py                     # canly barlag + tablisa
  python3 provider-audit.py --offline           # diňe maglumatdan (tor ýok)
  python3 provider-audit.py --crypto            # diňe kripto/no-KYC
  python3 provider-audit.py --near-tm           # TM-a ýakyn ýerleşişliler
  python3 provider-audit.py --top 5 --json
  python3 provider-audit.py --detail Hetzner

Bellik: providers.json-daky `null` = barlanmadyk. Skript ony "?" hökmünde görkezýär
we bal bermeýär — özüň barlap doldurmaly.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

UA = "provider-audit/1.0 (+cyber_tools)"
NEAR_TM = {"TR", "KZ", "AZ", "IR", "AE", "GE", "UZ", "TJ", "AF", "PK", "IN", "CN"}

C = {"g": "\033[32m", "y": "\033[33m", "r": "\033[31m", "c": "\033[36m",
     "d": "\033[2m", "b": "\033[1m", "0": "\033[0m"}


def col(key: str, text: str, enabled: bool = True) -> str:
    return f"{C[key]}{text}{C['0']}" if enabled else text


def probe(url: str, timeout: int = 10) -> tuple[int, int]:
    """(status, ms); 0 = ýalňyş."""
    if not url:
        return 0, 0
    start = time.time()
    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "*/*"})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, int((time.time() - start) * 1000)
    except urllib.error.HTTPError as e:
        return e.code, int((time.time() - start) * 1000)
    except Exception:
        return 0, int((time.time() - start) * 1000)


def score(p: dict, api_status: int, lg_status: int) -> tuple[int, list[str]]:
    s, why = 0, []
    if api_status and api_status < 400:
        s += 25; why.append("API ✓")
    elif p.get("api"):
        why.append("API ✗")
    if lg_status and lg_status < 400:
        s += 15; why.append("LG ✓")
    if p.get("crypto") is True:
        s += 15; why.append("kripto ✓")
    elif p.get("crypto") is None:
        why.append("kripto ?")
    if p.get("no_kyc") is True:
        s += 10; why.append("no-KYC ✓")
    if p.get("kvm") and p.get("root"):
        s += 10; why.append("KVM+root ✓")
    if p.get("agent") is True:
        s += 10; why.append("agent/cloud-init ✓")
    locs = set(p.get("locations") or [])
    if locs & NEAR_TM:
        s += 10; why.append("TM-a ýakyn: " + ",".join(sorted(locs & NEAR_TM)))
    price = p.get("price_eur_from")
    if isinstance(price, (int, float)):
        if price <= 3.5:
            s += 5; why.append(f"arzan ~€{price}")
        elif price <= 6:
            s += 2
    return s, why


def load(path: Path) -> list[dict]:
    with open(path, encoding="utf-8") as f:
        return json.load(f)["providers"]


def verdict(s: int) -> tuple[str, str]:
    if s >= 70:
        return "g", "GOWY"
    if s >= 45:
        return "y", "ORTA"
    return "r", "GOWANÇSYZ"


def main() -> int:
    ap = argparse.ArgumentParser(
        description="VPS provider-leri VPN üçin barla (API/LG/kripto/agent/ýerleşiş)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="Mysallar:\n  python3 provider-audit.py\n  python3 provider-audit.py --crypto\n"
               "  python3 provider-audit.py --offline --near-tm\n")
    ap.add_argument("--data", default=str(Path(__file__).with_name("providers.json")))
    ap.add_argument("--offline", action="store_true", help="tor barlagyny geçirme")
    ap.add_argument("--crypto", action="store_true", help="diňe kripto goldaýanlar")
    ap.add_argument("--near-tm", action="store_true", help="diňe TM-a ýakyn ýerleşişliler")
    ap.add_argument("--top", type=int, default=0)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--detail", help="bir provider barada jikme-jik")
    ap.add_argument("--no-color", action="store_true")
    a = ap.parse_args()

    text = not a.no_color and sys.stdout.isatty()
    try:
        provs = load(Path(a.data))
    except Exception as e:
        print(f"maglumat okalmady: {e}", file=sys.stderr)
        return 2

    if a.detail:
        p = next((x for x in provs if x["name"].lower() == a.detail.lower()), None)
        if not p:
            print(f"tapylmady: {a.detail}", file=sys.stderr)
            return 2
        api_st, api_ms = (0, 0) if a.offline else probe(p.get("api") or "")
        lg_st, lg_ms = (0, 0) if a.offline else probe(p.get("lg") or "")
        s, why = score(p, api_st, lg_st)
        k, v = verdict(s)
        print(col("b", p["name"]) + f"  →  " + col(k, v) + f"  ({s}/100)")
        print(f"  saýt        : {p.get('url')}")
        print(f"  ýerleşişler : {', '.join(p.get('locations') or []) or '?'}")
        print(f"  baha       : ~€{p.get('price_eur_from', '?')}/aý")
        print(f"  API        : {p.get('api') or '—'}  " +
              (f"[{api_st}, {api_ms} ms]" if not a.offline and p.get('api') else ""))
        print(f"  looking glass: {p.get('lg') or '—'}  " +
              (f"[{lg_st}, {lg_ms} ms]" if not a.offline and p.get('lg') else ""))
        print(f"  kripto/karta/no-KYC: {p.get('crypto')} / {p.get('cards')} / {p.get('no_kyc')}")
        print(f"  KVM/root/agent: {p.get('kvm')} / {p.get('root')} / {p.get('agent')}")
        print(f"  bellik     : {p.get('notes', '')}")
        print("  sebäpler   : " + ", ".join(why))
        return 0

    rows = []
    for p in provs:
        if a.crypto and p.get("crypto") is not True:
            continue
        if a.near_tm and not (set(p.get("locations") or []) & NEAR_TM):
            continue
        api_st, api_ms = (0, 0) if a.offline else probe(p.get("api") or "")
        lg_st, lg_ms = (0, 0) if a.offline else probe(p.get("lg") or "")
        s, why = score(p, api_st, lg_st)
        rows.append({"provider": p, "score": s, "why": why,
                     "api_status": api_st, "api_ms": api_ms,
                     "lg_status": lg_st, "lg_ms": lg_ms})
    rows.sort(key=lambda r: -r["score"])
    if a.top:
        rows = rows[: a.top]

    if a.json:
        print(json.dumps([{
            "name": r["provider"]["name"], "score": r["score"],
            "verdict": verdict(r["score"])[1], "reasons": r["why"],
            "api": r["provider"].get("api"), "api_status": r["api_status"],
            "lg": r["provider"].get("lg"), "lg_status": r["lg_status"],
            "crypto": r["provider"].get("crypto"), "no_kyc": r["provider"].get("no_kyc"),
            "price_eur_from": r["provider"].get("price_eur_from"),
            "near_tm": sorted(set(r["provider"].get("locations") or []) & NEAR_TM),
            "url": r["provider"].get("url"),
        } for r in rows], ensure_ascii=False, indent=2))
        return 0

    print()
    print(col("b", "VPS provider audit") + col("d", f"   {len(rows)} provider · "
          + ("offline" if a.offline else "canly barlag")))
    print()
    head = f"{'#':>2}  {'Provider':<16} {'Ball':>5}  {'Netije':<10} {'API':<5} {'LG':<5} {'Kripto':<7} {'TM-a ýakyn':<12} {'~€/aý':>6}"
    print(col("c", head))
    print(col("d", "─" * len(head)))
    for i, r in enumerate(rows, 1):
        p = r["provider"]
        k, v = verdict(r["score"])
        if a.offline:
            api = "·" if p.get("api") else "—"
            lg = "·" if p.get("lg") else "—"
        else:
            api = "✓" if r["api_status"] and r["api_status"] < 400 else ("✗" if p.get("api") else "—")
            lg = "✓" if r["lg_status"] and r["lg_status"] < 400 else ("✗" if p.get("lg") else "—")
        cr = "✓" if p.get("crypto") is True else ("✗" if p.get("crypto") is False else "?")
        near = ",".join(sorted(set(p.get("locations") or []) & NEAR_TM)) or "—"
        price = p.get("price_eur_from")
        price_s = f"{price}" if isinstance(price, (int, float)) else "?"
        print(f"{i:>2}  {p['name'][:16]:<16} {r['score']:>5}  "
              f"{col(k, f'{v:<10}')} {api:<5} {lg:<5} {cr:<7} {near:<12} {price_s:>6}")
    print()
    print(col("d", "✓ barlanyp işleýär · ✗ barlanyp işlemeýär · · barlanmady (offline) · — maglumat ýok (null)"))
    print(col("d", "Bellik: '—' LG/API ýok diýildigi däl, diňe maglumat ýetmezçiligi."))
    return 0


if __name__ == "__main__":
    sys.exit(main())
