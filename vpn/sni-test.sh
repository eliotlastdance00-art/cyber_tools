#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# cyber_tools · vpn/sni-test.sh
#
# Reality üçin SNI kandidatlaryny barlaýar:
#   · DNS çözgüdi            · TCP 443 ýoluň tizligi
#   · TLS 1.3 goldawy        · ALPN h2
#   · X25519 key exchange    · sertifikatyň dogrylygy we möhleti
#
# Ulanylyşy:
#   bash sni-test.sh                              # taýýar kandidatlar
#   bash sni-test.sh www.apple.com www.bing.com   # özüň saýlanlaryň
#   bash sni-test.sh --dest                       # diňe dest saýlamak üçin maslahat
#
# MÖHÜM: bu barlag SERWERDEN edilýär. Iň esasy barlag — MÜŞDERINIŇ torbasyndan
#        (meselem Türkmenistandan) şol domena girip bolýarmy? Eger ol ýerde
#        domen bloklanan bolsa, Reality hem işlemez.
# ---------------------------------------------------------------------------
set -uo pipefail

c_reset=$'\033[0m'; c_cyan=$'\033[1;36m'; c_yellow=$'\033[1;33m'
c_red=$'\033[1;31m'; c_green=$'\033[1;32m'; c_dim=$'\033[2m'

if locale -a 2>/dev/null | grep -qiE '^C\.utf-?8$'; then export LC_ALL=C.UTF-8; fi

DEFAULT_SNI=(
  www.microsoft.com
  www.apple.com
  www.bing.com
  www.cloudflare.com
  www.samsung.com
  www.nvidia.com
  www.adobe.com
  www.icloud.com
)

have() { command -v "$1" >/dev/null 2>&1; }
ms()   { date +%s%3N 2>/dev/null || echo 0; }

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

if [[ ${1:-} == --dest ]]; then
  cat <<'EOF'
Dest (SNI) saýlamak — bäş şert:

  1. TLS 1.3 goldaýar we X25519 key exchange bar        (bu skript barlaýar)
  2. ALPN h2 goldaýar                                    (bu skript barlaýar)
  3. Sertifikaty hakyky CA tarapyndan berlendir          (bu skript barlaýar)
  4. MÜŞDERINIŇ torbasynda BLOKLANMANDYR                ← iň esasy! elde barla
  5. Uly, hiç hili şübhe döretmeýän, seniňki däl domen    (meselem microsoft, apple)

Goşmaça:
  · Serwere ýakyn (ping az) — gije-gündiz işleýän hyzmat üçin latency möhüm
  · CDN arkasyndaky domenler (Cloudflare) kabul edilýär, ýöne käbir ýagdaýda
    geçiş durnuksyz bolýar → ilki göni (CDN-siz) domeni synap gör
  · Öň VPN/proxy hyzmaty hökmünde tanalýan domenleri ULANMA
  · Bir SNI-ni müňlerçe adam ulanýan bolsa, DPI-de "bellik" bolup biler —
    aýda bir gezek başga kandidata geçip durmak peýdaly

Mysallar: www.microsoft.com, www.apple.com, www.bing.com, www.samsung.com,
          www.nvidia.com, www.adobe.com, www.icloud.com
EOF
  exit 0
fi

[[ ${1:-} == -h || ${1:-} == --help ]] && usage

