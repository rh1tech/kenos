#!/usr/bin/env bash
# Smoke-test Kenos via the bench socket (isolated KENOS_PROBE world).
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${KENOS_APP:-build/Kenos.app/Contents/MacOS/Kenos}"
SOCK="$HOME/Library/Application Support/Kenos (test)/bench.sock"

pkill -f 'Kenos.app/Contents/MacOS/Kenos' 2>/dev/null || true
sleep 0.3
rm -f "$SOCK"

defaults write app.kenos.browser.test bench -bool true
defaults write app.kenos.browser.test welcomed -bool true

KENOS_PROBE=1 "$APP" >/tmp/kenos-smoke.log 2>&1 &
PID=$!
trap 'kill "$PID" 2>/dev/null || true' EXIT

for i in $(seq 1 80); do
  if ! kill -0 "$PID" 2>/dev/null; then
    echo "Kenos exited early"; cat /tmp/kenos-smoke.log; exit 1
  fi
  if [[ -S "$SOCK" ]]; then
    if ./bench --test probe >/dev/null 2>&1; then break; fi
  fi
  sleep 0.25
done

ID=$(./bench --test open https://example.com | tail -1)
./bench --test wait "$ID" 30 >/dev/null
TEXT=$(./bench --test text "$ID")
echo "$TEXT" | grep -qi "Example Domain"
./bench --test eval "$ID" "document.title" | grep -qi "Example Domain"
./bench --test ui history on >/dev/null
./bench --test ui history off >/dev/null
./bench --test ui downloads on >/dev/null
./bench --test ui downloads off >/dev/null
./bench --test ui bookmarks on >/dev/null
./bench --test ui bookmarks off >/dev/null
./bench --test ui look dark >/dev/null
./bench --test ui look system >/dev/null
./bench --test ui sidebar on >/dev/null
./bench --test ui sidebar off >/dev/null
./bench --test close all >/dev/null

echo "smoke ok"
