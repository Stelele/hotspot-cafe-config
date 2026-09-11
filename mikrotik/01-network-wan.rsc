# ============================================================================
# MikroTik hAP lite - Phase 1 : bridge -> router (AS-BUILT 2026-09-11)
# RouterOS 7.22.2 - executed and verified live
# ----------------------------------------------------------------------------
# Run from a machine wired to ether2-4. Verify each block before continuing.
# ============================================================================

# ---- identity (drives RADIUSDesk "New Arrivals" onboarding) --------------
/system identity set name=njeremoto-cafe-01

# ---- wlan1 out of the bridge -> becomes the WAN uplink -------------------
/interface bridge port remove [find interface=wlan1]

# ---- interface lists: wlan1 -> WAN (defconf masquerade + input-drop
#     rules are keyed on the WAN list, so they now cover wlan1) ------------
/interface list member add interface=wlan1 list=WAN

# ---- CRITICAL AS-BUILT FIX 1: station mode -------------------------------
# QuickSet CPE leaves wlan1 in station-pseudobridge, which FLAPS endlessly
# ("unicast key exchange timeout" / "deauth: authentication not valid (2)")
# once removed from the bridge. Plain station mode is correct for a routed
# WAN uplink:
/interface wireless set wlan1 mode=station

# ---- CRITICAL AS-BUILT FIX 2: the actual PSK ------------------------------
# The QuickSet password was wrong/stale. The Cudy 2.4GHz PSK differs from
# the 5GHz one. Set it explicitly (value: ask the owner):
/interface wireless security-profiles set default authentication-types=wpa2-psk \
    unicast-ciphers=aes-ccm group-ciphers=aes-ccm \
    wpa2-pre-shared-key="CHANGE_ME_CUDY_2G4_PSK"

# ---- WAN DHCP client (replaces the dead defconf ether1 client) -----------
/ip dhcp-client remove [find interface=ether1]
/ip dhcp-client add interface=wlan1 add-default-route=yes use-peer-dns=yes comment="cudy-starlink-wan"

# ---- DNS: router answers for hotspot clients ------------------------------
# AdGuard DNS (94.140.14.14/94.140.15.15) = ad/tracker blocking for every
# client (hotspot clients resolve via the router at 192.168.88.1).
# Static servers override the WAN DHCP-provided resolver (192.168.1.1).
/ip dns set allow-remote-requests=yes servers=94.140.14.14,94.140.15.15

# ---- verify ----------------------------------------------------------------
# /ip dhcp-client print      -> bound, 192.168.1.x from the Cudy
# /ping 8.8.8.8              -> replies ~30-50ms
# /interface wireless registration-table print -> uptime climbing, not 1s loops