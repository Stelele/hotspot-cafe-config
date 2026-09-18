# Droplet-hosted Njeremoto portal (server-side login, no browser-to-router calls)

Why: the stock bootstrap5 engine logs in via JSONP to http://192.168.88.1,
which every modern full browser blocks as mixed content from an https page
("MT Not responding to login requests") — and a direct form POST triggers
Chrome's insecure-form warning. So the browser talks HTTPS only to the droplet;
the droplet logs the device into the router via RouterOS API over WireGuard.

Live on droplet (UNTRACKED dir, survives rdcore pulls):
`/var/www/rdcore/login/njeremoto/` = `index.html`, `usage.html`,
`api-login.php`, `api-usage.php`, `img/` (logo, favicon, status QR).
Source of truth: `droplet/login-njeremoto/` in this repo (scp to deploy).

- `index.html`: Njeremoto skin (real bird PNG from `img/logo.png`),
  Voucher tab (input + Connect, Buy button BELOW it) + Username/Password tab.
  Submits to `api-login.php` (same-origin fetch); overlay spinner on every
  attempt; lands on usage-first dst. `#rd-voucher=` receiver auto-submits.
  Zero `http://` refs (verified).
- `usage.html`: dual-mode usage-or-login at
  `https://status-radius.giftmugweni.com` (bare domain 302s here via nginx).
  Session mode shows live counters (uptime, session-time-left, data) polled
  every 15s, Continue + Log out buttons (logout = router servlet + ?dst= back
  here), QR code for bookmark/scan return. Login mode mirrors index.html.
  Falls through to login when no open session.
- `api-login.php`: RouterOS `/ip/hotspot/active/login` via API; server-built
  dst (usage + `?ip=` + optional `&next=`); rate-limited; secret from php-fpm
  env (`zz-njeremoto.conf`), never in code.
- `api-usage.php`: live RouterOS active entry first (uptime, session-time-left,
  bytes), radacct fallback second; DB pass from php-fpm env.

RADIUSDesk wiring (DB): detail 21 `theme='Custom'`,
`mikrotik_desktop/mobile_url` AND `coova_desktop/mobile_url` all =
`https://radius.giftmugweni.com/login/njeremoto/index.html`
(the mikrotik detect path reads the coova_* columns — codebase quirk).

Router: `hotspot-redirect/login.html` stub v3 POSTs `link_orig` (`$(link-orig)`)
and `client_ip` (`$(ip)`) so the pages know dst + which host to bind.
Rollback: detail 21 `theme='Default'` restores stock bootstrap5 in seconds.
