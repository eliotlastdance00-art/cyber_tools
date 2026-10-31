# `vpn/dev` — ýerli synag gurallary

Hakyky VPS ýa-da 3X-UI panel bolmazdan `vpn/provision.sh`-yň işleýşini barlamak üçin.
**Diňe test üçin** — önümçilikde ulanma.

| Faýl | Näme edýär |
|---|---|
| `mock-xui-api.py` | 3X-UI v3 API-siniň ýönekeý emulýatory + HTML dashboard. Daşarky paket gerek däl, diňe Python 3. |
| `bin/xray` | `xray x25519` ýerine ýasama açar jübüti (provision.sh şu binany tapýar) |
| `serve.sh` | Preview/ýerli işletmek üçin gysga ýol: host/port/token/seed bir ýerde |

## Işletmek

```bash
# 1) mock API (adaty: 0.0.0.0:18080, token testtoken, seed açyk)
bash vpn/dev/serve.sh
# ýa-da göni:
python3 vpn/dev/mock-xui-api.py

# 2) başga terminalda — provision.sh-y mock-a garşy işlet
export PATH="$PWD/vpn/dev/bin:$PATH"          # ýasama xray üçin
bash vpn/provision.sh test   --api-base http://127.0.0.1:18080 --token testtoken
bash vpn/provision.sh reality --api-base http://127.0.0.1:18080 --token testtoken \
     --sni www.microsoft.com --clients 2 --gb 100 --days 30 \
     --addr 203.0.113.10 --link-dir /tmp/vpn-links
bash vpn/provision.sh list   --api-base http://127.0.0.1:18080 --token testtoken
```

Dashboard: <http://127.0.0.1:18080/> — inbound-lary, müşderileri we endpoint-leri görkezýär,
«Maglumatlary arassala» düwmesi bilen ýagdaýy nula gaýtarýar (seed açyk bolsa, nusgalyk
maglumatlar täzeden döredilýär). Health: <http://127.0.0.1:18080/health>.

## Sazlamalar (environment)

| Üýtgeýän | Adaty | Manysy |
|---|---|---|
| `PORT` | `18080` | Diňleýän port |
| `HOST` | `0.0.0.0` | Diňleýän salgy |
| `MOCK_TOKEN` | `testtoken` | Bearer token |
| `MOCK_PANEL_BASE` | `/panelx` | Panel ýoly (boş goýsaň: kök) |
| `MOCK_USER` / `MOCK_PASS` | `admin` / `secret` | Login üçin |
| `MOCK_SEED` | `1` (`serve.sh`), `0` (göni) | Başlangyçda nusgalyk inbound + 3 müşderi döretmek |

`serve.sh` şu bahalary belläp goýýar: `HOST=0.0.0.0`, `PORT=18080`, `MOCK_TOKEN=testtoken`,
`MOCK_SEED=1`, `MOCK_PANEL_BASE=/panelx`. Islendigini üýtgedip bilersiň:

```bash
PORT=19000 MOCK_TOKEN=supersecret MOCK_SEED=0 bash vpn/dev/serve.sh
```

## Näme goldanýar

`/health`, `/csrf-token`, `/login`, `/panel/api/inbounds/{list,get/:id,add,addClient}`,
`/panel/api/clients/{list,add,del/:email,links/:email}`, `/__reset`.

Mock hakyky panel ýaly barlaýar: `security=reality`, `privateKey`, `serverNames`,
`shortIds`, `publicKey` hökmany; port başga inboundda bar bolsa `port in use` gaýtarýar.

## Näme goldanmaýar

Xray-yň özi, subscription, haýyşyň hakyky trafigi, TLS, köp ulanyjyly session,
2FA. Bu zatlar üçin hakyky panel gerek.
