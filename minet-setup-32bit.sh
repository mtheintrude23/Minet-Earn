#!/usr/bin/env sh
BU="https://dashboard.minet.vn"
echo ""
echo "===== Minet Mining Setup ====="
echo ""
printf "Email: "
read EM < /dev/tty
[ -z "$EM" ] && echo "Email required." && exit 1
echo "Preparing..."
if [ -d "/data/data/com.termux" ]; then
  pkg update -y && pkg install -y curl >/dev/null 2>&1 || true
else
  command -v curl >/dev/null 2>&1 || { apt-get update -y >/dev/null 2>&1; apt-get install -y curl >/dev/null 2>&1; }
fi
EE="$(printf "%s" "$EM" | sed -e 's/%/%25/g' -e 's/+/%2B/g' -e 's/@/%40/g')"
CI="$(curl -sf https://api.ipify.org 2>/dev/null || echo "")"
[ -z "$CI" ] && echo "Network error." && exit 1
EI="$(printf "%s" "$CI" | sed -e 's/%/%25/g' -e 's/:/%3A/g')"
curl -fsSL "$BU/api/minecoin/setup?email=$EE&ip=$EI&mode=dashboard" | sh

