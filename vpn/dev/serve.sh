#!/usr/bin/env bash
# cyber_tools · vpn/dev/serve.sh
#
# 3X-UI mock API-sini preview üçin yzygiderli işledýär (host/port/token/seed bir ýerde).
#
# Ulanylyşy:
#   bash vpn/dev/serve.sh                # 0.0.0.0:18080, token=testtoken, seed açyk
#   PORT=19000 bash vpn/dev/serve.sh     # başga port
#   MOCK_SEED=0 bash vpn/dev/serve.sh    # boş panel (tohumsuz)
#   MOCK_TOKEN=supersecret bash vpn/dev/serve.sh
set -euo pipefail

DEV_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

export HOST="${HOST:-0.0.0.0}"
export PORT="${PORT:-18080}"
export MOCK_TOKEN="${MOCK_TOKEN:-testtoken}"
export MOCK_SEED="${MOCK_SEED:-1}"
export MOCK_PANEL_BASE="${MOCK_PANEL_BASE:-/panelx}"

exec python3 "${DEV_DIR}/mock-xui-api.py"
