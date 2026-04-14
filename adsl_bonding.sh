#!/usr/bin/env bash
set -euo pipefail

# ----------------------------------------------------------------------------
# ADSL Multi-WAN load balancing (per-connection) using nftables + policy routing
#
# IMPORTANT:
# - This script aggregates multiple ADSL links for many simultaneous connections.
# - A single TCP/UDP flow usually will NOT exceed one line's speed unless you use
#   MPTCP end-to-end or tunnel bonding with a server/VPS.
# ----------------------------------------------------------------------------

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "[!] Run as root." >&2
  exit 1
fi

WAN_IFACES=(ppp0 ppp1)
LAN_IFACE="eth0"
TABLE_BASE=200
NFT_TABLE="inet mwan"

usage() {
  cat <<USAGE
Usage:
  $0 up      # apply load balancing rules
  $0 down    # remove rules

Edit WAN_IFACES and LAN_IFACE inside the script to match your interfaces.
USAGE
}

require_bin() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[!] Missing command: $1" >&2
    exit 1
  }
}

for b in ip nft sysctl awk mktemp; do
  require_bin "$b"
done

get_gw() {
  local dev="$1"
  ip -4 route show default dev "$dev" | awk '/default/ {print $3; exit}'
}

cleanup() {
  echo "[*] Removing nftables rules..."
  nft delete table $NFT_TABLE 2>/dev/null || true

  echo "[*] Removing policy rules and routes..."
  local i=0
  for _dev in "${WAN_IFACES[@]}"; do
    local table=$((TABLE_BASE + i))
    ip rule del fwmark $((i+1)) table "$table" 2>/dev/null || true
    ip route flush table "$table" 2>/dev/null || true
    i=$((i+1))
  done

  sysctl -w net.ipv4.ip_forward=0 >/dev/null
  echo "[+] Done."
}

apply_rules() {
  echo "[*] Enabling IP forward..."
  sysctl -w net.ipv4.ip_forward=1 >/dev/null

  echo "[*] Building routing tables for each WAN..."
  local i=0
  for dev in "${WAN_IFACES[@]}"; do
    local table=$((TABLE_BASE + i))
    local gw
    gw="$(get_gw "$dev")"

    if [[ -z "$gw" ]]; then
      echo "[!] Could not detect gateway for $dev. Ensure interface is up with default route." >&2
      exit 1
    fi

    ip route flush table "$table" 2>/dev/null || true
    ip route add default via "$gw" dev "$dev" table "$table"
    ip rule add fwmark $((i+1)) table "$table" 2>/dev/null || true

    i=$((i+1))
  done

  local wan_count=${#WAN_IFACES[@]}
  if (( wan_count < 2 )); then
    echo "[!] Need at least 2 WAN interfaces in WAN_IFACES." >&2
    exit 1
  fi

  echo "[*] Applying nftables connection marking..."
  local nft_file
  nft_file="$(mktemp)"

  cat > "$nft_file" <<NFT
flush table $NFT_TABLE

table $NFT_TABLE {
  chain prerouting {
    type filter hook prerouting priority mangle; policy accept;

    # Keep existing conntrack marks stable
    ct mark != 0 meta mark set ct mark

    # New flows from LAN: distribute across WAN links
    iifname "$LAN_IFACE" ct state new numgen random mod $wan_count map {
NFT

  for ((i=0; i<wan_count; i++)); do
    local comma=","
    (( i == wan_count - 1 )) && comma=""
    printf '      %d : %d%s\n' "$i" "$((i+1))" "$comma" >> "$nft_file"
  done

  cat >> "$nft_file" <<'NFT'
    } ct mark set meta mark

    # Restore mark for established packets
    ct mark != 0 meta mark set ct mark
  }

  chain postrouting {
    type nat hook postrouting priority srcnat; policy accept;
NFT

  for dev in "${WAN_IFACES[@]}"; do
    printf '    oifname "%s" masquerade\n' "$dev" >> "$nft_file"
  done

  cat >> "$nft_file" <<'NFT'
  }
}
NFT

  nft -f "$nft_file"
  rm -f "$nft_file"

  echo "[+] Multi-WAN load balancing enabled."
  echo "[i] For true single-flow bonding, use MPTCP or a VPN bonding server."
}

case "${1:-}" in
  up)
    apply_rules
    ;;
  down)
    cleanup
    ;;
  *)
    usage
    exit 1
    ;;
esac
