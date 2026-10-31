# VPS-de VPN serwer gurmak — amaly gollanma

> Mysal üçin **FriendHosting** VPS-i ulanylýar, ýöne bu ýol-baýram (metod) islendik KVM VPS-de işleýär:
> Hetzner, Contabo, RackNerd, Aeza, Vultr, DigitalOcean...
>
> Ähli buýruklar **Debian 12 / Ubuntu 22.04+** üçin we `root` hökmünde ýerine ýetirilýär.

---

## 0. Gysga jogap (TL;DR)

| Sorag | Gysga jogap |
|---|---|
| FriendHosting VPN üçin amatlymy? | **Hawa.** KVM wirtualizasiýa, Ýewropada birnäçe data-centr, VPN/proxy resmi ýagdaýda gadagan däl (käbir synlarda WireGuard/OpenVPN şablonlary hem bar diýilýär). Arzan planlarda **100 Mbit port + 1 TB trafik** — köp ulanyjy üçin az. |
| Haýsy panel? | **3x-ui** — ýeke serwer, 5 minutda gurnalýar, içinde VLESS+Reality **we** AmneziaWG bar. 200+ ulanyjy / birnäçe serwer gerek bolsa → **Marzban** ýa-da **Hiddify**. |
| Haýsy protokol? | **VLESS + Reality (TCP 443)** — esasy. **AmneziaWG** — goşmaça. **VLESS+XHTTP+TLS (CDN)** — ätiýaçlyk. WireGuard/OpenVPN — gowy DPI bolan ýerde tiz bloklanýar. **Türkmenistan üçin 5.8-nji bölümi hökmany okaň** — ol ýerde ak sanaw (whitelist) meselesi bar. |
| Ýene näme baglamaly? | Domen (hökmany däl), Cloudflare DNS, Telegram bot, monitoring, awtomatik backup, 2-nji serwer (başga IP/ASN), töleg ulgamy. |
| Näçe pul? | VPS ~€4–9/aý + domen ~$10/ýyl. Başlangyç üçin **1 vCPU / 1 GB / 10 GB** ýeterlik (30–50 ulanyjy). |

---

## 1. FriendHosting: nämä üns bermeli

Bulgaristanda hasaba alnan, arzan Ýewropa VPS-i satýan hoster. KVM, SSD/NVMe, 10+ ýer.

**Typiki planlar** (baha üýtgeýär — saýtda barla):

| Plan | vCPU | RAM | Disk | Port / trafik | Baha (takmynan) |
|---|---|---|---|---|---|
| Micro | 1 | 512 MB | 5–10 GB | 100 Mbit / 1 TB | ~€3/aý |
| **Start** | 1 | 1 GB | 10 GB | 100 Mbit / 1 TB | **~€4.5/aý** |
| **Plus** | 2 | 2 GB | 20 GB | 100 Mbit–1 Gbit / 1 TB | **~€8.5/aý** |
| Profi | 4 | 4 GB | 35 GB | 1 Gbit / has uly | ~€17/aý |

**Ýerleşişler:** Bolgariýa (Sofiýa), Niderland (Dronten/Meppel), Germaniýa (Frankfurt), Polşa, Latwiýa, Çehiýa, Şweýsariýa, Rumyniýa, Italiýa, Ukraina (Kiw), ABŞ (Los-Anjeles, Maýami).

**Saýlamak boýunça maslahat:**
- **Türkmenistandan gürleşjek bolsaň** — Frankfurt ýa-da Niderland iň gowy peýda berýär. Sofiýa hem bolar (Stambul arkaly ýol gysga).
- **Port tizligi** arzan planda 100 Mbit = bir ulanyjy üçin ýeterlik, 20+ adam bir wagtda 4K görensoň̌ dar bolýar.
- **Trafik** limitini barla: 1 TB = takmynan 330 sagat YouTube (1080p) ýa-da 50 ulanyjynyň ýeňil ulanyşy.
- **KVM bolmaly** (OpenVZ/LXC-de TUN/TAP we BBR problemi bolýar).
- **AUP/ToS** — resminama boýunça VPN/proxy gadagan däl, ýöne *reselling* (başgalara satmak) barada supportdan ýazmaça sora. Käbir hosterler "proxy service" diýilse hasaby ýapýar.
- **Töleg** — karta/kripto/usullary checkout-da görkezilýär. Türkmen kartlary halkara tölege çykmaýar, şonuň üçin kripto (USDT TRC-20) amatly.
- **Backup/snapshot** hyzmaty bar bolsa alyň — IP bloklananda täze serwere çalt geçmek üçin.

