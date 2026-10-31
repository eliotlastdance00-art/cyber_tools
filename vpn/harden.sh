#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# cyber_tools · vpn/harden.sh
#
# VPS-ni VPN node hökmünde taýýarlaýar:
#   · Howpsuzlyk täzelenmesi (unattended-upgrades)
#   · BBR + fq, TCP tuning, MTU probing
#   · Swap (RAM 2 GB-dan az bolsa)
#   · UFW firewall (22, 80, 443/tcp, 443/udp, 51820/udp)
#   · fail2ban (sshd jail)
#   · journald log çäklendirmesi
#   · (islege görä) SSH-ny diňe açar bilen galdyrmak
#
# Ulanylyşy:
#   sudo bash harden.sh              # interaktiw tassyklama
#   sudo bash harden.sh --yes        # soramazdan
#   sudo bash harden.sh --dry-run    # diňe näme ediljekdigini görkez
#   sudo bash harden.sh --ssh-strict # SSH: parol öçürilýär (açar bar bolsa)
#
# Goldanýan OS: Debian 11/12/13, Ubuntu 22.04/24.04
# ---------------------------------------------------------------------------
set -Eeuo pipefail

# root-yň adaty PATH-y (interaktiw däl shellerde /sbin ýok bolmagy mümkin)
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

DRY_RUN=0
ASSUME_YES=0
SSH_STRICT=0

# ------------------------------- kömekçiler --------------------------------
c_reset=$'\033[0m'; c_cyan=$'\033[1;36m'; c_yellow=$'\033[1;33m'
c_red=$'\033[1;31m'; c_green=$'\033[1;32m'; c_dim=$'\033[2m'

log()  { printf '%s[harden]%s %s\n' "$c_cyan" "$c_reset" "$*"; }
ok()   { printf '%s  ✓%s %s\n' "$c_green" "$c_reset" "$*"; }
warn() { printf '%s[warn]%s %s\n' "$c_yellow" "$c_reset" "$*" >&2; }
die()  { printf '%s[error]%s %s\n' "$c_red" "$c_reset" "$*" >&2; exit 1; }

usage() {
  sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

run() {
  if (( DRY_RUN )); then
    printf '  %s+ %s%s\n' "$c_dim" "$*" "$c_reset"
    return 0
  fi
  "$@"
}

# write_root_file <path> [mode]   (mazmuny stdin-dan)
write_root_file() {
  local path=$1 mode=${2:-0644} content tmp
  content=$(cat)
  if (( DRY_RUN )); then
    printf '  %s+ write %s (%s simwol)%s\n' "$c_dim" "$path" "${#content}" "$c_reset"
    return 0
  fi
  mkdir -p "$(dirname "$path")"
  tmp=$(mktemp)
  printf '%s\n' "$content" >"$tmp"
  install -m "$mode" "$tmp" "$path"
  rm -f "$tmp"
}

confirm() {
  (( ASSUME_YES )) && return 0
  local answer
  read -r -p "$1 [ý/Ý = hawa, beýleki = ýok] " answer
  [[ $answer =~ ^[yýYÝ]$ ]]
}

# --------------------------------- argumentler -----------------------------
for arg in "$@"; do
  case $arg in
    -n|--dry-run)  DRY_RUN=1 ;;
    -y|--yes)      ASSUME_YES=1 ;;
    --ssh-strict)  SSH_STRICT=1 ;;
    -h|--help)     usage ;;
    *) die "Nämälim parametr: $arg  (--help)" ;;
  esac
done

(( EUID == 0 )) || (( DRY_RUN )) || die "Root hökmünde işlediň:  sudo bash $0"

# --------------------------------- OS barlagy ------------------------------
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  case ${ID:-} in
    debian|ubuntu) ok "OS: ${PRETTY_NAME:-$ID}" ;;
    *) warn "OS '${ID:-näbelli}' — skript Debian/Ubuntu üçin ýazylan. Dowam etseň döwülmegi mümkin." ;;
  esac
