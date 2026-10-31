#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# cyber_tools · vpn/check.sh
#
# VPN node diagnostikasy — hiç zat üýtgetmeýär, diňe okaýar.
# Barlaýar: OS, ýük, ýadyň, disk, BBR, forwarding, portlar, hyzmatlar,
#           UFW, fail2ban, DNS, daşarky internet, Reality dest, wagt sinhrony.
#
# Ulanylyşy:
#   bash check.sh            # adaty barlag
#   bash check.sh --speed    # + tizlik ölçegi (~25 MB)
#   bash check.sh --quiet    # diňe problemalary görkez
# ---------------------------------------------------------------------------
set -uo pipefail

c_reset=$'\033[0m'; c_cyan=$'\033[1;36m'; c_yellow=$'\033[1;33m'
c_red=$'\033[1;31m'; c_green=$'\033[1;32m'; c_dim=$'\033[2m'

# UTF-8 locale bolsa, sütün deňleşdirme dogry bolar
if locale -a 2>/dev/null | grep -qiE '^C\.utf-?8$'; then export LC_ALL=C.UTF-8; fi

SPEED=0
QUIET=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --speed) SPEED=1 ;;
    --quiet|-q) QUIET=1 ;;
    -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Nämälim parametr: $1" >&2; exit 2 ;;
  esac
  shift
done

PROBLEMS=0
WARNS=0

section() { (( QUIET )) || printf '\n%s▌ %s%s\n' "$c_cyan" "$*" "$c_reset"; }

pad() { # pad <setir> <iniş>
  local s=$1 w=$2 n
  n=${#s}
  if (( n < w )); then printf '%s%*s' "$s" $(( w - n )) ''; else printf '%s' "$s"; fi
}

item() {
  local label=$1 value=${2:-—} status=${3:-ok}
  (( QUIET )) && [[ $status == ok ]] && return 0
  local mark color
  case $status in
    ok)   mark='✓'; color=$c_green ;;
    warn) mark='!'; color=$c_yellow; WARNS=$((WARNS+1)) ;;
    bad)  mark='✗'; color=$c_red;    PROBLEMS=$((PROBLEMS+1)) ;;
    *)    mark='·'; color=$c_dim ;;
  esac
  printf '  %s%s%s %s  %s\n' "$color" "$mark" "$c_reset" "$(pad "$label" 26)" "$value"
}

have() { command -v "$1" >/dev/null 2>&1; }

# sysctl okaýjy: /proc/sys-dan okaýar (sysctl PATH-da bolmasa-da işleýär)
sysval() {
  local file="/proc/sys/${1//.//}"
  if [[ -r $file ]]; then tr -d '[:space:]' <"$file"; else printf 'n/a'; fi
}

# ------------------------------- ulgam -------------------------------------
section "Ulgam"
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  item "OS" "${PRETTY_NAME:-$ID}" ok
fi
item "Kernel" "$(uname -r)" ok
item "Arhitektura" "$(uname -m)" ok
item "Uptime" "$(uptime -p 2>/dev/null | sed 's/^up //')" ok
item "Virtualizasiýa" "$(systemd-detect-virt 2>/dev/null || echo n/a)" ok

read -r load1 load5 load15 rest < /proc/loadavg
item "Load (1/5/15)" "${load1} / ${load5} / ${load15}" ok

mem_total=$(awk '/^MemTotal:/{printf "%d", $2/1024}' /proc/meminfo)
mem_avail=$(awk '/^MemAvailable:/{printf "%d", $2/1024}' /proc/meminfo)
mem_status=ok
(( mem_avail < 120 && mem_total <= 1024 )) && mem_status=warn
item "RAM" "${mem_avail} MB boş / ${mem_total} MB jemi" "$mem_status"

swap_mb=$(swapon --show --bytes --noheadings 2>/dev/null | awk '{s+=$3; n++} END{if(n) printf "%d", s/n/1048576; else print 0}')
swap_mb=${swap_mb:-0}
if (( swap_mb == 0 && mem_total < 2048 )); then
  item "Swap" "ýok (RAM az — swap goş)" warn
else
  item "Swap" "${swap_mb} MB" ok
fi

disk_use=$(df -P / | awk 'NR==2{gsub("%","",$5); print $5}')
disk_free=$(df -Ph / | awk 'NR==2{print $4}')
disk_status=ok
(( disk_use >= 90 )) && disk_status=bad
(( disk_use >= 75 && disk_use < 90 )) && disk_status=warn
item "Disk /" "${disk_use}% ulanyldy, ${disk_free} boş" "$disk_status"