---

## 2. Arhitektura

```
 Müşderi (Telefon/PC)                VPS (FriendHosting)
┌────────────────────┐          ┌──────────────────────────────────┐
│ v2rayNG / Hiddify  │  :443    │  Xray-core (3x-ui paneli)        │
│  VLESS + Reality   │ ───────► │   ├─ VLESS+Reality  (TCP 443)    │
│  (uTLS: chrome)    │          │   ├─ AmneziaWG      (UDP 51820)  │
└────────────────────┘          │   └─ XHTTP+TLS      (TCP 443/CDN)│
                                │  Panel: 127.0.0.1:PORT (SSH tunel)│
                                └──────────────────────────────────┘
                                          │
                                          ▼
                                    Internet / Telegram / YouTube
```

**Ýörelgeler:**
1. Panel internetden göni açylmaly däl (diňe SSH tunel ýa-da IP allowlist).
2. Reality üçin 443/TCP boş bolmaly — paneli başga porta goý.
3. Her müşderä aýratyn UUID + trafik çäklendirmesi.
4. Bir serwere 2–3 dürli protokol goý: biri bloklansa beýlekisi işlär.

---

## 3. Paneli saýlamak

| Panel | Näme üçin gowy | Näme üçin erbet | Kim üçin |
|---|---|---|---|
| **3x-ui** | Çalt gurnalýar, az RAM iýýär, Reality + AmneziaWG + Hysteria2 içinde, QR/subscription bar | Köp serwer merkezi dolandyrylmaýar, API çäkli | 1 serwer, 10–100 ulanyjy |
| **Marzban** | Ulanyjy/subscription/trafik hasaby gowy, REST API, node-lar, Telegram bot | Docker, has köp RAM, gurnamak uzyn | 100+ ulanyjy, satylýan hyzmat |
| **Hiddify Manager** | Iň köp protokol (20+), anti-censorship sazlamalary taýýar, multi-language | Agyr, köp hyzmat işleýär, täzelenmesi kynrak | DPI gaty güýçli ýerler |
| **Remnawave** | Go-da ýazylan, çalt, döwrebap UI, subscription + payment | Ýaş proýekt, dokumentasiýa azrak | Tejribeli operator |
| **wg-easy** | 2 minutda WireGuard + web UI | Diňe WireGuard (DPI-de gowy däl) | Öý/ulgam üçin, 2–10 adam |

**Maslahatym:** başla **3x-ui** bilen. Uly biznes bolsa soň Marzban/Remnawave geçirersiň — konfigurasiýa (Reality parametrleri) birmeňzeş.

---

## 4. Protokol saýlamak (Türkmenistan / gaty DPI şertleri)

| Protokol | DPI goragy | Barmy? | Bellik |
|---|---|---|---|
| **VLESS + Reality + Vision** | Örän ýokary (hakyky HTTPS ýaly) | Ha | Esasy saýlaw. Domen gerek däl. |
| VLESS + XHTTP + TLS + CDN | Ýokary | Ha | Cloudflare/Gcore arkaly, domen gerek |
| **AmneziaWG** | Orta-ýokary (junk paketler) | Ha | 3x-ui içinde taýýar; UDP |
| Hysteria2 | Orta | Ha | UDP, tiz, ýöne UDP köplenç throttling edilýär |
| Shadowsocks-2022 | Orta | Ha | Köne DPI-de döwülýär |
| Trojan | Pes-orta (2025-den soň tanalýar) | Ha | Işleýän ýerlerde gowy |
| WireGuard (adaty) | **Pes** | Ha | Handshake-a görä bloklanýar |
| OpenVPN | **Pes** | Ha | Sertifikat belligi boýunça bloklanýar |
| IKEv2 | Pes | Ha | Korporatiw VPN belligi |

