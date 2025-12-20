#!/usr/bin/env bash
set -euo pipefail

TS="$(date '+%F_%H%M%S')"
OUT="/var/log/wg-debug"
mkdir -p "$OUT"
LOG="$OUT/snapshot_$TS.log"

WG_IF="wg0"
WAN_IF="eth0"
WG_PORT="51821"

echo "### WG DEBUG SNAPSHOT $TS" | tee -a "$LOG"
echo | tee -a "$LOG"

echo "## ip -4 rule (relevant)" | tee -a "$LOG"
ip -4 rule | grep -E 'fwmark 0x77|fwmark 0x520|lookup (main|vpn|wan)' | tee -a "$LOG" || true
echo | tee -a "$LOG"

echo "## ip -4 route (tables)" | tee -a "$LOG"
echo "# main:" | tee -a "$LOG"
ip -4 route show table main | sed -n '1,80p' | tee -a "$LOG"
echo "# vpn:" | tee -a "$LOG"
ip -4 route show table vpn 2>/dev/null | sed -n '1,80p' | tee -a "$LOG" || true
echo "# wan:" | tee -a "$LOG"
ip -4 route show table wan 2>/dev/null | sed -n '1,80p' | tee -a "$LOG" || true
echo | tee -a "$LOG"

echo "## wg show $WG_IF" | tee -a "$LOG"
wg show "$WG_IF" | tee -a "$LOG" || true
echo | tee -a "$LOG"

echo "## ss listener" | tee -a "$LOG"
ss -uapn | grep -E ":${WG_PORT}\b" | tee -a "$LOG" || true
echo | tee -a "$LOG"

echo "## conntrack (wg port) - may require conntrack-tools" | tee -a "$LOG"
conntrack -L 2>/dev/null | grep -E "dport=${WG_PORT}|sport=${WG_PORT}" | tee -a "$LOG" || true
echo | tee -a "$LOG"

echo "## kernel: wg-related logs (last 200 lines)" | tee -a "$LOG"
dmesg | tail -n 200 | grep -i -E 'wireguard|wg0' | tee -a "$LOG" || true
echo | tee -a "$LOG"

echo "Snapshot written to: $LOG"

