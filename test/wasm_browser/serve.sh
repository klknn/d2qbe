#!/bin/bash
set -euo pipefail

MODE=${1:?"usage: serve.sh <test|demo>"}
PORT=${WASM_BROWSER_PORT:-8787}

case "$MODE" in
  test) PAGE=test.html ;;
  demo) PAGE=demo.html ;;
  *)
    echo "unknown browser page: $MODE" >&2
    exit 2
    ;;
esac

if ! command -v python3 >/dev/null 2>&1; then
  echo "wasm browser targets require python3 to serve local files" >&2
  exit 1
fi

URL="http://127.0.0.1:$PORT/test/wasm_browser/$PAGE"
python3 -m http.server "$PORT" --bind 127.0.0.1 &
SERVER_PID=$!
cleanup() {
  kill "$SERVER_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

sleep 1
if [ "${WASM_BROWSER_OPEN:-1}" = 1 ]; then
  case "$(uname -s)" in
    Darwin) open "$URL" ;;
    Linux) xdg-open "$URL" >/dev/null 2>&1 || true ;;
    *) echo "Open $URL in a browser" ;;
  esac
fi

echo "Serving $MODE at $URL (press Ctrl-C to stop)"
wait "$SERVER_PID"
