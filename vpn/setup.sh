#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# cyber_tools · vpn/setup.sh
#
# Menýu-dispetçer:
#   harden     serweri taýýarlaýar (harden.sh-iň üsti bilen)
#   3xui       3X-UI panelini gurnýar (VLESS+Reality, AmneziaWG, Hysteria2)
#   marzban    Marzban panelini gurnýar (köp ulanyjy / köp node)
#   backup     panel bazasyny, sertifikatlary, konfigurasiýalary arhiwleýär
#   check      diagnostika (check.sh)
#   info       gurnalnan panel maglumatlaryny görkezýär
#
# Ulanylyşy:
#   sudo bash setup.sh 3xui --yes
#   sudo bash setup.sh 3xui --yes --panel-port 2087
#   sudo bash setup.sh 3xui --yes --panel-public        # panel dünýäden açyk
#   sudo bash setup.sh 3xui --yes --domain vpn.example.com --email me@example.com
#   sudo bash setup.sh backup --out /root
#
# Bellik: panel durnuklylygy üçin 3X-UI-niň resmi install.sh-y ulanylýar,
#     şonuň üçin kredensiallar installeriň özi döredýär we
#     /etc/x-ui/install-result.env faýlynda saklanýar (chmod 600).
# ---------------------------------------------------------------------------
set -Eeuo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

c_reset=$'\033[0m'; c_cyan=$'\033[1;36m'; c_yellow=$'\033[1;33m'
c_red=$'\033[1;31m'; c_green=$'\033[1;32m'; c_dim=$'\033[2m'

log()  { printf '%s[setup]%s %s\n' "$c_cyan" "$c_reset" "$*"; }
ok()   { printf '%s  ✓%s %s\n' "$c_green" "$c_reset" "$*"; }
warn() { printf '%s[warn]%s %s\n' "$c_yellow" "$c_reset" "$*" >&2; }
die()  { printf '%s[error]%s %s\n' "$c_red" "$c_reset" "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
cyber_tools · vpn/setup.sh

Amallar:
  harden     serweri taýýarlaýar (BBR, UFW, fail2ban, swap)
  3xui       3X-UI panelini gurnýar (VLESS+Reality, AmneziaWG, Hysteria2)
  marzban    Marzban panelini gurnýar (köp ulanyjy / köp node)
  backup     panel bazasyny, sertifikatlary, konfigurasiýalary arhiwleýär
  check      diagnostika (check.sh; --speed / --quiet geçirilýär)
  info       gurnalnan panel maglumatlaryny görkezýär

Parametrler:
  -y, --yes             soramazdan tassykla
  -n, --dry-run         hiç zat üýtgetmän, näme ediljekdigini görkez
  --panel-port N        3X-UI panel porty (adaty: tötänleýin 20000-60000)
  --panel-public        paneli dünýäden aç (SSL hökmany!)
  --domain DOMAIN       panel üçin Let's Encrypt sertifikaty
  --email EMAIL         Let's Encrypt hasap e-poçtasy
  --installer FILE      ýerli install.sh nusgasy (internet ýok bolsa)
  --out DIR             backup katalogi (adaty: /root)

Mysallar:
  sudo bash setup.sh harden
  sudo bash setup.sh 3xui --yes
  sudo bash setup.sh 3xui --yes --domain vpn.example.com --email me@example.com
  sudo bash setup.sh backup --out /root
  sudo bash setup.sh check --speed
EOF
  exit 0
}

ASSUME_YES=0
PANEL_PORT=""
PANEL_PUBLIC=0
DOMAIN=""
EMAIL=""
OUT_DIR="/root"
INSTALLER=""
DRY_RUN=0
CHECK_ARGS=()
ACTION="${1:-help}"
[[ $ACTION == --* ]] && ACTION=help
[[ $ACTION != help ]] && shift || true

while [[ $# -gt 0 ]]; do
  case $1 in
    -y|--yes)         ASSUME_YES=1 ;;
    -n|--dry-run)     DRY_RUN=1 ;;
    --panel-port)     PANEL_PORT=${2:?--panel-port bahasy ýok}; shift ;;
    --panel-public)   PANEL_PUBLIC=1 ;;
    --domain)         DOMAIN=${2:?--domain bahasy ýok}; shift ;;
    --email)          EMAIL=${2:?--email bahasy ýok}; shift ;;
    --out)            OUT_DIR=${2:?--out bahasy ýok}; shift ;;
    --installer)      INSTALLER=${2:?--installer bahasy ýok}; shift ;;
    --speed)          CHECK_ARGS+=(--speed) ;;
    --quiet|-q)       CHECK_ARGS+=(--quiet) ;;
    -h|--help)        usage ;;
    *) die "Nämälim parametr: $1  (--help)" ;;
  esac
  shift
