# `vpn/dev` — ýerli synag gurallary

Hakyky VPS ýa-da 3X-UI panel bolmazdan `vpn/provision.sh`-yň işleýşini barlamak üçin.
**Diňe test üçin** — önümçilikde ulanma.

| Faýl | Näme edýär |
|---|---|
| `mock-xui-api.py` | 3X-UI v3 API-siniň ýönekeý emulýatory + HTML dashboard. Daşarky paket gerek däl, diňe Python 3. |
| `bin/xray` | `xray x25519` ýerine ýasama açar jübüti (provision.sh şu binany tapýar) |

## Işletmek

```bash
# 1) mock API (adaty: 0.0.0.0:18080, token testtoken)
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
«Maglumatlary arassala» düwmesi bilen ýagdaýy nula gaýtarýar.

## Sazlamalar (environment)

| Üýtgeýän | Adaty | Manysy |
|---|---|---|
| `PORT` | `18080` | Diňleýän port |
| `HOST` | `0.0.0.0` | Diňleýän salgy |
| `MOCK_TOKEN` | `testtoken` | Bearer token |
| `MOCK_PANEL_BASE` | `/panelx` | Panel ýoly (boş goýsaň: kök) |
| `MOCK_USER` / `MOCK_PASS` | `admin` / `secret` | Login üçin |

## Näme goldanýar

`/health`, `/csrf-token`, `/login`, `/panel/api/inbounds/{list,get/:id,add,addClient}`,
`/panel/api/clients/{list,add,del/:email,links/:email}`, `/__reset`.

Mock hakyky panel ýaly barlaýar: `security=reality`, `privateKey`, `serverNames`,
`shortIds`, `publicKey` hökmany; port başga inboundda bar bolsa `port in use` gaýtarýar.

## Näme goldanmaýar

Xray-yň özi, subscription, haýyşyň hakyky trafigi, TLS, köp ulanyjyly session,
2FA. Bu zatlar üçin hakyky panel gerek.
