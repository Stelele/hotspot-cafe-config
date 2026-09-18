# HTTPS for Hotspot via RADIUSDesk Central Pages — Design (2026-09-17)

## Visual

```
Option A (chosen)                        Option B (fallback)
─────────────                            ───────────────────
[client] --http--> [hAP stub]            [droplet certbot DNS-01]
   | 302 https://radius...                  | scp fullchain+key
   v                                         v
[droplet nginx :443 LE]                  [hAP https://hotspot...]
   | PAP back to 192.168.88.1               | auth over WG (same)
   v                                         v
[FreeRADIUS 10.10.10.1]                  [FreeRADIUS 10.10.10.1]
```

## Decisions

| # | Decision | Reason |
|---|----------|--------|
| 1 | Primary = RADIUSDesk dynamic pages on existing `radius.giftmugweni.com` LE cert | Zero new renewal work; verified cert VALID to 2026-10-21 with snap renew timer; hAP lite 32MB avoids TLS load; best captive-portal behaviour |
| 2 | Router serves only `hotspot-redirect/login.html` stub (POST to `.../mikrotik-browser-detect`) | Upstream rdcore stub pattern; keeps `$(identity)` = `njeremoto-cafe-01` as the NAS key |
| 3 | Match via Dynamic Pair `nasid=njeremoto-cafe-01` to new "Njeremoto" detail | Existing pattern: `nasid=mcp_26` -> Dev detail id 20; same mechanism |
| 4 | Walled-garden pre-auth for droplet IP + hostname | External HTTPS must load BEFORE auth; extends `04-walled-garden.rsc` pattern without touching Frappe rule |
| 5 | Keep `login-by` with `http-pap` | External page POSTs PAP to `$(link-login-only)`; already present in hsprof1 |
| 6 | Fallback B documented, not built now | Requires new `hotspot.radius.giftmugweni.com` DNS-01 cert + copy hook + RouterOS `ssl-certificate` + `dns-name`; fragile on Starlink NAT + weak CPU |
| 7 | Tunnel-down behaviour accepted | User confirmed: vouchers fail without droplet anyway, so page depending on droplet is fine |

## Why the droplet cert can't just be copied as-is

LE signed the name `radius.giftmugweni.com`. Browsers trust it only when the URL host matches.
`https://192.168.88.1/` with that cert will ALWAYS warn. "Offline page" = no public IP for
HTTP-01, so router-local HTTPS needs DNS-01 for a hotspot-only hostname, issued where DNS
is controlled (droplet), then copied to the router.

## RADIUSDesk A2 spec

- Dynamic Details -> Add "Njeremoto": Realm = Njeremoto (id 20), Theme = Default (bootstrap5),
  show_logo/name on, language en_GB.
- Dynamic Pairs on that detail: `{name: nasid, value: njeremoto-cafe-01, priority: 1}`.
- Enable voucher (user=pass) + permanent-user auth against profiles 49/51/52/53/54.
- Buy tab: link to `https://njeremoto.jh.erpnext.com/voucher-checkout/?embed=1&linklogin=...&linkorig=...`,
  return with `#rd-voucher=CODE`; preserve auto-submit + sessionStorage rescue semantics
  from current `login.html`.
- Verify: `curl -sk -w '%{redirect_url}' '.../mikrotik-browser-detect?nasid=njeremoto-cafe-01'`
  -> `.../login/bootstrap5/index.html?...` (verified 302 on 2026-09-17 with default theme;
  after pairing it should resolve to the Njeremoto detail/theme).

## Router change surface

- NEW `mikrotik/hotspot-redirect/login.html` (stub, https action, ssid Njeremoto).
- NEW `mikrotik/05-external-login.rsc` (2 walled-garden accepts + verify steps).
- NO change to `01/02/03`, `04` Frappe rule untouched, `hsprof1` unchanged except confirming http-pap present.

## Test matrix (A6)

| # | Check | How (unauth client unless noted) |
|---|-------|----------------------------------|
| 1 | Pre-auth HTTPS reachable | `curl -v https://radius.giftmugweni.com/.../mikrotik-browser-detect?nasid=...` -> 302, trusted chain |
| 2 | Redirect chain | `curl -v http://1.1.1.1` -> 302 router -> stub auto-POST -> droplet 302 -> login page, lock icon |
| 3 | iOS CNA / Android CPC / Windows | join SSID, portal pops without cert warning |
| 4 | Voucher login | code as user=pass -> internet, `SESSION-TIME-LEFT` counts, queue 10M/5M |
| 5 | Permanent user | `owner@dev` -> no time cap, 1-device limit |
| 6 | Buy flow | checkout -> return `#rd-voucher=` -> auto-connect, no typing |
| 7 | Accounting + CoA | interim updates, `Disconnect-ACK` with Framed-IP |
| 8 | Rollback | re-upload old login.html, remove 2 garden entries -> HTTP portal back |

## Self-review

- No TBDs; all IPs/names concrete (droplet 165.232.33.196, nasid njeremoto-cafe-01, realm 20).
- Consistent with README §7 voucher flow and §Later-upgrades note.
- Single-plan scope; B kept as documented fallback only.
- Break-glass when droplet down: MAC-WinBox + `ssh root@droplet -> admin@10.10.10.2`; hotspot `admin` user retained.