# ---------------------------- tor performansy -------------------------------
section "Tor performansy"
qdisc=$(sysval net.core.default_qdisc)
cc=$(sysval net.ipv4.tcp_congestion_control)
if [[ $cc == bbr ]]; then
  item "Congestion control" "bbr / ${qdisc}" ok
else
  item "Congestion control" "${cc} / ${qdisc} (BBR maslahat)" warn
fi

fwd=$(sysval net.ipv4.ip_forward)
if [[ $fwd == 1 ]]; then
  item "IP forwarding" "açyk" ok
else
  item "IP forwarding" "ýapyk" warn
fi
item "MTU probing" "$(sysval net.ipv4.tcp_mtu_probing)" ok
item "File limit" "$(ulimit -n 2>/dev/null || echo n/a)" ok

# ------------------------------- hyzmatlar ---------------------------------
section "Hyzmatlar"
for svc in x-ui marzban hiddify-manager fail2ban ufw docker; do
  if systemctl list-unit-files "${svc}.service" 2>/dev/null | grep -q "${svc}.service"; then
    state=$(systemctl is-active "$svc" 2>/dev/null || true)
    if [[ $state == active ]]; then
      item "$svc" "işleýär" ok
    else
      item "$svc" "$state" bad
    fi
  fi
done
if systemctl list-unit-files 'wg-quick@*.service' 2>/dev/null | grep -q 'wg-quick@'; then
  for unit in $(systemctl list-units --type=service --all --no-legend 'wg-quick@*' 2>/dev/null | awk '{print $1}'); do
    item "$unit" "$(systemctl is-active "$unit" 2>/dev/null || true)" ok
  done
fi
have sing-box && item "sing-box" "$(sing-box version 2>/dev/null | head -1)" ok
have xray     && item "xray" "$(xray version 2>/dev/null | head -1)" ok

