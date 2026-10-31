#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# cyber_tools · vpn/provision.sh
#
# 3X-UI paneliniň API-si arkaly VPN-ny awtomatik döredýär — panelde elli basman.
#
# Amallar:
#   reality   (adaty)  VLESS+Reality inbound döredýär we müşderi(ler)i goşýar
#   client             Bar bolan inbound-a müşderi goşýar
#   list               Inbound-lary we müşderileri görkezýär
#   link               Müşderiniň vless:// linkini çykarýär (QR bilen)
#   test               API baglanyşygyny barlaýar
#   delete-client      Müşderini pozýar
#
# Ulanylyşy:
#   sudo bash provision.sh reality --sni www.microsoft.com
#   sudo bash provision.sh reality --sni www.apple.com --port 443 --clients 3 --gb 100 --days 30
#   sudo bash provision.sh client --email ahmet-02 --gb 50 --days 30
#   sudo bash provision.sh list
#   sudo bash provision.sh link --email ahmet-01 --qr
#   sudo bash provision.sh test
#
# Authentifikasiýa:
#   1) /etc/x-ui/install-result.env-daky XUI_API_TOKEN (Bearer) — iň gowysy
#   2) şol faýldaky login/parol → /login + CSRF (köneler üçin)
#   Ýa-da: --token TOKEN / --api-base http://127.0.0.1:PORT/BASEPATH
#
# Bellik: skript 3X-UI v3 API-sini esasy alýar; v2-de hem işleýän ýollary bar.
# ---------------------------------------------------------------------------
set -Eeuo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"
if locale -a 2>/dev/null | grep -qiE '^C\.utf-?8$'; then export LC_ALL=C.UTF-8; fi

c_reset=$'\033[0m'; c_cyan=$'\033[1;36m'; c_yellow=$'\033[1;33m'
c_red=$'\033[1;31m'; c_green=$'\033[1;32m'; c_dim=$'\033[2m'

log()  { printf '%s[provision]%s %s\n' "$c_cyan" "$c_reset" "$*"; }
ok()   { printf '%s  ✓%s %s\n' "$c_green" "$c_reset" "$*"; }
warn() { printf '%s[warn]%s %s\n' "$c_yellow" "$c_reset" "$*" >&2; }
die()  { printf '%s[error]%s %s\n' "$c_red" "$c_reset" "$*" >&2; exit 1; }

COMMAND="${1:-reality}"
case $COMMAND in
  reality|client|list|link|test|delete-client|--help|-h) ;;
  *) die "Nämälim amal: $COMMAND  (--help)" ;;
esac
[[ $COMMAND == --help || $COMMAND == -h ]] && COMMAND=help
[[ $COMMAND != help ]] && shift || true

# ------------------------------- parametrler -------------------------------
SNI="www.microsoft.com"
PORT=443
REMARK=""
CLIENT_EMAIL=""
CLIENTS_COUNT=1
TOTAL_GB=0
DAYS=0
LIMIT_IP=2
ADDR=""
INBOUND_ID=""
QR=0
DRY_RUN=0
VISION=1
JSON_OUT=0
TOKEN="${XUI_API_TOKEN:-}"
API_BASE="${XUI_API_BASE:-}"
ENV_FILE="${XUI_ENV_FILE:-/etc/x-ui/install-result.env}"
LINK_DIR="/root/vpn-links"

help() {
  sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

while [[ $# -gt 0 ]]; do
  case $1 in
    --sni)        SNI=${2:?}; shift ;;
    --port)       PORT=${2:?}; shift ;;
    --remark)     REMARK=${2:?}; shift ;;
    --email)      CLIENT_EMAIL=${2:?}; shift ;;
    --clients)    CLIENTS_COUNT=${2:?}; shift ;;
    --gb)         TOTAL_GB=${2:?}; shift ;;
    --days)       DAYS=${2:?}; shift ;;
    --limit-ip)   LIMIT_IP=${2:?}; shift ;;
    --addr)       ADDR=${2:?}; shift ;;
    --inbound)    INBOUND_ID=${2:?}; shift ;;
    --qr)         QR=1 ;;
    --json)       JSON_OUT=1 ;;
    --no-vision)  VISION=0 ;;
    --token)      TOKEN=${2:?}; shift ;;
    --api-base)   API_BASE=${2:?}; shift ;;
    --env-file)   ENV_FILE=${2:?}; shift ;;
    --link-dir)   LINK_DIR=${2:?}; shift ;;
    --dry-run)    DRY_RUN=1 ;;
    --help|-h)    help ;;
    *) die "Nämälim parametr: $1  (--help)" ;;
  esac
  shift