> **Reality nädip işleýär:** serwer hakyky saýtyň (meselem `www.microsoft.com`) TLS handshake-yny "karz alýar". DPI üçin bu — adaty HTTPS. Şol sebäpli 443/TCP we SNI dogry saýlanmaly.

---

## 5. Gurnama: ädimme-ädim

### 5.1. Serwere birinji gezek girmek

```bash
ssh root@SENIÑ_IP
apt update && apt upgrade -y
timedatectl set-timezone UTC
```

### 5.2. Serweri taýýarlamak (skript bilen)

Repo-ny serwere göçüriň ýa-da şu skriptleri ýerli ýerden işlediň:

```bash
cd /root
# BBR, swap, UFW, fail2ban, awtomatik täzelenme, sysctl tuning
bash vpn/harden.sh --yes
```

Skript näme edýär: BBR + fq, MTU probing, 1 GB swap (RAM az bolsa), UFW poratlary (22/80/443/51820), fail2ban, awtomatik howpsuzlyk täzelenmesi, journald çäklendirmesi.

### 5.3. Paneli gurmak

```bash
bash vpn/setup.sh 3xui --yes
```

Skript resmi `install.sh`-y ulanýar, ýöne:
- **tötänleýin panel porty** (20000–60000),
- **tötänleýin 20 simwolly panel ýoly** (`webBasePath`),
- **tötänleýin login/parol** döredýär,
- paneli **diňe `127.0.0.1`-de** diňledýär (dünýäden ýapyk).

Installasiýa gutaransoň ekranda şular çykýar:

```
Panel URL   : http://127.0.0.1:41731/9x2f...   (diňe SSH tunel bilen)
Ulanyjy     : k3v9a1z0pq
Parol       : Xy7... (20 simwol)
SSH tunel   : ssh -N -L 41731:127.0.0.1:41731 root@SERWER_IP
```

Bu maglumatlar `/etc/x-ui/install-result.env` faýlynda hem saklanýar (chmod 600).
Islendik wagt gaýtadan görmek üçin:

```bash
sudo bash vpn/setup.sh info
x-ui settings          # ýa-da buýruk bilen
```

**Panele girmek (SSH tunel):** öz kompýuteriňde aşakdaky buýrugy işledip, brauzerde `http://127.0.0.1:PORT/ÝOL` aç:

```bash
ssh -N -L PORT:127.0.0.1:PORT root@SENIÑ_IP
```

> Porty we ýoly ýokardaky çykyşdan (ýa-da `setup.sh info`-dan) al. `2053` diňe köne wersiýalaryň adaty bahasy.

**Panel howpsuzlygy:**
- Panel dünýäden açylmaly däl — SSH tunel iň howpsuz ýol.
- Panelde **2FA** aç (3X-UI goldaýar).
- Panel üçin SSL gerek bolsa: `--domain vpn.example.com --email sen@example.com` (80-nji port açyk bolmaly).
- Doly açyk panel isleýän bolsaň: `--panel-public` — **diňe SSL + 2FA + güýçli parol bilen**.
- GitHub bloklanan ýerde: `--installer /root/install.sh` (faýly başga ýerden göçürip al).

Soňky ädimler:

```bash
x-ui            # dolandyryş menýusy (start/stop/log/SSL)
```

### 5.4. VLESS + Reality inbound goşmak

Panelde: **Inbounds → Add Inbound**

| Meýdan | Baha |
|---|---|
| Remark | `tm-reality-443` |
| Protocol | `vless` |
| Listening IP | boş (0.0.0.0) |
| Port | `443` |
| Total traffic | 0 (çäksiz) ýa-da 1000 GB |
| Expiry | boş |
| Security | `reality` |
| Flow | `xtls-rprx-vision` |
| Dest / Target | `www.microsoft.com:443` |
| SNI / serverNames | `www.microsoft.com` |
| Short IDs | düwmä basyp döret (8–16 simwol hex) |
| Public key / Private key | “Get new key” düwmesi |
| uTLS fingerprint | `chrome` |
| SpiderX | `/` |

