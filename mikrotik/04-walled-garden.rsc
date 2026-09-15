# Phase 4 - Walled garden for the Frappe guest voucher portal
# Lets pre-auth hotspot clients reach https://njeremoto.jh.erpnext.com
# (voucher shop full-page flow + status polling).
# Run AFTER the portal app is live on the Frappe Cloud site.
# Verify with the QA checklist in radius_desk
# docs/superpowers/specs/2026-09-12-hotspot-embed-voucher-purchase-design.md
# NOTE: the console menu is walled-garden ip with a space, not hyphenated.
# NOTE: action is accept (allow is only valid on the hostname-based
# walled-garden menu; the import parser rejects action=allow here).

/ip hotspot walled-garden ip
add action=accept dst-host=njeremoto.jh.erpnext.com comment="Frappe guest voucher portal pre-auth"

# Block DNS-over-HTTPS / DNS-over-TLS bypass: a client using DoH resolves
# the portal to different edge IPs than the ones the walled-garden entry
# allowed, breaking the portal before login. Clients must use the router DNS.
# NOTE: RouterOS array literals separate elements with semicolons.
/ip firewall filter
add chain=forward action=drop protocol=tcp dst-port=853 comment="block DoT and DoH port 853"
add chain=forward action=drop protocol=udp dst-port=853 comment="block DoT and DoH port 853"
:foreach addr in={"1.1.1.1";"1.0.0.1";"8.8.8.8";"8.8.4.4";"9.9.9.9";"149.112.112.112"} do={
    /ip firewall filter add chain=forward action=drop dst-address=$addr comment="block known public DNS resolver - use router DNS"
}