else
  warn "/etc/os-release ýok — OS anyklanmady."
fi

command -v systemctl >/dev/null || die "systemd tapylmady (konteýner?)"

# SSH portuny anyklamak
SSH_PORT=""
if command -v sshd >/dev/null 2>&1; then
  SSH_PORT=$(sshd -T 2>/dev/null | awk 'tolower($1)=="port"{print $2; exit}' || true)
fi
if [[ -z $SSH_PORT ]]; then
  SSH_PORT=$(ss -H -tlnp 2>/dev/null | awk '/sshd/{n=split($4,a,":"); if(n>1) print a[n]; exit}' || true)
fi
SSH_PORT=${SSH_PORT:-22}
ok "SSH porty: ${SSH_PORT}"

# --------------------------------- başla -----------------------------------
log "VPN node üçin serwer taýýarlanýar$( ((DRY_RUN)) && echo ' (DRY-RUN)')"

confirm "Dowam edilsinmi? (BBR, swap, UFW, fail2ban goýlar)" || die "Ýatyryldy."

# 1) Paketler ---------------------------------------------------------------
log "1/8 Paketler goýulýar"
run env DEBIAN_FRONTEND=noninteractive apt-get update -qq
run env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
  curl ca-certificates ufw fail2ban unattended-upgrades jq htop \
  net-tools dnsutils iputils-ping procps

# 2) sysctl: BBR + tuning ---------------------------------------------------
log "2/8 BBR we TCP tuning"
write_root_file /etc/sysctl.d/99-cybertools-vpn.conf <<'EOF'
# cyber_tools · VPN node tuning
# --- BBR (Google congestion control) ---
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_notsent_lowat = 16384

# --- buferler ---
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.core.somaxconn = 4096
net.ipv4.tcp_max_syn_backlog = 8192

# --- port aralygy ---
net.ipv4.ip_local_port_range = 10240 65000
fs.file-max = 1000000

# --- forwarding (VPN üçin hökmany) ---
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# --- gorag ---
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
vm.swappiness = 10
EOF
run sysctl --system >/dev/null
if (( DRY_RUN )); then
  ok "BBR: (dry-run)"
else
  ok "BBR: $(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || echo —)"
fi

# 3) Swap -------------------------------------------------------------------
log "3/8 Swap barlanýar"
mem_kb=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
has_swap=$(awk 'NR>1{n++} END{print n+0}' /proc/swaps)
if (( has_swap > 0 )); then
  ok "Swap eýýäm bar"
elif (( mem_kb >= 1900000 )); then
  ok "RAM ýeterlik ($(( mem_kb / 1024 )) MB) — swap gerek däl"
else
  log "RAM az ($(( mem_kb / 1024 )) MB) — 1 GB swap döredilýär"
  if (( ! DRY_RUN )); then
    if [[ ! -f /swapfile ]]; then
      fallocate -l 1G /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count=1024 status=none
      chmod 600 /swapfile
      mkswap -q /swapfile >/dev/null
    fi
    swapon /swapfile 2>/dev/null || true
    grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >>/etc/fstab
    ok "Swap açyk"
  else
    printf '  %s+ 1G swap (/swapfile) + fstab%s\n' "$c_dim" "$c_reset"
  fi
fi

# 4) fail2ban ---------------------------------------------------------------
log "4/8 fail2ban (sshd)"
write_root_file /etc/fail2ban/jail.d/cybertools-sshd.local <<EOF
[sshd]
enabled  = true
backend  = systemd
port     = ${SSH_PORT}
maxretry = 4
findtime = 10m
bantime  = 1h
bantime.increment = true
bantime.factor    = 2
bantime.maxtime   = 1w
EOF
run systemctl enable --now fail2ban

