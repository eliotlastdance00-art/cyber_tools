# vpscheck — "Türkmenistandan işleýärmi?" + VPS provider audit

Iki gural, daşarky garaşlylyk ýok (diňe Python 3.9+, urllib/ssl).

| Faýl | Näme edýär |
|---|---|
| `tmcheck.py` | IP/domen berilende: **TM-den açylýarmy** — OONI + check-host + TLS + port/ASN heuristikasy |
| `provider-audit.py` | `providers.json`-daky provider-leri canly barlaýar: **API, looking glass, kripto, no-KYC, agent, ýerleşiş** |
| `providers.json` | 14 provider barada maglumat (`null` = barlanmadyk) |

## 1. `tmcheck.py`

```bash
python3 tmcheck.py 203.0.113.10
python3 tmcheck.py 203.0.113.10 --port 443 --domain vpn.example.com
python3 tmcheck.py vpn.example.com --json
python3 tmcheck.py --batch ips.txt --port 443
python3 tmcheck.py 203.0.113.10 --no-network      # diňe heuristika
```

**Näme barlaýar:**

| Çeşme | Näme berýär |
|---|---|
| **OONI API** (`probe_cc=TM`) | TM-de şu domen boýunça hakyky ölçegler: näçe ýapyk, haýsy ASN-lerden, haçan |
| **check-host.net** | 29 düwünden TCP barlagy — serwer diri-mi (TM düwüni ýok!) |
| **ipwho.is** | ASN, ýurt, provayder; CDN/cloud bolsa ak sanaw ähtimallygy ýokary |
| **TLS** | TLS 1.3, sertifikat, SNI — Reality üçin ýaramlymy |
| **Port syýasaty** | TM-de 65 535 TCP portdan diňe ~1 150 açyk (ValdikSS, AGTS 2021) |
| **rDNS/SNI** | Diňe IP berlen bolsa, OONI üçin domeni özi tapýar |

**Netije:** `LIKELY_OK` / `UNCERTAIN` / `LIKELY_BLOCKED` + ball (0–100) + deliller + maslahat.

### Hakykat barada aç-açan

- **Göni "TM-dan" ölçeg düzgüni ýok:** check-host-da TM düwüni ýok, OONI maglumatlary taryhy (60 gün).
- Şonuň üçin bu **ähtimallyk**, kepillik däl. Iň dogry synag — müşderiniň telefonyndan VPN-siz barlamak.
- TM köplenç **ak sanaw (whitelist)** ulanýar: täze IP-ler birnäçe gün/sagatdan soň ýapylyp bilner → 1–2 hepde synag.
- OONI-de şol domen boýunça ölçeg ýok bolsa, skript "ýapyk" diýmez — `UNCERTAIN` berýär.

### Synag (çeşme salgylaryny üýtgedip bolýar)

```bash
OONI_API_BASE=http://127.0.0.1:18090 CHECKHOST_BASE=http://127.0.0.1:18090 \
GEO_BASE=http://127.0.0.1:18090 python3 tmcheck.py 203.0.113.10 --domain test.example
```

## 2. `provider-audit.py`

```bash
python3 provider-audit.py                 # canly: API/LG URL-lerini barla + tablisa
python3 provider-audit.py --offline       # diňe maglumat (tor ýok)
python3 provider-audit.py --crypto        # diňe kripto goldaýanlar
python3 provider-audit.py --near-tm       # TM-a ýakyn ýerleşişliler (TR/KZ/AZ/IR/AE/GE/UZ/IN)
python3 provider-audit.py --detail Hetzner
python3 provider-audit.py --top 5 --json
```

**Bal:** API +25 · LG +15 · kripto +15 · no-KYC +10 · KVM+root +10 · agent/cloud-init +10 ·
TM-a ýakyn ýerleşiş +10 · arzanlyk +5.

`null` = **barlanmadyk** (ýok diýildigi däl). Täze provider goşmak: `providers.json`-a ýaz.

## Gözlegden çykan esasy netijeler

1. **OONI** — TM-de 218 633 ölçeg, 5 tor; iň güýçli subut çeşmesi.
2. **TMC** (WWW'23) — TM senzurasy *iki taraplaýyn*, daşardan hem ölçäp bolýar.
3. **ValdikSS 2021** — diňe ~1 150/65 535 TCP port açyk; DNS filterlenýär; DoH IP boýunça ýapyk.
4. **check-host.net / .cc** — TM düwüni ýok → göni ölçeg üçin ýaramaýar.
5. **Provider-ler** — güýçli API: Hetzner, Contabo, Vultr, Cloudzy; kripto/no-KYC: VPSWolf, EQVPS (MCP agent), VPS4Crypto; LG köplenç ýok, barlanmaly.
