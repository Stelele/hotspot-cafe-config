# Droplet login hook (stock bootstrap5, no theme clone)

Live on droplet: `/var/www/rdcore/login/bootstrap5/js/njeremoto.js` (UNTRACKED file
in rdcore git -> upstream pulls never touch it) + ONE line in
`login/bootstrap5/index.html` after the sDynamic.js include:

```html
<script src="js/njeremoto.js"></script>
```

Source of truth: `njeremoto.js` in this directory (scp it to the droplet).
Backup of pre-hook index.html: `/root/njeremoto-hook-backup-index.html.2026-09-17`.

## After any upstream rdcore pull

```bash
grep -c njeremoto.js /var/www/rdcore/login/bootstrap5/index.html || echo "RE-ADD the script line"
```

## What the hook does

1. Prepends the Njeremoto bird SVG (paths lifted verbatim from
   `mikrotik/hotspot/login.html`) to the navbar title.
2. Injects a "Buy a WiFi Voucher" button + note into the `#nav-voucher` pane.
   The checkout link passes `linklogin=<this page URL>` so the Frappe portal
   returns `#rd-voucher=` here; no Frappe-side change needed.
3. `#rd-voucher=` fragment receiver: fills `#txtVoucher`, clicks `#btnConnect`,
   sessionStorage stash + 2 retries + manual-code banner (ported from the old
   router page), plus the dormant postMessage listener.

RADIUSDesk detail: "Njeremoto Internet Cafe" (id 21, realm 20, Default theme),
pair `nasid=njeremoto-cafe-01`. Branding name/colour are DB-backed.
