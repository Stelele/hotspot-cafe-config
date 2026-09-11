# ============================================================================
# MikroTik hAP lite - Phase 2 : WireGuard -> droplet (AS-BUILT 2026-09-11)
# executed and verified live. Tunnel IP pair: 10.10.10.2 <-> 10.10.10.1
# ============================================================================

# ---- interface + address ---------------------------------------------------
/interface wireguard add name=wg1 listen-port=13231 mtu=1420
/ip address add address=10.10.10.2/32 interface=wg1

# ---- peer = droplet wg0 (public key verified via `wg show` on droplet) -----
/interface wireguard peers add interface=wg1 \
    public-key="CHANGE_ME_DROPLET_PUBKEY" \
    endpoint-address=165.232.33.196 endpoint-port=51820 \
    allowed-address=10.10.10.1/32 \
    persistent-keepalive=25s comment="droplet-wg0"

# ---- CRITICAL AS-BUILT FIX 3: static route ---------------------------------
# This RouterOS build did NOT auto-create a route from the peer's
# allowed-address. Without it, traffic to 10.10.10.1 silently follows the
# default route to the ISP and dies (handshake works, data doesn't):
/ip route add dst-address=10.10.10.1/32 gateway=wg1 comment="droplet via tunnel"

# ---- droplet side: swap the dead pre-reset peer key ------------------------
# Run on the droplet (see droplet/update-wireguard-peer.sh):
#   wg set wg0 peer <OLD_DEAD_KEY> remove
#   wg set wg0 peer <NEW_ROUTER_KEY> allowed-ips 10.10.10.2/32 persistent-keepalive 25
# Router's new public key: /interface wireguard get wg1 public-key
# (as-built value redacted; re-read with: /interface wireguard get wg1 public-key)

# ---- verify ----------------------------------------------------------------
# /ping 10.10.10.1   -> ~200ms through the tunnel (public path ~195ms)
# droplet: wg show wg0 latest-handshakes -> timestamp within 2 min (keepalive)