# --------------------------------- portlar ---------------------------------
section "Diňleýän TCP portlar"
if have ss; then
  ss -H -tlnp 2>/dev/null | awk '{
      addr=$4
      sub(/^\*:/, "0.0.0.0:", addr)
      sub(/^\[::\]:/, "[::]:", addr)
      n=split(addr, a, ":"); port=a[n]
      proc=""
      if (match($0, /users:\(\("[^"]+"/)) {
        proc=substr($0, RSTART, RLENGTH)
        sub(/^users:\(\("/, "", proc)
      }
      printf "  · %-6s %-22s %s\n", port, addr, proc
    }' | sort -k2,2n | while read -r line; do (( QUIET )) || echo "$line"; done
else
  item "ss" "tapylmady" warn
fi

# ---------------------------------- UFW ------------------------------------
section "Firewall"
if have ufw; then
  if ufw status 2>/dev/null | grep -q 'Status: active'; then
    item "UFW" "işjeň" ok
    if (( ! QUIET )); then
      ufw status numbered 2>/dev/null | sed -n '3,40p' | sed 's/^/    /'
    fi
  else
    item "UFW" "ýapyk" warn
  fi
else
  item "UFW" "gurnalman" warn
fi

# -------------------------------- fail2ban ---------------------------------
section "fail2ban"
if have fail2ban-client && systemctl is-active --quiet fail2ban 2>/dev/null; then
  jails=$(fail2ban-client status 2>/dev/null | awk -F: '/Jail list/{print $2}' | tr -d ' ')
  item "Jailler" "${jails:-ýok}" ok
  banned=$(fail2ban-client status sshd 2>/dev/null | awk -F'\t' '/Currently banned/{print $2}')
  item "SSH bans" "${banned:-0}" ok
else
  item "fail2ban" "işlemeýär" warn
fi

# ---------------------------------- DNS ------------------------------------
section "DNS we internet"
dns_start=$(date +%s%3N 2>/dev/null || echo 0)
if getent hosts one.one.one.one >/dev/null 2>&1; then
  dns_end=$(date +%s%3N 2>/dev/null || echo 0)
  item "DNS çözgüdi" "$(( dns_end - dns_start )) ms" ok
else
  item "DNS çözgüdi" "şowsuz" bad
fi

if have ping && ping -c2 -W3 1.1.1.1 >/dev/null 2>&1; then
  rtt=$(ping -c3 -W3 1.1.1.1 2>/dev/null | awk -F'/' '/rtt|round-trip/{print $5" ms"}')
  item "Ping 1.1.1.1" "${rtt:-ok}" ok
else
  item "Ping 1.1.1.1" "jogap ýok (ICMP ýapyk bolmagy mümkin)" warn
fi

for target in https://www.cloudflare.com/cdn-cgi/trace https://www.google.com/generate_204; do
  code=$(curl -s -o /dev/null -m 10 -w '%{http_code}' "$target" 2>/dev/null)
  [[ -z $code ]] && code=000
  host=${target#https://}; host=${host%%/*}
  if [[ $code =~ ^(200|204)$ ]]; then
    item "HTTPS $host" "HTTP $code" ok
  else
    item "HTTPS $host" "HTTP $code" bad
  fi
done

# --------------------------- Reality dest barlagy --------------------------
section "Reality dest (SNI) barlagy"
if [[ -r /etc/x-ui/x-ui.db ]] && have sqlite3; then
  mapfile -t dests < <(sqlite3 -noheader /etc/x-ui/x-ui.db \
      "select distinct remark||'|'||port from inbounds where protocol='vless';" 2>/dev/null || true)
  if (( ${#dests[@]} )); then
    for row in "${dests[@]}"; do
      item "Inbound" "${row/|/:}" ok
    done
  fi
fi
for sni in www.microsoft.com www.apple.com www.cloudflare.com; do
  if curl -sI -m 8 "https://${sni}" >/dev/null 2>&1; then
    item "TLS ${sni}" "elýeterli" ok
  else
    item "TLS ${sni}" "elýeterli däl (Reality üçin başga SNI saýla)" warn
  fi
done

# --------------------------------- panel ----------------------------------
section "Panel"
if [[ -r /etc/x-ui/install-result.env ]]; then
  # shellcheck disable=SC1091
  . /etc/x-ui/install-result.env
  item "3X-UI port" "${XUI_PANEL_PORT:-?}" ok
  item "3X-UI ýol" "/${XUI_WEB_BASE_PATH:-?}" ok
  item "3X-UI ulanyjy" "${XUI_USERNAME:-?}" ok
  if (( ! QUIET )); then
    printf '    %smaglumat: %s%s\n' "$c_dim" "/etc/x-ui/install-result.env" "$c_reset"
  fi
fi
panel_port=$(ss -H -tlnp 2>/dev/null | awk '/x-ui/ {n=split($4,a,":"); print a[n]; exit}')
if [[ -n ${panel_port:-} ]]; then
  listen_addr=$(ss -H -tlnp 2>/dev/null | awk -v p=":${panel_port}$" '$4 ~ p {print $4; exit}')
  case $listen_addr in
    127.0.0.1:*|\[::1\]:*) item "Panel diňleýär" "${listen_addr} (diňe lokal — gowy)" ok ;;
    *) item "Panel diňleýär" "${listen_addr} (dünýä açyk — SSL goý!)" warn ;;
  esac
fi

# ------------------------------- wagt sinhrony -----------------------------
section "Wagt"
if have timedatectl; then
  sync_state=$(timedatectl show -p NTPSynchronized --value 2>/dev/null || echo unknown)
  if [[ $sync_state == yes ]]; then
    item "NTP sinhron" "hawa" ok
  else
    item "NTP sinhron" "$sync_state" warn
  fi
  item "Wagt" "$(date -u '+%Y-%m-%d %H:%M UTC')" ok
fi

# -------------------------------- tizlik ----------------------------------
if (( SPEED )); then
  section "Tizlik ölçegi (ýükleme)"
  bytes=26214400
  out=$(curl -s -o /dev/null -m 45 -w '%{speed_download} %{time_total}' \
        "https://speed.cloudflare.com/__down?bytes=${bytes}" 2>/dev/null || echo "0 0")
  spd=${out%% *}; t=${out##* }
  mbps=$(awk -v b="$spd" 'BEGIN{printf "%.1f", b*8/1000000}')
  item "Ýükleme" "${mbps} Mbit/s (${t}s)" ok
  item "Ping Cloudflare" "$(curl -s -o /dev/null -m 10 -w '%{time_connect}s' https://speed.cloudflare.com/__down?bytes=0 2>/dev/null || echo n/a)" ok
fi

# -------------------------------- jemleme ---------------------------------
printf '\n'
if (( PROBLEMS == 0 && WARNS == 0 )); then
  printf '%sÄhli barlag gowy geçdi.%s\n' "$c_green" "$c_reset"
elif (( PROBLEMS == 0 )); then
  printf '%s%d duýduryş bar (ýokardaky ! belgiler).%s\n' "$c_yellow" "$WARNS" "$c_reset"
else
  printf '%s%d problem, %d duýduryş bar.%s\n' "$c_red" "$PROBLEMS" "$WARNS" "$c_reset"
fi
(( PROBLEMS == 0 )) || exit 1