done

confirm() {
  (( ASSUME_YES )) && return 0
  local answer
  read -r -p "$1 [ý/Ý = hawa] " answer
  [[ $answer =~ ^[yýYÝ]$ ]]
}

need_root() { (( EUID == 0 || DRY_RUN )) || die "Root hökmünde işlediň: sudo bash $0 $ACTION"; }
have()      { command -v "$1" >/dev/null 2>&1; }

random_port() { shuf -i 20000-60000 -n 1 2>/dev/null || echo $(( (RANDOM % 40000) + 20000 )); }

# rand_str <uzynlyk> <belgiler>  — SIGPIPE-siz tötänleýin setir
rand_str() {
  local len=$1 cs=${2:-A-Za-z0-9} out=""
  while (( ${#out} < len )); do
    if have openssl; then
      out+=$(openssl rand -base64 96 2>/dev/null | LC_ALL=C tr -dc "$cs" || true)
    else
      out+=$(head -c 512 /dev/urandom 2>/dev/null | LC_ALL=C tr -dc "$cs" || true)
    fi
    # howpsuzlyk: çykgysyz bolsa aýlawy çäklendir
    [[ -z $out ]] && out="A1b2C3d4E5f6G7h8I9j0"
  done
  printf '%s' "${out:0:$len}"
}

# ---------------------------------------------------------------------------
# harden
# ---------------------------------------------------------------------------
do_harden() {
  local args=(--yes)
  (( DRY_RUN )) && args+=(--dry-run)
  [[ -x $SCRIPT_DIR/harden.sh ]] || die "harden.sh tapylmady: $SCRIPT_DIR"
  bash "$SCRIPT_DIR/harden.sh" "${args[@]}"
}

# ---------------------------------------------------------------------------
# 3xui
# ---------------------------------------------------------------------------
do_3xui() {
  need_root
  if [[ -x /usr/local/x-ui/x-ui ]]; then
    warn "3X-UI eýýäm gurnalgy görünýär."
    if ! confirm "Üstünden täzeden gurnalmalymy?"; then
      info_3xui
      return 0
    fi
  fi

  PANEL_PORT=${PANEL_PORT:-$(random_port)}
  if [[ ! $PANEL_PORT =~ ^[0-9]+$ ]] || (( PANEL_PORT < 2 || PANEL_PORT > 65535 )); then
    die "Panel porty nätogry: $PANEL_PORT (2-65535 bolmaly)"
  fi

  local base_path user pass
  base_path=$(rand_str 20 'a-z0-9')
  user=$(rand_str 10 'a-z0-9')
  pass=$(rand_str 20 'A-Za-z0-9')

  log "3X-UI gurnalýar (panel: 127.0.0.1:${PANEL_PORT}/${base_path})"

  local tmp
  tmp=$(mktemp /tmp/3xui-install.XXXXXX.sh)
  local urls=(
    "https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh"
    "https://github.com/MHSanaei/3x-ui/raw/master/install.sh"
  )
  local got=0 url
  if [[ -n $INSTALLER ]]; then
    [[ -r $INSTALLER ]] || die "installer faýly okamak bolmady: $INSTALLER"
    cp "$INSTALLER" "$tmp"; got=1
    log "Ýerli installer ulanylýar: ${INSTALLER}"
  else
    for url in "${urls[@]}"; do
      log "install.sh göçürilýär: ${url}"
      if curl -fsSL --retry 2 --connect-timeout 15 -o "$tmp" "$url" && head -1 "$tmp" | grep -q '^#!'; then
        got=1; break
      fi
    done
  fi
  (( got )) || die "install.sh göçürip bolmady — interneti/DPI-ny barla, ýa-da --installer FILE ulanyň."
  ok "install.sh taýýar ($(wc -l <"$tmp") setir)"

  if (( DRY_RUN )); then
    printf '  %s+ XUI_NONINTERACTIVE=1 XUI_PANEL_PORT=%s XUI_USERNAME=%s XUI_PASSWORD=*** XUI_WEB_BASE_PATH=%s bash %s%s\n' \
      "$c_dim" "$PANEL_PORT" "$user" "$base_path" "$tmp" "$c_reset"
    rm -f "$tmp"
    return 0
  fi

  local ssl_mode="none" extra_env=()
  if [[ -n $DOMAIN ]]; then
    ssl_mode="domain"
    extra_env=(XUI_DOMAIN="$DOMAIN")
    [[ -n $EMAIL ]] && extra_env+=(XUI_ACME_EMAIL="$EMAIL")
    log "Panel üçin Let's Encrypt sertifikaty: ${DOMAIN} (80-nji port açyk bolmaly)"
  fi

  env XUI_NONINTERACTIVE=1 \
      XUI_USERNAME="$user" XUI_PASSWORD="$pass" \
      XUI_PANEL_PORT="$PANEL_PORT" XUI_WEB_BASE_PATH="$base_path" \
      XUI_SSL_MODE="$ssl_mode" ${extra_env[@]+"${extra_env[@]}"} \
      bash "$tmp" || die "3X-UI gurnamasy şowsuz — ýokardaky loglara seret."
  rm -f "$tmp"

  # Panel diňe lokal interfeýsde diňlär (SSH tunel arkaly girilýär).
  if (( ! PANEL_PUBLIC )); then
    if /usr/local/x-ui/x-ui setting -listenIP "127.0.0.1" >/dev/null 2>&1; then
      ok "Panel diňe 127.0.0.1-de diňleýär (dünýäden ýapyk)"
    else
      warn "listenIP sazlamady — UFW-de panel portyny elde ýap: ufw deny ${PANEL_PORT}/tcp"
    fi
    /usr/local/x-ui/x-ui restart >/dev/null 2>&1 || true
  else
    ufw allow "${PANEL_PORT}/tcp" comment 'x-ui panel' >/dev/null 2>&1 || true
    warn "Panel dünýäden açyk — hökmany suratda SSL goý we güýçli paroly sakla!"
  fi

  echo
  printf '%s╔══════════════════════════════════════════════════════════╗%s\n' "$c_green" "$c_reset"
  printf '%s║  3X-UI taýýar                                            ║%s\n' "$c_green" "$c_reset"
  printf '%s╚══════════════════════════════════════════════════════════╝%s\n' "$c_green" "$c_reset"
  printf '  Panel URL   : %shttp://127.0.0.1:%s/%s%s  (diňe SSH tunel bilen)\n' "$c_cyan" "$PANEL_PORT" "$base_path" "$c_reset"
  printf '  Ulanyjy     : %s%s%s\n' "$c_cyan" "$user" "$c_reset"
  printf '  Parol       : %s%s%s\n' "$c_cyan" "$pass" "$c_reset"
  printf '  SSH tunel   : ssh -N -L %s:127.0.0.1:%s root@SERWER_IP\n' "$PANEL_PORT" "$PANEL_PORT"
  printf '  Soň brauzer : http://127.0.0.1:%s/%s\n' "$PANEL_PORT" "$base_path"
  echo
  warn "Şu maglumatlary HOWPSUZ ýerde sakla. Panelde 2FA açmagyňy maslahat berýärin."
  warn "Soňky ädim: panelde VLESS+Reality inbound goş (README, 5.4-nji bölüm)."
}

info_3xui() {
  local f=/etc/x-ui/install-result.env
  if [[ -r $f ]]; then
    # install.sh tarapyndan döredilen, %q bilen gaçyrylan faýl
    # shellcheck disable=SC1090
    . "$f"
    echo
    printf '%s3X-UI maglumatlary (%s)%s\n' "$c_cyan" "$f" "$c_reset"
    printf '  Ulanyjy : %s\n' "${XUI_USERNAME:-?}"
    printf '  Parol   : %s\n' "${XUI_PASSWORD:-?}"
    printf '  Port    : %s\n' "${XUI_PANEL_PORT:-?}"
    printf '  Ýol     : /%s\n' "${XUI_WEB_BASE_PATH:-?}"
    printf '  API tok : %s\n' "${XUI_API_TOKEN:-—}"
    printf '  URL     : %s\n' "${XUI_ACCESS_URL:-—}"
  else
    warn "Panel maglumatlary tapylmady ($f). 'x-ui settings' ýa-da 'x-ui' menýusyndan gör."
  fi
}

# ---------------------------------------------------------------------------
# marzban
# ---------------------------------------------------------------------------
do_marzban() {
  need_root
  if command -v marzban >/dev/null 2>&1; then
    warn "Marzban eýýäm gurnalgy."; return 0
  fi
  confirm "Marzban gurnalmalymy? (Docker + köp ulanyjy üçin; 2 GB RAM maslahat)" || return 1

  local tmp sb
  tmp=$(mktemp /tmp/marzban-scripts.XXXXXX.sh)
  log "Marzban skripti göçürilýär"
  sb="$(curl -fsSL --retry 2 https://raw.githubusercontent.com/Gozargah/Marzban-scripts/master/marzban.sh)" \
    || die "marzban.sh göçürip bolmady"
  printf '%s\n' "$sb" >"$tmp"

  if (( DRY_RUN )); then
    printf '  %s+ bash %s @ install%s\n' "$c_dim" "$tmp" "$c_reset"; rm -f "$tmp"; return 0
  fi

  bash "$tmp" @ install || die "Marzban gurnamasy şowsuz"
  rm -f "$tmp"
  ok "Marzban gurnaldy"
  echo
  log "Admin döretmek üçin:"
  echo "    marzban cli admin create --sudo"
  echo "    marzban status"
  echo "  Panel: http://SERWER_IP:8000/dashboard  (proxy/SSL-i özüň goý)"
  warn "Marzban 8000-nji porty dünýä açýar — UFW-de diňe proxy/SSH tunel üçin aç."
}

# ---------------------------------------------------------------------------
# backup
# ---------------------------------------------------------------------------
do_backup() {
  need_root
  mkdir -p "$OUT_DIR"
  local stamp out tmpd
  stamp=$(date -u +%Y%m%d-%H%M%S)
  out="$OUT_DIR/vpn-backup-${stamp}.tar.gz"
  tmpd=$(mktemp -d)

  log "Backup ýygnanýar"
  if [[ -d /etc/x-ui ]]; then
    install -d -m 700 "$tmpd/x-ui"; cp -a /etc/x-ui/. "$tmpd/x-ui/" 2>/dev/null || true
    ok "3X-UI bazasy"
  fi
  if [[ -d /root/cert ]]; then
    install -d -m 700 "$tmpd/cert"; cp -a /root/cert/. "$tmpd/cert/" 2>/dev/null || true
    ok "Sertifikatlar"
  fi
  [[ -f /etc/cybertools-vpn.info ]] && cp -a /etc/cybertools-vpn.info "$tmpd/" 2>/dev/null || true
  [[ -d /opt/marzban && -f /opt/marzban/.env ]] && { install -d -m 700 "$tmpd/marzban"; cp -a /opt/marzban/.env "$tmpd/marzban/" 2>/dev/null || true; ok "Marzban .env"; }
  [[ -d /etc/wireguard ]] && { install -d -m 700 "$tmpd/wireguard"; cp -a /etc/wireguard/. "$tmpd/wireguard/" 2>/dev/null || true; ok "WireGuard"; }

  if (( DRY_RUN )); then
    printf '  %s+ tar czf %s%s\n' "$c_dim" "$out" "$c_reset"; return 0
  fi

  ( umask 077; tar -czf "$out" -C "$tmpd" . )
  rm -rf "$tmpd"
  chmod 600 "$out"
  ok "Backup: ${out} ($(du -h "$out" | cut -f1))"
  warn "Bu faýlda panel paroly we Reality şahsy açary bar — başga ýere howpsuz göçür!"
}

# ---------------------------------------------------------------------------
# check / info
# ---------------------------------------------------------------------------
do_check() {
  [[ -x $SCRIPT_DIR/check.sh ]] || die "check.sh tapylmady"
  local args=(${CHECK_ARGS[@]+"${CHECK_ARGS[@]}"} "$@")
  bash "$SCRIPT_DIR/check.sh" ${args[@]+"${args[@]}"}
}

do_info() {
  info_3xui
  echo
  log "Hyzmatlar:"
  for svc in x-ui marzban fail2ban nginx; do
    if systemctl list-unit-files "${svc}.service" 2>/dev/null | grep -q "${svc}.service"; then
      printf '  %-10s %s\n' "$svc" "$(systemctl is-active "$svc" 2>/dev/null || true)"
    fi
  done
  echo
  log "Diňleýän portlar (protokol / port / salgy):"
  ss -H -tuln 2>/dev/null | awk '{
      addr=$5; n=split(addr, a, ":"); port=a[n];
      if (port == "*") port="—";
      printf "  %-4s %-6s %s\n", $1, port, addr
    }' | sort -k2,2n | uniq || true
}

case $ACTION in
  harden)   do_harden ;;
  3xui|xui) do_3xui ;;
  marzban)  do_marzban ;;
  backup)   do_backup ;;
  check)    do_check "$@" ;;
  info)     do_info ;;
  help|-h)  usage ;;
  *) die "Nämälim amal: ${ACTION}  (--help)" ;;
esac
