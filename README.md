# cyber_tools

Amaly gollanmalar we skriptler.

## VPN hyzmaty (VPS)

FriendHosting ýaly arzan VPS-de öz VPN hyzmatyňyzy gurmak we satmak üçin
doly gollanma + taýýar skriptler:

- **Gollanma:** [`vpn/README.md`](vpn/README.md) — hoster saýlamak, panel
  (3X-UI / Marzban / Hiddify), VLESS+Reality we AmneziaWG sazlamak,
  subscription, howpsuzlyk, Türkmenistan şertleri, nyrh we kanuny bellikler.
- **Taýýar skriptler:**
  - `vpn/harden.sh` — BBR, swap, UFW, fail2ban, awtomatik täzelenme
  - `vpn/setup.sh` — 3X-UI / Marzban gurmak, backup, info
  - `vpn/check.sh` — diagnostika (portlar, BBR, DNS, Reality SNI, tizlik)

Çalt başlangyç:

```bash
sudo bash vpn/harden.sh --yes      # serweri taýýarla
sudo bash vpn/setup.sh 3xui --yes  # paneli gur (kredensiallary çykarýar)
sudo bash vpn/check.sh             # barla
```