> **Dest saýlamak:** TLS 1.3 goldaýan, uly, "şübhe döretmeýän" saýt: `www.microsoft.com`, `www.apple.com`, `www.bing.com`, `www.samsung.com`, `www.nvidia.com`.
> Serwerden bar bolmaly: `curl -I https://www.microsoft.com` — 200/301 gaýtarmaly.
> Bir näçe inbound goýup, dürli SNI bilen synap gör (bloklansa çalt çalyşmaly).

#### SNI näme we nädip saýlamaly

**SNI** (*Server Name Indication*) — TLS protokolynyň giňeltmesi (RFC 6066).
Brauzer bir IP-däki https saýta birigeninde, haýsy saýty isleýänini **ClientHello-da açyk görnüşde** (şifrlenmän) aýdýar — sebäbi bir IP-de birnäçe saýt bolup biler we serwer haýsy sertifikaty bermelidigini saýlamaly bolýar.

- Şonuň üçin DPI SNI-a seredip **haýsy domena gidýändigiňi görýär** — domen boýunça bloklama hut şu ýerde bolýar.
- ECH (*Encrypted Client Hello*) muny ýapýar, ýöne häzir hemme ýerde goldanmaýar.

**Reality-de SNI nämä gerek?** Reality öz sertifikatyny ulanmaýar — ol hakyky saýtyň TLS handshake-yny "karz alýar":

1. Klient SNI hökmünde `www.microsoft.com` iberýär.
2. Reality serweri şol handshake-y `dest` (`www.microsoft.com:443`) saýtyna geçirýär.
3. Yzyna **hakyky Microsoft sertifikaty** we hakyky TLS 1.3 handshake gaýdýar.

Netijede DPI adaty HTTPS birikmäni görýär — "proxy belligi" ýok. Üstesine, DPI serwere göni birigip barlasa (**active probing**), şol SNI bilen hakyky microsoft jogabyny alýar.

> Şol sebäpli **dest we SNI hökmany suratda deň bolmaly**: `dest = www.microsoft.com:443`, `serverNames = www.microsoft.com`.

**SNI saýlamagyň 5 şerti:**

| # | Şert | Nädip barlamaly |
|---|---|---|
| 1 | TLS 1.3 + X25519 goldaýar | `bash vpn/sni-test.sh` |
| 2 | ALPN `h2` goldaýar | şol bir skript |
| 3 | Sertifikat hakyky CA-dan | şol bir skript |
| 4 | **Müşderiniň torbasynda bloklanan DÄL** ← iň esasy | telefondan VPN-siz `https://<SNI>` açyp gör |
| 5 | Uly, "bitewilikli" domen, seniňki däl | microsoft, apple, samsung, nvidia, adobe... |

**4-nji şert näme üçin möhüm?** Türkmenistanda köplenç "gadagan sanaw" däl, **ak sanaw** işleýär. Eger `www.microsoft.com` hem şol ýerde bloklanan bolsa, klient handshake-iň ilkinji ädiminde ýykylýar — serwerde bolsa hemme zat "işleýän" görünýär. Şol sebäpli SNI-ny **müşderiniň torbasyndan** barlamaly.

**Goşmaça maslahatlar:**

- Serwere ýakyn (ping az) domen saýla — her birikmede goşmaça gidiş-geliş ýüze çykýar.
- CDN arkasyndaky domenler (Cloudflare) kabul edilýär, ýöne käbir ýagdaýda geçiş durnuksyz bolýar → ilki CDN-siz domeni synap gör.
- Öň VPN/proxy hyzmaty hökmünde tanalýan domenleri **ulanma**.
- Bir SNI-ni ýyllap ulanma — 2–3 aýdan çalyşmak DPI-de "bellik" döretmez.
- Bir serwerde **2–3 dürli SNI** bilen inbound goý: biri bloklansa beýlekisi işlär.

**Barlag skripti:**

```bash
bash vpn/sni-test.sh                        # taýýar kandidatlar
bash vpn/sni-test.sh www.apple.com www.bing.com
bash vpn/sni-test.sh --dest                 # saýlamak boýunça gysga maslahat
```

Çykyş: DNS, TCP 443, TLS 1.3, ALPN, sertifikat, möhlet, ping we netije (GOWY / ORTA / ERBET).