if (( $# > 0 )); then
  SNI_LIST=("$@")
else
  SNI_LIST=("${DEFAULT_SNI[@]}")
  echo "${c_dim}Berkitme: öz kandidatlaryňy bermek üçin: bash $0 domen1 domen2${c_reset}"
fi

have openssl || { echo "openssl gerek: apt install openssl" >&2; exit 1; }
have timeout || { echo "coreutils (timeout) gerek" >&2; exit 1; }

GOOD=0; BAD=0

check_one() {
  local host=$1 ip t0 t1 connect_ms tls_ms out proto alpn verify cn issuer days verdict reason

  printf '\n%s▌ %s%s\n' "$c_cyan" "$host" "$c_reset"

  if ! ip=$(getent ahostsv4 "$host" 2>/dev/null | awk 'NR==1{print $1}'); then
    printf '  %s✗ DNS%s  çözülmedi\n' "$c_red" "$c_reset"
    BAD=$((BAD+1)); return
  fi
  printf '  %s✓%s DNS            %s\n' "$c_green" "$c_reset" "$ip"

  # TCP connect wagty
  t0=$(ms)
  if ! timeout 8 bash -c "exec 3<>/dev/tcp/${host}/443" 2>/dev/null; then
    printf '  %s✗ TCP 443%s      birikip bolmady (domen ýapyk?)\n' "$c_red" "$c_reset"
    BAD=$((BAD+1)); return
  fi
  t1=$(ms); connect_ms=$(( t1 - t0 ))
  printf '  %s✓%s TCP 443        %s ms\n' "$c_green" "$c_reset" "$connect_ms"

  # TLS handshake (1.3, X25519, h2)
  t0=$(ms)
  out=$(timeout 12 openssl s_client -connect "${host}:443" -servername "$host" \
        -tls1_3 -alpn h2 -groups X25519 -verify_return_error </dev/null 2>&1)
  t1=$(ms); tls_ms=$(( t1 - t0 ))

  proto=$(printf '%s\n' "$out" | awk -F': *' '/^ *Protocol *:/{print $2; exit}')
  alpn=$(printf '%s\n' "$out" | awk -F': *' '/ALPN protocol:/{print $2; exit}')
  verify=$(printf '%s\n' "$out" | awk -F'return code: ' '/Verify return code/{print $2; exit}')
  cn=$(printf '%s\n' "$out" | awk -F'CN = ' '/subject=/{print $2; exit}')
  issuer=$(printf '%s\n' "$out" | awk -F' = ' '/issuer=/{print $NF; exit}')

  if [[ ${proto:-} != TLSv1.3 ]]; then
    printf '  %s✗ TLS 1.3%s      goldanmaýar (%s) — Reality üçin ýaramaz\n' \
      "$c_red" "$c_reset" "${proto:-baglanyşyk ýok}"
    BAD=$((BAD+1)); return
  fi
  printf '  %s✓%s TLS 1.3        %s ms\n' "$c_green" "$c_reset" "$tls_ms"

  if [[ ${alpn:-} == h2 ]]; then
    printf '  %s✓%s ALPN           h2\n' "$c_green" "$c_reset"
  else
    printf '  %s!%s ALPN           %s (h2 maslahat)\n' "$c_yellow" "$c_reset" "${alpn:-ýok}"
  fi

  if [[ ${verify:-} == 0* ]]; then
    printf '  %s✓%s Sertifikat     CN=%s · CA=%s\n' "$c_green" "$c_reset" "${cn:-?}" "${issuer:-?}"
  else
    printf '  %s✗ Sertifikat%s     barlag şowsuz: %s\n' "$c_red" "$c_reset" "${verify:-?}"
  fi

  days=$(printf '%s\n' "$out" | tr -d '\000' | openssl x509 -noout -enddate 2>/dev/null \
        | cut -d= -f2 | { read -r d; [[ -n $d ]] && echo $(( ( $(date -d "$d" +%s 2>/dev/null || echo 0) - $(date +%s) ) / 86400 )); })
  days=${days:-0}
  if (( days > 20 )); then
    printf '  %s✓%s Möhlet         %s gün galdy\n' "$c_green" "$c_reset" "$days"
  else
    printf '  %s!%s Möhlet         %s gün (täzelemek gerek bolup biler)\n' "$c_yellow" "$c_reset" "$days"
  fi

  # jemleme
  reason=""
  verdict="GOWY"
  if [[ ${alpn:-} != h2 ]]; then verdict="ORTA"; reason="h2 ýok"; fi
  if [[ ${verify:-} != 0* ]]; then verdict="ERBET"; reason="sertifikat nädogry"; fi
  if (( connect_ms > 300 )); then verdict="ORTA"; reason="${reason:+$reason; }ping ýokary (${connect_ms} ms)"; fi

  case $verdict in
    GOWY)
      printf '  %s→ Netije: GOWY — Reality üçin laýyk%s\n' "$c_green" "$c_reset"
      GOOD=$(( GOOD + 1 ))
      ;;
    ORTA)
      printf '  %s→ Netije: ORTA (%s) — ätiýaçlyk hökmünde bolýar%s\n' "$c_yellow" "$reason" "$c_reset"
      GOOD=$(( GOOD + 1 ))
      ;;
    *)
      printf '  %s→ Netije: ERBET (%s) — ulanma%s\n' "$c_red" "$reason" "$c_reset"
      BAD=$(( BAD + 1 ))
      ;;
  esac
}

printf '%sReality SNI barlagy%s  %s(%s)%s\n' "$c_cyan" "$c_reset" "$c_dim" "$(date -u '+%Y-%m-%d %H:%M UTC')" "$c_reset"
printf '%sDiňe serwerden barlanýar — müşderiniň torbasyndan hem barla!%s\n' "$c_dim" "$c_reset"

for host in "${SNI_LIST[@]}"; do
  check_one "$host"
done

printf '\n%s╍╍╍ jemleme ╍╍╍%s\n' "$c_cyan" "$c_reset"
printf '  laýyk kandidatlar: %s%d%s   problemli: %s%d%s\n' "$c_green" "$GOOD" "$c_reset" "$c_red" "$BAD" "$c_reset"
printf '  Netijeden iň gowy 1–2 sanysyny saýla we panelde goý:\n'
printf '    Dest        : <domen>:443\n'
printf '    SNI         : <domen>   (dest bilen hökmany suratda deň bolmaly)\n'
printf '  Soň: bash check.sh\n'
