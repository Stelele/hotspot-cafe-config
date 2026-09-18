# Droplet-hosted Njeremoto login pages (full-POST flow, no AJAX to router)

Why: the stock bootstrap5 engine logs in via JSONP to http://192.168.88.1,
which every modern full browser blocks as mixed content from an https page
("MT Not responding to login requests"). These pages do a classic top-level
form POST instead — never blocked — and the router redirects to `dst`.

Live on droplet (UNTRACKED dir, survives rdcore pulls):
`/var/www/rdcore/login/njeremoto/index.html` + `connected.html`.
Source of truth: `droplet/login-njeremoto/` in this repo (scp to deploy).

- `index.html`: Njeremoto skin (bird SVG from `mikrotik/hotspot/login.html`),
  Voucher tab (input + Connect, Buy button BELOW it) + Username/Password tab.
  POSTs username/password/dst to `link_login_only` (PAP). `#rd-voucher=`
  receiver auto-submits. Zero `http://` subresources (verified).
- `connected.html`: static "You're online" fallback landing + usage link.

RADIUSDesk wiring (DB): detail 21 `theme='Custom'`,
`mikrotik_desktop/mobile_url` AND `coova_desktop/mobile_url` all =
`https://radius.giftmugweni.com/login/njeremoto/index.html`
(the mikrotik detect path reads the coova_* columns — codebase quirk).

Router: `hotspot-redirect/login.html` stub v2 also POSTs `link_orig`
(`$(link-orig)`) so the page knows `dst`. Rollback: detail 21
`theme='Default'` restores stock bootstrap5 in seconds.

Companion fix (separate repo): Frappe `radius_desk` branch
`feat/portal-return-to-droplet-login` lets the checkout return #rd-voucher=
to this page. MUST be merged + pulled on the Frappe Cloud bench (with migrate
for the new `hotspot_portal_return_prefix` setting) or Buy auto-return stays
broken — manual code entry still works.