Soň **Add Client**: e-poçta (`user-01`), Flow `xtls-rprx-vision`, trafik çäklendirmesi. Soň QR kody ýa-da `vless://...` linki bilen paýlaş.

### 5.5. AmneziaWG goşmak (ätiýaçlyk protokol)

3x-ui 3.x wersiýasynda **AmneziaWG** içinde bar (userspace, kernel moduly gerek däl).

**Inbounds → Add Inbound → Protocol: `amneziawg`**, port `51820` (UDP), `JC/JMIN/JMAX`, `S1/S2`, `H1–H4` parametrleri — standart bahalary goý, bloklansa üýtgedip gör.

> AmneziaWG — WireGuard-yň "ýasamak" wersiýasy: junk paketler + tötänleýin header. DPI-de adaty WG-den has gowy durýar.
> Müşderi tarapynda **Amnezia VPN** programmasy ýa-da AmneziaWG goldaýan klient gerek.

### 5.6. Barlag

```bash
bash vpn/check.sh
```

Çykýar: portlar, hyzmatlar, BBR, internet tizligi, DNS, ping, Reality SNI-lary, panel ýagdaýy. SNI kandidatlaryny jikme-jik barlamak üçin: `bash vpn/sni-test.sh`. Şeýle hem telefondan synap gör — işlemeýän zady maslahatlaşmazdan öň barla.

Goşmaça: `bash vpn/check.sh --speed` — tizlik ölçegi; `--quiet` — diňe problemalary görkez.

### 5.7. Müşderi goşmak we subscription

1. Inbound-y açyň → **Add Client**.
2. Her müşderä aýratyn:
   - e-poçta/at (`ahmet-01`),
   - **trafik limiti** (meselem 100 GB),
   - **möhleti** (meselem 30 gün),
   - **IP limiti** (bir wagtyň özünde 2–3 enjam).
3. Soň şol klientiň hatarynda **QR** ýa-da **link** düwmesi — `vless://...` çykýar.

**Subscription (iň amatly):**

- 3X-UI-de **Settings → Subscription** açyň (port, ýol, `sub` prefiksi).
- Her müşderiniň öz subscription URL-i bolýar; klient ony awtomatik täzeläp durýar.
- Müşderi linki ýitirse — positive täze link döretmek ýerine şol bir subscription-y ber.

> Müşderiniň e-poçtasyny hakyky e-poçta hökmünde ulanmaň (şahsy maglumat). Diňe belgi hökmünde `user-01` ýazyň.

---

### 5.8. Türkmenistan şertlerinde hakykatlar

Bu iň möhüm bölüm — hyzmat satmazdan öň hökmany okaň.

| Hakykat | Manysy |
|---|---|
| **Ak sanaw (whitelist)** | Turkmenistanda köplenç "gadagan sanaw" däl, **rugsat edilen sanaw** işleýär. Şol sebäpli täze IP-ler köplenç ilkinji günlerden elli ýapylýar. |
| **Täze IP = 1–7 gün** | Reality-de işleýän serwer hem birnäçe gün/henizem sagatdan soň "timeout" bolup biler. Şonuň üçin **bir serwer = bir hyzmat däl**. |
| **UDP agyr** | WireGuard/AmneziaWG/Hysteria2 UDP paketleri köplenç throttle edilýär ýa-da doly ýapylýar. Esasy 443/TCP bolmaly. |
| **Tizlik çäkli** | Milli çäk ~2–6 Mbit. 4K wideo hakda gürleşmek kyn; esasy maksat — web, Telegram, iş gurallary. |
| **Diňe DNS bilen** | Gaty ýagdaýda diňe DNS (UDP/53) we käbir CDN-ler geçýär. Şeýle ýerde `dnstt`/`slipstream` (DNS tunnel) ýaly usullar işleýär, ýöne tizligi örän az (birnäçe kbit). |
| **CDN fronting** | Gcore/Cloudflare ýaly CDN-leriň IP-leri ak sanawda bolýar. `VLESS+XHTTP+TLS+CDN` şol ýerde işleýär — domen we TLS hökmany. |

