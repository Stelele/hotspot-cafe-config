# ============================================================================
# MikroTik hAP lite - Phase 3 : hotspot + RADIUS (AS-BUILT 2026-09-11)
# executed and verified live (voucher login, accounting, CoA disconnect)
# ============================================================================

# ---- RADIUS client (secret = RADIUSDesk site-wide secret, defined in
#      /etc/freeradius/3.0/sites-enabled/dynamic-clients on the droplet) -----
/radius add service=hotspot address=10.10.10.1 secret="CHANGE_ME_RADIUSDESK_SITE_SECRET" \
    timeout=5000ms require-message-auth=yes-for-request-resp comment="RADIUSDesk over WG"

# ---- CoA/Disconnect listener (RADIUSDesk kick button) ----------------------
/radius incoming set accept=yes port=1700

# ---- wg1 into LAN list: input firewall lets CoA + tunnel SSH through ------
/interface list member add interface=wg1 list=LAN

# ---- hotspot DHCP (replaces defconf server) --------------------------------
/ip dhcp-server remove [find name="defconf"]
/ip dhcp-server network remove [find address="192.168.88.0/24"]
/ip pool add name=hs-pool-1 ranges=192.168.88.2-192.168.88.254
/ip dhcp-server add name=dhcp1 interface=bridge address-pool=hs-pool-1 lease-time=1h comment="hotspot"
/ip dhcp-server network add address=192.168.88.0/24 gateway=192.168.88.1 dns-server=192.168.88.1 comment="hotspot"

# ---- CRITICAL AS-BUILT FIX 4: MAC-bypass the management machine FIRST ------
# The hotspot's dynamic firewall blocks everything but the portal for
# non-bypassed hosts - including SSH/WinBox to 192.168.88.1. Bind by MAC
# (survives DHCP lease changes) BEFORE enabling the hotspot server, or you
# need MAC-Winbox or the droplet tunnel to get back in:
/ip hotspot ip-binding add type=bypassed mac-address=CHANGE_ME_MGMT_MAC comment="mgmt laptop"

# ---- CRITICAL AS-BUILT FIX 5: disable fasttrack ----------------------------
# Fasttracked traffic bypasses queues -> per-user Mikrotik-Rate-Limit would
# silently not apply:
/ip firewall filter disable [find comment="defconf: fasttrack"]

# ---- robustness: cap connections per LAN client ------------------------------
# The hAP lite has 32MB RAM; one pathologically chatty client (1000s of
# sockets) can exhaust connection tracking and stall the whole router.
# Drop NEW forward connections from a single LAN IP beyond 300. Placed after
# accept-established/related + drop-invalid, before the WAN drop (rule 23 live):
/ip firewall filter add chain=forward src-address=192.168.88.0/24 \
    connection-state=new connection-limit=300,32 action=drop \
    comment="per-device conn limit"

# ---- profile + server -------------------------------------------------------
/ip hotspot profile add name=hsprof1 use-radius=yes radius-accounting=yes \
    radius-interim-update=00:10:00 login-by=http-chap,http-pap,cookie \
    html-directory=hotspot
/ip hotspot add name=hotspot1 interface=bridge profile=hsprof1 \
    address-pool=hs-pool-1 idle-timeout=5m

# ---- break-glass local user (works when tunnel is down; NOTE: local users
#      do NOT generate RADIUS accounting - by design) -------------------------
/ip hotspot user add name=admin password="CHANGE_ME_BREAK_GLASS" comment="break-glass"

# ---- verify ----------------------------------------------------------------
# /radius monitor 0 once  -> Accounting-On: requests/accepts climb
# unauth client curl http://1.1.1.1 -> 302 to http://192.168.88.1/login?...
# login page shows "Njeremoto Internet hotspot"
# RADIUSDesk: RADIUS Clients -> New Arrivals shows njeremoto-cafe-01
#
# CoA disconnect recipe (from droplet; Framed-IP-Address is REQUIRED -
# RouterOS matches sessions by host IP, and NAKs with Unsupported-Extension
# without it):
#   echo "Acct-Session-ID=<id> ,User-Name=<user> ,NAS-IP-Address=10.10.10.2 ,Framed-IP-Address=<client-ip>" \
#     | radclient -x 10.10.10.2:1700 disconnect "<site secret>"
# -> Disconnect-ACK; radacct row gets acctterminatecause=Admin-Reset