done

have() { command -v "$1" >/dev/null 2>&1; }
need() { have "$1" || die "'$1' gerek: apt install $2"; }

need curl curl
need jq jq

REMARK=${REMARK:-"tm-reality-${PORT}"}

# ------------------------------- panel sazlamalary -------------------------
load_env() {
  if [[ -r $ENV_FILE ]]; then
    # install.sh faýly %q bilen ýazýar — source etmek howpsuz
    # shellcheck disable=SC1090
    . "$ENV_FILE"
  fi
  [[ -z $API_BASE && -n ${XUI_PANEL_PORT:-} ]] && \
    API_BASE="http://127.0.0.1:${XUI_PANEL_PORT}/${XUI_WEB_BASE_PATH:-}"
  if [[ -z ${TOKEN:-} && -n ${XUI_API_TOKEN:-} ]]; then
    TOKEN=$XUI_API_TOKEN
  fi
  [[ -n $API_BASE ]] || die "Panel salgysy belli däl. --api-base http://127.0.0.1:PORT/BASEPATH ber."
  API_BASE=${API_BASE%/}
}

# ------------------------------- API gatlagy ---------------------------------
API_MODE=""; COOKIE_JAR=""; CSRF=""
AUTH_HDR=()

_api_curl() {
  local method=$1 path=$2 body=${3:-}
  local args=(-sS --max-time 25 -X "$method" "${API_BASE}${path}" -H 'Accept: application/json')
  (( ${#AUTH_HDR[@]} )) && args+=("${AUTH_HDR[@]}")
  [[ -n $COOKIE_JAR ]] && args+=(-b "$COOKIE_JAR" -c "$COOKIE_JAR")
  [[ -n $CSRF ]] && args+=(-H "X-CSRF-Token: ${CSRF}")
  [[ -n $body ]] && args+=(-H 'Content-Type: application/json' --data-binary "$body")
  curl "${args[@]}" 2>/dev/null || true
}

api() { # api <GET|POST> <path> [json]
  local out
  out=$(_api_curl "$@")
  if [[ -z $out ]]; then
    die "Panel API jogap bermedi (${API_BASE}). Panel işleýärmi?  systemctl status x-ui"
  fi
  printf '%s' "$out"
}

api_ok() { # api_ok <GET|POST> <path> [json] — success bolmasa ölýär
  local out msg
  out=$(api "$@")
  if ! jq -e '.success == true' >/dev/null 2>&1 <<<"$out"; then
    msg=$(jq -r '.msg // "näbelli ýalňyşlyk"' <<<"$out" 2>/dev/null || echo "$out")
    die "API şowsuz: ${msg}"
  fi
  printf '%s' "$out"
}

auth_bearer() {
  AUTH_HDR=(-H "Authorization: Bearer ${TOKEN}")
  API_MODE="bearer"
}

auth_login() {
  local user=${XUI_USERNAME:-} pass=${XUI_PASSWORD:-}
  [[ -n $user && -n $pass ]] || die "API token ýa-da login/parol tapylmady (${ENV_FILE})."
  COOKIE_JAR=$(mktemp)
  trap 'rm -f "$COOKIE_JAR"' EXIT

  CSRF=$(curl -sS --max-time 10 -c "$COOKIE_JAR" "${API_BASE}/csrf-token" 2>/dev/null \
         | jq -r '.obj // empty' 2>/dev/null || true)

  local body resp hashed
  body=$(jq -nc --arg u "$user" --arg p "$pass" '{username:$u,password:$p}')
  resp=$(_api_curl POST /login "$body")
  if ! jq -e '.success == true' >/dev/null 2>&1 <<<"$resp"; then
    # käbir 3x-ui wersiýalary sha256-hash parol garaşýar
    hashed=$(printf '%s' "$pass" | openssl dgst -sha256 -hex 2>/dev/null | awk '{print $NF}')
    if [[ -n $hashed ]]; then
      body=$(jq -nc --arg u "$user" --arg p "$hashed" '{username:$u,password:$p}')
      resp=$(_api_curl POST /login "$body")
    fi
  fi
  jq -e '.success == true' >/dev/null 2>&1 <<<"$resp" \
    || die "Login şowsuz. Panel parolyny barla ýa-da API token ber (Settings → API Tokens)."
  API_MODE="session"
}

api_init() {
  load_env
  if [[ -n $TOKEN ]]; then
    auth_bearer
    # token dogrumy? (monitor scope hem /server/status-a rugsat berýär)
    local probe
    probe=$(api GET /panel/api/inbounds/list)
    if ! jq -e '.success == true' >/dev/null 2>&1 <<<"$probe"; then
      warn "Bearer token bilen baglanyşyk şowsuz — login synanyşygy"
      TOKEN=""
      auth_login
    fi
  else
    auth_login
  fi
}

# ----------------------------- kömekçi funksiýalar -------------------------
detect_addr() {
  local ip
  ip=$(ip -4 route get 1.1.1.1 2>/dev/null \
        | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}')
  [[ -z $ip ]] && ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  printf '%s' "${ip:-SERWER_IP}"
}

find_xray() {
  local c
  for c in /usr/local/x-ui/bin/xray-* /usr/local/bin/xray /usr/bin/xray; do
    [[ -x $c ]] && { printf '%s' "$c"; return 0; }
  done
  c=$(command -v xray 2>/dev/null || true)
  [[ -n $c ]] && printf '%s' "$c"
}

gen_keys() {
  local xray out priv pub
  xray=$(find_xray)
  if [[ -n $xray ]]; then
    out=$("$xray" x25519 2>/dev/null || true)
  fi
  priv=$(printf '%s\n' "${out:-}" | awk -F': *' 'tolower($1) ~ /^private/ {print $2; exit}')
  pub=$(printf '%s\n' "${out:-}" | awk -F': *' 'tolower($1) ~ /^(password|public)/ {print $2; exit}')
  if [[ -z $priv || -z $pub ]]; then
    die "x25519 açar döredip bolmady. Xray bin tapyldymy? ($xray)"
  fi
  printf '%s %s' "$priv" "$pub"
}

gen_uuid() {
  if [[ -r /proc/sys/kernel/random/uuid ]]; then
    cat /proc/sys/kernel/random/uuid
  else
    openssl rand -hex 16 | sed -E 's/(.{8})(.{4})(.{4})(.{4})(.{12})/\1-\2-\3-\4-\5/'
  fi
}

rand_str() { # rand_str <uzynlyk> <belgiler>
  local len=$1 cs=${2:-A-Za-z0-9} out=""
  while (( ${#out} < len )); do
    out+=$( { openssl rand -base64 96 2>/dev/null || head -c 256 /dev/urandom; } | LC_ALL=C tr -dc "$cs" || true)
    [[ -z $out ]] && out="a1b2c3d4"
  done
  printf '%s' "${out:0:$len}"
}

urlenc() { jq -rn --arg v "$1" '$v|@uri'; }

# inbound-yň settings/streamSettings hem setir, hem obýekt bolup biler
json_field() { # json_field <json> <field>
  jq -c --arg f "$2" '
    (.[$f] // {}) as $v |
    if ($v|type) == "string" then ($v|fromjson) else $v end
  ' <<<"$1" 2>/dev/null
}

build_client() {
  local email=$1 uuid=$2 subid=$3 total=$4 expiry=$5 flow=$6
  jq -nc --arg id "$uuid" --arg email "$email" --arg sub "$subid" \
         --arg flow "$flow" --argjson total "$total" --argjson expiry "$expiry" \
         --argjson limitip "$LIMIT_IP" \
    '{id:$id, email:$email, subId:$sub, flow:$flow, limitIp:$limitip,
      totalGB:$total, expiryTime:$expiry, enable:true, tgId:"", reset:0}'
}

expiry_ms() { # expiry_ms <gün> → millisekunt
  local d=${1:-0}
  (( d > 0 )) || { printf '0'; return; }
  printf '%s' $(( ($(date +%s) + d * 86400) * 1000 ))
}

total_bytes() { # total_bytes <GB>
  local g=${1:-0}
  (( g > 0 )) || { printf '0'; return; }
  printf '%s' $(( g * 1073741824 ))
}

# --------------------------------- amallar ---------------------------------
cmd_test() {
  api_init
  ok "API baglanyşygy: ${API_BASE} (${API_MODE})"
  local inbounds count
  inbounds=$(api_ok GET /panel/api/inbounds/list)
  count=$(jq -r '.obj | length' <<<"$inbounds")
  ok "Inbound sany: ${count}"
  jq -r '.obj[]? | "  · #\(.id)  \(.protocol)  :\(.port)  \(.remark // "")  enable=\(.enable)"' <<<"$inbounds"
  local cl
  cl=$(api GET /panel/api/clients/list)
  if jq -e '.success == true' >/dev/null 2>&1 <<<"$cl"; then
    ok "Müşderi sany: $(jq -r '.obj | length' <<<"$cl")"
  else
    warn "v3 /clients/list ýok (köne panel) — müşderiler inbound içinde"
  fi
}

inbound_payload() {
  local priv=$1 pub=$2 sid=$3 clients_json=$4
  jq -nc \
    --arg remark "$REMARK" --argjson port "$PORT" \
    --arg dest "${SNI}:443" --arg sni "$SNI" \
    --arg priv "$priv" --arg pub "$pub" --arg sid "$sid" \
    --argjson clients "$clients_json" \
    '{
      enable: true, remark: $remark, listen: "", port: $port, protocol: "vless",
      expiryTime: 0, total: 0,
      settings: ({clients: $clients, decryption: "none", fallbacks: []} | tojson),
      streamSettings: ({
        network: "tcp",
        security: "reality",
        realitySettings: {
          show: false, xver: 0,
          dest: $dest, target: $dest,
          serverNames: [$sni],
          privateKey: $priv,
          minClientVer: "", maxClientVer: "",
          maxTimeDiff: 0, maxTimediff: 0,
          shortIds: [$sid],
          mldsa65Seed: "",
          settings: {
            publicKey: $pub, fingerprint: "chrome",
            serverName: "", spiderX: "/", mldsa65Verify: ""
          }
        }
      } | tojson),
      sniffing: ({enabled: true, destOverride: ["http", "tls", "quic"]} | tojson)
    }'
}

cmd_reality() {
  api_init
  local keyline priv pub sid uuid subid email flow total expiry clients_json payload resp id

  keyline=$(gen_keys)
  priv=${keyline% *}; pub=${keyline#* }
  sid=$(rand_str 16 'a-f0-9')
  flow=""; (( VISION )) && flow="xtls-rprx-vision"
  total=$(total_bytes "$TOTAL_GB")
  expiry=$(expiry_ms "$DAYS")

  clients_json="[]"
  local emails=()
  if (( CLIENTS_COUNT > 0 )); then
    local i
    for (( i = 1; i <= CLIENTS_COUNT; i++ )); do
      if [[ -n $CLIENT_EMAIL ]]; then
        if (( CLIENTS_COUNT == 1 )); then email=$CLIENT_EMAIL; else email="${CLIENT_EMAIL}-${i}"; fi
      else
        email=$(printf 'user-%02d' "$i")
      fi
      emails+=("$email")
      uuid=$(gen_uuid); subid=$(rand_str 16 'a-z0-9')
      clients_json=$(jq -c --argjson c "$(build_client "$email" "$uuid" "$subid" "$total" "$expiry" "$flow")" '. + [$c]' <<<"$clients_json")
    done
  fi

  payload=$(inbound_payload "$priv" "$pub" "$sid" "$clients_json")

  if (( DRY_RUN )); then
    log "Payload (POST /panel/api/inbounds/add):"
    jq . <<<"$payload"
    return 0
  fi

  # şol remark bilen inbound barmy?
  local existing
  existing=$(api_ok GET /panel/api/inbounds/list | jq -r --arg r "$REMARK" '.obj[]? | select(.remark==$r) | .id' | head -1)
  if [[ -n $existing ]]; then
    die "『${REMARK}』 atly inbound eýýäm bar (#${existing}). Müşderi goşmak üçin: bash $0 client --inbound ${existing} --email ..."
  fi

  log "VLESS+Reality inbound döredilýär: ${SNI}:443 · port ${PORT} · remark ${REMARK}"
  resp=$(api_ok POST /panel/api/inbounds/add "$payload")
  id=$(jq -r '.obj.id // empty' <<<"$resp")
  if [[ -z $id ]]; then
    id=$(api_ok GET /panel/api/inbounds/list | jq -r --arg r "$REMARK" '.obj[]? | select(.remark==$r) | .id' | head -1)
  fi
  [[ -n $id ]] || die "Inbound döredildi, ýöne ID tapylmady."
  ok "Inbound #${id} döredildi"
  printf '%s  Soň: bash %s list  ·  bash %s link --email <at>%s\n' "$c_dim" "$0" "$0" "$c_reset"

  if (( ${#emails[@]} > 0 )); then
    print_links "$id" "${emails[@]}"
  fi
}

print_links() {
  local id=$1; shift
  local emails=("$@")
  local addr=${ADDR:-$(detect_addr)}
  local inbound ib_obj stream inc_settings pubkey sni sid port cflow
  inbound=$(api_ok GET "/panel/api/inbounds/get/${id}")
  ib_obj=$(jq -c '.obj' <<<"$inbound")
  stream=$(json_field "$ib_obj" streamSettings)
  inc_settings=$(json_field "$ib_obj" settings)
  pubkey=$(jq -r '.realitySettings.settings.publicKey // empty' <<<"$stream")
  sni=$(jq -r '.realitySettings.serverNames[0] // empty' <<<"$stream")
  sid=$(jq -r '.realitySettings.shortIds[0] // empty' <<<"$stream")
  port=$(jq -r '.obj.port' <<<"$inbound")

  [[ -n $pubkey ]] || warn "Public key tapylmady — link ýaramaz bolar"
  [[ -n $addr ]]   || die "Serwer salgysy anyklanmady — --addr ber"

  local can_save=1
  if ! mkdir -p "$LINK_DIR" 2>/dev/null; then
    can_save=0
    warn "Link faýllaryny ýazyp bolmady (${LINK_DIR}) — diňe ekrana çykarylýar. --link-dir DIR ber."
  else
    chmod 700 "$LINK_DIR" 2>/dev/null || true
  fi

  local email uuid link file flowq clients_json
  clients_json=$(api GET /panel/api/clients/list)

  for email in "${emails[@]}"; do
    uuid=""; cflow=""
    # 1) inbound settings-den (flow hem şol ýerde)
    uuid=$(jq -r --arg e "$email" '.clients[]? | select(.email==$e) | .id' <<<"$inc_settings" | head -1)
    cflow=$(jq -r --arg e "$email" '.clients[]? | select(.email==$e) | (.flow // "")' <<<"$inc_settings" | head -1)
    # 2) v3 /clients/list (eýýäm bar bolsa)
    if [[ -z $uuid ]] && jq -e '.success == true' >/dev/null 2>&1 <<<"$clients_json"; then
      uuid=$(jq -r --arg e "$email" '.obj[]? | select(.email==$e) | .uuid' <<<"$clients_json" | head -1)
    fi
    [[ -n $uuid ]] || { warn "${email} üçin UUID tapylmady"; continue; }

    flowq=""
    [[ -n ${cflow:-} ]] && flowq="&flow=$(urlenc "$cflow")"
    link="vless://${uuid}@${addr}:${port}?type=tcp&security=reality&encryption=none&pbk=$(urlenc "$pubkey")&fp=chrome&sni=$(urlenc "$sni")&sid=$(urlenc "$sid")&spx=%2F${flowq}#$(urlenc "${REMARK}-${email}")"

    if (( JSON_OUT )); then
      jq -nc --arg email "$email" --arg link "$link" '{email:$email, link:$link}'
    else
      printf '\n%s  %s%s\n' "$c_green" "$email" "$c_reset"
      printf '    %s\n' "$link"
    fi
    if (( can_save )); then
      file="${LINK_DIR}/${REMARK}-${email}.txt"
      if ( umask 077; printf '%s\n' "$link" >"$file" ); then
        if (( JSON_OUT )); then
          printf '%s    faýl: %s%s\n' "$c_dim" "$file" "$c_reset" >&2
        else
          printf '%s    faýl: %s%s\n' "$c_dim" "$file" "$c_reset"
        fi
      fi
    fi
    if (( QR )); then
      if have qrencode; then qrencode -t ANSIUTF8 "$link"; else warn "qrencode ýok — QR çykmady (apt install qrencode)"; fi
    fi
  done
}
cmd_client() {
  api_init
  local id=${INBOUND_ID} email=${CLIENT_EMAIL} flow uuid subid total expiry payload resp

  if [[ -z $id ]]; then
    id=$(api_ok GET /panel/api/inbounds/list \
         | jq -r --arg r "$REMARK" '.obj[]? | select(.remark==$r) | .id' | head -1)
  fi
  [[ -n $id ]] || die "Inbound tapylmady. --inbound N ýa-da --remark NAME ber."
  if [[ -z $email ]]; then
    email=$(printf 'user-%s' "$(rand_str 4 'a-z0-9')")
  fi

  uuid=$(gen_uuid); subid=$(rand_str 16 'a-z0-9')
  total=$(total_bytes "$TOTAL_GB"); expiry=$(expiry_ms "$DAYS")
  flow=""; (( VISION )) && flow="xtls-rprx-vision"

  local client
  client=$(build_client "$email" "$uuid" "$subid" "$total" "$expiry" "$flow")

  # v3: /clients/add ; v2: /inbounds/addClient
  payload=$(jq -nc --argjson c "$client" --argjson id "$id" '{client:$c, inboundIds:[$id]}')
  if (( DRY_RUN )); then
    log "Payload (POST /panel/api/clients/add):"; jq . <<<"$payload"; return 0
  fi

  resp=$(api POST /panel/api/clients/add "$payload")
  if jq -e '.success == true' >/dev/null 2>&1 <<<"$resp"; then
    ok "Müşderi goşuldy: ${email} → inbound #${id}"
  else
    local legacy
    legacy=$(jq -nc --argjson id "$id" --argjson c "$client" \
             '{id:$id, settings: ({clients:[$c]} | tojson)}')
    resp=$(api POST /panel/api/inbounds/addClient "$legacy")
    jq -e '.success == true' >/dev/null 2>&1 <<<"$resp" \
      || die "Müşderi goşup bolmady: $(jq -r '.msg // .' <<<"$resp")"
    ok "Müşderi goşuldy (legacy API): ${email} → inbound #${id}"
  fi

  print_links "$id" "$email"
}

cmd_list() {
  api_init
  local inbounds clients
  inbounds=$(api_ok GET /panel/api/inbounds/list)
  clients=$(api GET /panel/api/clients/list)

  log "Inbound-lar"
  jq -r '.obj[]? | "  #\(.id)  \(.protocol)  :\(.port)  \(.remark // "-")  enable=\(.enable)"' <<<"$inbounds"

  log "Müşderiler"
  if jq -e '.success == true' >/dev/null 2>&1 <<<"$clients"; then
    jq -r '.obj[]? | "  \(.email)\t inbounds=\(.inboundIds|join(","))\t total=\(.totalGB)\t exp=\(.expiryTime)\t enable=\(.enable)"' <<<"$clients"
  else
    jq -r '.obj[]? | (.settings? // "{}") as $s | ($s|if type=="string" then fromjson else . end).clients[]? | "  \(.email)\t inbound=\(.id)"' <<<"$inbounds"
  fi
}

cmd_link() {
  api_init
  [[ -n $CLIENT_EMAIL ]] || die "--email hökmany"
  local id=${INBOUND_ID}
  if [[ -z $id ]]; then
    id=$(api_ok GET /panel/api/inbounds/list \
         | jq -r --arg r "$REMARK" '.obj[]? | select(.remark==$r) | .id' | head -1)
  fi
  if [[ -z $id ]]; then
    id=$(api_ok GET /panel/api/clients/list \
         | jq -r --arg e "$CLIENT_EMAIL" '.obj[]? | select(.email==$e) | .inboundIds[0]' | head -1)
  fi
  [[ -n $id ]] || die "Inbound tapylmady (--inbound ber)"
  print_links "$id" "$CLIENT_EMAIL"
}

cmd_delete_client() {
  api_init
  [[ -n $CLIENT_EMAIL ]] || die "--email hökmany"
  if (( DRY_RUN )); then
    log "DELETE /panel/api/clients/del/${CLIENT_EMAIL}"; return 0
  fi
  api_ok POST "/panel/api/clients/del/$(urlenc "$CLIENT_EMAIL")" >/dev/null 2>&1 \
    || api_ok POST "/panel/api/inbounds/delClient" \
         "$(jq -nc --arg e "$CLIENT_EMAIL" '{email:$e}')" >/dev/null
  ok "Müşderi pozuldy: ${CLIENT_EMAIL}"
}

case $COMMAND in
  help)          help ;;
  reality)       cmd_reality ;;
  client)        cmd_client ;;
  list)          cmd_list ;;
  link)          cmd_link ;;
  delete-client) cmd_delete_client ;;
  test)          cmd_test ;;
esac