**Praktiki maslahat:**

1. **Öň synap gör, soň sat.** 2–3 dürli ýer (DE, NL, BG) we 2–3 dürli protokol bilen 1–2 hepde synag edip, haýsysynyň durnuklydygyny anykla.
2. Müşderä "100% işleýär" diýip wada bermä — DPI her hepde üýtgeýär.
3. Her müşderä **2 profil** ber (Reality + AmneziaWG / CDN), biri işlemese beýlekisi.
4. Bloklanan IP-ni derrew çalyşmak üçin **snapshot + täze IP** meýilnamasyny öňünden taýýarla.
5. Satuwda **kanuny töwekgelçiligi** aç-açan aýt (aşakda 10-njy bölüm).

---

## 6. Goşmaça näme baglap bolýar

| Zat | Näme üçin | Nädip |
|---|---|---|
| **Domen** (~$10/ýyl) | Subscription linkler, TLS, CDN, panel salgysy; IP üýtsene müşderileriň sazlamasy bozulmaýar | Cloudflare-de domen al, A-ýazgyny VPS IP-sine goý |
| **Cloudflare (free)** | DNS + CDN + gizlinlik | NS-leri Cloudflare-e geçir. *Reality üçin proxy däl, "DNS only" goý!* |
| **TLS sertifikat** | XHTTP+TLS / Trojan üçin | 3x-ui menýusynda `SSL Certificate Management` (Let's Encrypt / acme.sh) |
| **Telegram bot** | Müşderä trafik gutardy barada habar, link paýlaşmak | 3x-ui → Settings → Telegram Bot (token + chat ID) |
| **Monitoring** | Serwer ölse/gaýtsa habar | Uptime Kuma (başga ýerde) ýa-da Netdata/Beszel |
| **Backup** | Panel + ulanyjylar ýitmesin | `bash vpn/setup.sh backup` + cron; başga serwere göçür |
| **2-nji serwer** | IP bloklananda hyzmat durmasyn | Başga hoster/ASN, başga IP; subscription-da 2 profil |
| **Töleg/algy** | Hyzmat satylsa | Telegram bot + kripto (USDT TRC-20) iň ýönekeý; karta üçin lokal töleg aggregatory |
| **Logs = 0** | Müşderiniň mertebesi + kanuny arkaýynlyk | Xray-de access log öçürip goý (`/var/log/xray/access.log` dereesini `none`) |

**Näme goşmak gerek däl:** "anti-DPI" diýen gümürtik skriptler, Telegram-dan satylýan "premium panel", nätanyş adamdan SSH açar. Bularyň köpüsi şaýylyk (backdoor).

---

## 7. Howpsuzlyk çeklisti

- [ ] SSH: parol däl, **açar** bilen; `PermitRootLogin prohibit-password`
- [ ] `fail2ban` işleýär (`fail2ban-client status sshd`)
- [ ] UFW açyk, diňe 22/80/443/51820
- [ ] Panel porty dünýäden ýapyk (SSH tunel)
- [ ] Panelde 2FA (3x-ui goldaýar) + güýçli parol
- [ ] Her ulanyja aýratyn UUID; "hemmelere bir link" ýok
- [ ] Trafik çäklendirmesi (bir ulanyjy kanaly doldurmasyn)
- [ ] Awtomatik täzelenme açyk (`unattended-upgrades`)
- [ ] Backup cron + başga ýerde kopiýa
- [ ] Provider bilen VPN reselling barada ýazmaça ylalaşyk

---

## 8. Müşderi (klient) programmalary

| Platforma | Programmа | Bellik |
|---|---|---|
| Android | **v2rayNG**, Hiddify, NekoBox | APK-ny öňünden göçürip al (App Store/Play bloklanan bolmagy mümkin) |
| iOS | **Streisand**, FoXray, Hiddify, Shadowrocket (pully) | iOS-da Reality goldaýan klientler az; subscription link amatly |
| Windows | **v2rayN**, Hiddify, NekoRay/Throne | |
| macOS | **Hiddify**, V2Box, Streisand | |
| Linux | sing-box, xray-core, Hiddify | |
| AmneziaWG | **Amnezia VPN** (ähli platforma) | `.conf` faýly import edýär |

**Subscription link** — iň amatly usul: ulanyja bir URL berýärsiň, klient özi täzeläp durýar. 3x-ui-de `Subscription` açyp, her müşderä aýratyn link ber.

---

## 9. Köp duş gelýän problemalar

| Alamaty | Sebäbi | Çözgüdi |
|---|---|---|
| Klient "connected" ýöne internet ýok | DNS ýa-da routing | Klientde DNS `1.1.1.1` / `8.8.8.8` goý; `check.sh` bilen serweriň özüni barla |
| Ilkinji gün işleýär, soň "timeout" | IP bloklandy (SNI-dan) | Täze IP (providerden), SNI/port üýtget, AmneziaWG görnüşine geç |
| Diňe 443 açylýar, beýleki portlar ýok | Provider firewall | Provider panelinde port aç; UFW-de barla |
| Serwerde hemme zat gowy, klient birigip bilmeýär | **SNI müşderiniň torbasynda bloklanan** | Telefondan VPN-siz şol domeni açyp gör; açylmasa başga SNI (`sni-test.sh`) |
| Tizlik 1–2 Mbit | 100 Mbit port + DPI throttling | Has gowy plan (1 Gbit), başga ýer (DE/NL), BBR açykmy barla |
| `curl` serwerde işleýär, telefondan ýok | Ýerli ISP bloky | XHTTP+CDN ýa-da AmneziaWG; başga port |
| Panel açylmaýar | Panel diňe 127.0.0.1-de; SSH tunel gerek | `ssh -N -L PORT:127.0.0.1:PORT root@IP`, soň `http://127.0.0.1:PORT/ÝOL`; barla: `systemctl status x-ui` |
| `x-ui` "command not found" | Gurnama düşmedi | `bash vpn/setup.sh 3xui --yes` gaýtadan |
| 3X-UI gurnalmaýar, `curl` 404/403 | GitHub/DPI blok | Installer-i başga ýerden göçürip al, `--installer /root/install.sh` bilen gur |

---

## 10. Kanuny bellik

- VPN hyzmatyny **satmak** — ýurduň telekom kanunlaryna, salgyt hasabyna we provideriň AUP-sine degişli. Öňünden anyklap al.
- Müşderiniň hereketleri üçin jogapkärçilik (spam, botnet, fraud) — **log ýazmaýan** bolsaň-da, AB/BG kanuny boýunça abuse habarlaryna jogap bermeli bolýarsyň.
- Käbir ýurtlarda VPN ulanmak/satmak gadagan. Bu gollanma diňe **tehniki bilim** üçin; kanuny tarapyny özüň barlamaly.
- Şahsy maglumatlary (e-poçta, töleg) ýygnasaň — GDPR ýaly düzgünlere degişli bolýar.

---

## Faýllar

| Faýl | Näme edýär |
|---|---|
| `harden.sh` | Serweri taýýarlaýar: BBR, swap, UFW, fail2ban, awtomatik täzelleme |
| `setup.sh` | Menýu: `harden`, `3xui`, `marzban`, `backup`, `check`, `info` |
| `check.sh` | Diagnostika: portlar, hyzmatlar, tizlik, DNS, ping, Reality SNI |
| `sni-test.sh` | Reality SNI kandidatlaryny barlaýar: TLS 1.3, ALPN h2, sertifikat, ping |

**setup.sh parametrleri:** `--yes` (soramazdan), `--dry-run` (hiç zat üýtgetmän görkez), `--panel-port N`,
`--panel-public`, `--domain` + `--email` (panel SSL), `--installer FILE` (ýerli install.sh), `--out DIR` (backup).

```bash
sudo bash vpn/harden.sh --yes         # serwer taýýarla
sudo bash vpn/setup.sh 3xui --yes     # panel gur (maglumatlary ekrana çykarýar)
sudo bash vpn/setup.sh info           # panel maglumatlaryny ýene gör
sudo bash vpn/check.sh                # barla (--speed goşup bilersiň)
bash vpn/sni-test.sh                  # Reality SNI kandidatlaryny barla
sudo bash vpn/setup.sh backup         # backup al
```
