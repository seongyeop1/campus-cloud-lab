#!/usr/bin/env bash
# 웹 터미널 시작. TTYD_BASE_PATH는 프록시에서 보는 경로(예: /s01).
set -euo pipefail
exec ttyd --writable --port 7681 --base-path "${TTYD_BASE_PATH:-/}" bash -l
