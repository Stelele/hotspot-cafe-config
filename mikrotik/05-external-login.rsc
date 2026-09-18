# Phase 5 - External RADIUSDesk login pages over HTTPS (trusted LE cert)
# Goal: hotspot login served from https://radius.giftmugweni.com (existing LE,
# auto-renewed on the droplet) instead of http://192.168.88.1/login.
# Router only serves the redirect stub in mikrotik/hotspot-redirect/login.html.
#
# PREREQS (droplet + RADIUSDesk GUI, do these FIRST):
#  1. LE valid: ssh droplet `certbot certificates` shows radius.giftmugweni.com VALID.
#     (Verified 2026-09-17: ECDSA cert, expiry 2026-10-21, snap.certbot.renew.timer active.)
#  2. RADIUSDesk GUI: Dynamic Details -> add detail "Njeremoto":
#       - Realm: Njeremoto (id 20), Theme: Default (bootstrap5) or clone of Dev detail.
#       - Dynamic Pairs -> add: name=nasid value=njeremoto-cafe-01 priority=1
#         (matches $(identity) posted by the stub; existing Dev pair nasid=mcp_26 stays).
#       - Enable voucher login (user=pass) + permanent users; add Buy link to
#         https://njeremoto.jh.erpnext.com/voucher-checkout/ carrying linklogin/linkorig
#         so the #rd-voucher= auto-submit flow keeps working.
#  3. Test the detect URL from a normal browser (should 302 to /login/bootstrap5/...):
#       https://radius.giftmugweni.com/cake4/rd_cake/dynamic-details/mikrotik-browser-detect?nasid=njeremoto-cafe-01&type=mikrotik
#
# ROUTER STEPS:
#  1. Backup live hotspot dir (WinBox Files: hotspot -> desktop) so rollback is re-upload.
#  2. Upload mikrotik/hotspot-redirect/login.html into the router's hotspot folder,
#     replacing the Njeremoto-branded login.html. Keep md5.js etc. in place (harmless).
#  3. Run the walled-garden lines below over SSH (NOT /import -- parser is stricter).
#  4. Keep hsprof1 login-by including http-pap (external page POSTs PAP back to
#     $(link-login-only)): /ip hotspot profile print -> login-by must contain http-pap.
#
# ROLLBACK: re-upload the previous login.html from backup; remove the two
# walled-garden entries below.

# --- allow pre-auth HTTPS to the droplet (IP + hostname forms) ---
/ip hotspot walled-garden ip
add action=accept dst-address=165.232.33.196 comment="RADIUSDesk external login pre-auth (droplet IP)"
add action=accept dst-host=radius.giftmugweni.com comment="RADIUSDesk external login pre-auth (hostname)"

# --- verify ---
# :put [/ip hotspot walled-garden ip print]
# From an UNAUTHENTICATED client (not the MAC-bypassed mgmt laptop):
#   curl -vk https://radius.giftmugweni.com/cake4/rd_cake/dynamic-details/mikrotik-browser-detect?nasid=njeremoto-cafe-01
#   -> 302 to /login/bootstrap5/... with a trusted cert (no -k warning needed on 2nd run)
#   http://1.1.1.1 -> 302 to router -> auto-POST -> droplet login page shows lock icon
#   voucher login -> internet; Buy flow returns #rd-voucher= and auto-submits
