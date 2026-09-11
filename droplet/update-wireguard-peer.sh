#!/usr/bin/env bash
# ============================================================================
# DigitalOcean droplet - replace the old MikroTik WireGuard peer key
# ----------------------------------------------------------------------------
# The MikroTik was factory-reset, so its old WireGuard key is dead. Run this
# AFTER creating wg1 on the router (Phase 2) to swap in the fresh key.
#
# Usage (run on the droplet as root or via sudo):
#   sudo ./update-wireguard-peer.sh <NEW_MIKROTIK_PUBLIC_KEY>
#
# The script:
#   1. removes the stale peer AND updates /etc/wireguard/wg0.conf
#   2. re-adds the peer with AllowedIPs 10.10.10.2/32 (tunnel subnet)
#   3. sets PersistentKeepalive = 25 (MikroTik also keeps 25s on its side)
# No Endpoint line: the MikroTik initiates outbound, so the droplet learns
# the endpoint dynamically and follows Starlink IP changes automatically.
# ============================================================================
set -euo pipefail

# Public key of the *previous* router peer, used only to remove its stale
# [Peer] block from wg0.conf. WireGuard public keys are not secret; leave empty
# for a fresh install (no stale peer to clean). When replacing an existing peer
# (e.g. after a factory reset), set this to the old router's public key.
OLD_PUBKEY=""
WG_IF="wg0"
CONF="/etc/wireguard/wg0.conf"
NEW_PUBKEY="${1:?usage: $0 <new_mikrotik_public_key>}"

if [[ ! "$NEW_PUBKEY" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
    echo "error: '$NEW_PUBKEY' does not look like a WireGuard public key" >&2
    exit 1
fi
if [[ "$NEW_PUBKEY" == "$OLD_PUBKEY" ]]; then
    echo "Nothing to do - that is the old (dead) key."
    exit 0
fi

echo "== Droplet: updating live tunnel config (runtime) =="
sudo wg set "$WG_IF" peer "$OLD_PUBKEY" remove 2>/dev/null || echo "   (old key was not attached - ok)"
sudo wg set "$WG_IF" peer "$NEW_PUBKEY" allowed-ips 10.10.10.2/32 persistent-keepalive 25
echo "   live config updated: allowed-ips 10.10.10.2/32, keepalive 25s"

echo "== Droplet: persisting change in $CONF =="
if [[ -f "$CONF" ]]; then
    sudo cp "$CONF" "$CONF.bak.$(date +%s)"
    sudo python3 - "$CONF" "$OLD_PUBKEY" "$NEW_PUBKEY" <<'PY'
import re, sys

path, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    text = f.read()

# Split into [Section] blocks (comments preserved with their section)
header = []
parts = re.split(r'(?m)^(?=\[)', text)
keep = []
for part in parts:
    if not part:
        continue
    # a block is a closed section if it matches [..] (i.e. it does NOT start
    # mid-file as leading comments/globals before the first section)
    m = re.match(r'\[(?P<name>[^\]]+)\]\s*', part)
    if m and m.group('name') == 'Peer' and re.search(r'(?im)^\s*PublicKey\s*=\s*(?P<key>' + re.escape(old) + r')\s*$', part):
        print(f"   dropped stale [Peer] block (PublicKey {old[:12]}...)", file=sys.stderr)
        continue
    keep.append(part)

out = "".join(keep).rstrip() + "\n\n[Peer]\nPublicKey = " + new + \
      "\nAllowedIPs = 10.10.10.2/32\nPersistentKeepalive = 25\n"

with open(path, "w") as f:
    f.write(out)
print("   wg0.conf rewritten", file=sys.stderr)
PY
    # verify it parses
    sudo wg-quick strip "$WG_IF" >/dev/null
    echo "   verified: 'wg quick strip $WG_IF' parses OK"
else
    echo "   note: $CONF not found - skipped persistence."
fi

echo ""
echo "== Check with: sudo wg show $WG_IF =="
echo "After you reboot/turn on the MikroTik you should see a fresh handshake."