# 5) UFW --------------------------------------------------------------------
log "5/8 UFW firewall"
run ufw --force default deny incoming
run ufw --force default allow outgoing
run ufw limit "${SSH_PORT}/tcp" comment 'ssh'
run ufw allow 80/tcp   comment 'http-acme'
run ufw allow 443/tcp  comment 'reality'
run ufw allow 443/udp  comment 'hysteria2'
run ufw allow 51820/udp comment 'wireguard'
run ufw --force enable
ok "UFW: $( ((DRY_RUN)) && echo '(dry-run)' || true )"

# 6) Awtomatik täzelenme ----------------------------------------------------
log "6/8 Awtomatik howpsuzlyk täzelenmesi"
write_root_file /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
run systemctl enable --now unattended-upgrades.service

# 7) Loglar -----------------------------------------------------------------
log "7/8 journald log çäklendirmesi"
write_root_file /etc/systemd/journald.conf.d/99-cybertools.conf <<'EOF'
[Journal]
SystemMaxUse=200M
SystemMaxFileSize=50M
MaxRetentionSec=2week
EOF
run systemctl restart systemd-journald

# 8) SSH (islege görä) ------------------------------------------------------
log "8/8 SSH barlagy"
key_count=0
[[ -s /root/.ssh/authorized_keys ]] && key_count=$(grep -cE '^(ssh-|ecdsa-)' /root/.ssh/authorized_keys || true)

if (( SSH_STRICT )); then
  if (( key_count == 0 )); then
    warn "SSH açar tapylmady — --ssh-strict bilen parol öçürilseňiz serwere girip bilmersiňiz!"
    warn "Ilki 'ssh-copy-id root@IP' ediň, soň gaýtadan işlediň."
  else
    write_root_file /etc/ssh/sshd_config.d/99-cybertools.conf <<'EOF'
PermitRootLogin prohibit-password
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
EOF
    if (( DRY_RUN )); then
      printf '  %s+ sshd_config barlagy we reload%s\n' "$c_dim" "$c_reset"
    else
      if sshd -t; then
        systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
        ok "SSH: parol öçürildi, diňe açar"
      else
        rm -f /etc/ssh/sshd_config.d/99-cybertools.conf
        warn "sshd konfigurasiýasy nätogry — üýtgeşme yzyna gaýtaryldy"
      fi
    fi
  fi
else
  if (( key_count == 0 )); then
    warn "Root üçin SSH açar ýok. Maslahat: 'ssh-copy-id root@IP' edip, soň --ssh-strict bilen gaýtadan işled."
  else
    ok "SSH açar bar ($key_count) — isleseň --ssh-strict bilen paroly öçür"
  fi
fi

# --------------------------------- jemleme ---------------------------------
echo
log "Taýýar. Jemleme:"
(( DRY_RUN )) || {
  printf '  %sBBR%s        : %s\n' "$c_cyan" "$c_reset" "$(cat /proc/sys/net/ipv4/tcp_congestion_control 2>/dev/null || echo —)"
  printf '  %sQdisc%s      : %s\n' "$c_cyan" "$c_reset" "$(cat /proc/sys/net/core/default_qdisc 2>/dev/null || echo —)"
  printf '  %sIP forward%s : %s\n' "$c_cyan" "$c_reset" "$(cat /proc/sys/net/ipv4/ip_forward 2>/dev/null || echo —)"
  printf '  %sUFW%s        : %s\n' "$c_cyan" "$c_reset" "$(ufw status 2>/dev/null | head -1)"
  printf '  %sfail2ban%s   : %s\n' "$c_cyan" "$c_reset" "$(systemctl is-active fail2ban 2>/dev/null || true)"
  printf '  %sSwap%s       : %s\n' "$c_cyan" "$c_reset" "$(awk 'NR>1{s+=$3} END{if(s) printf "%d MB", s/1024; else printf "ýok"}' /proc/swaps)"
  echo
  log "Indiki ädim:  bash setup.sh 3xui --yes"
}
