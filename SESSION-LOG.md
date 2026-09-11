# Session Log — Full Project Dump

> Purpose: a complete, mineable record of the entire hotspot-cafe project so a
> future agent can reconstruct full context without re-doing discovery.
> This is a chronological narrative of everything done across the build,
> the time-cap bug fix, the profile-hardening work, and the slow-internet
> debugging. Pair with `README.md` (reference) and the `mikrotik/` + `droplet/`
> runbooks (as-built scripts).
>
> ⚠️ All passwords, PSKs, keys and the RADIUS site secret are **redacted** below.
> Repo is public — keep it that way (do not reintroduce live values).

---

## PART 0 — Background & architecture goal

Build a captive-portal WiFi hotspot for **Njeremoto Internet Cafe**:

- MikroTik hAP lite runs the portal + hotspot (single 2.4 GHz radio, 32 MB RAM).
- A DigitalOcean droplet runs **RADIUSDesk + FreeRADIUS 3.0** (CakePHP 4).
- Router ↔ droplet linked by **WireGuard**, so RADIUS survives Starlink's
  changing public IP (CGNAT).
- Vouchers (user=pass, time-limited) + permanent users, both rate-limited.

## PART 1 — Router bring-up (Phases 1–3)

Router: hAP lite RB941-2nD, RouterOS 7.22.2, identity `njeremoto-cafe-01`.

Phase 1 (`01-network-wan.rsc`):
- Removed `wlan1` from the bridge → becomes the WAN uplink (station to the Cudy).
- **Gotcha 1**: QuickSet left wlan1 in `station-pseudobridge`, which flaps
  endlessly when unbridged → `mode=station`.
- **Gotcha 2**: the Cudy 2.4 GHz PSK differs from the 5 GHz PSK (both redacted);
  the QuickSet-stored PSK was stale.
- WAN DHCP client `cudy-starlink-wan` → bound `192.168.1.137/24`, gw `192.168.1.1`.
- DNS set for future clients (later switched to AdGuard).

Phase 2 (`02-wireguard.rsc`):
- `wg1` = `10.10.10.2/32`, listen-port 13231, mtu 1420, peer → droplet
  `165.232.33.196:51820`, keepalive 25 s.
- **Gotcha 3**: RouterOS did NOT auto-create a route from the peer's
  allowed-address → `/ip route add dst-address=10.10.10.1/32 gateway=wg1`.
- Droplet `update-wireguard-peer.sh` swapped the dead (factory-reset) peer key.

Phase 3 (`03-hotspot-radius.rsc`):
- `/radius` (service=hotspot, secret = site-wide, 5000 ms,
  `require-message-auth=yes-for-request-resp`), `/radius incoming accept=yes port=1700`.
- `wg1` into LAN list (lets CoA + tunnel SSH through the input firewall).
- Replaced defconf DHCP with hotspot pool `192.168.88.2-254`, lease 1 h.
- **Gotcha 4**: MAC-bypass the management laptop **before** enabling the hotspot
  (the hotspot's dynamic firewall blocks SSH/WinBox to 192.168.88.1 for
  non-bypassed hosts). Mgmt laptop MAC bound as `bypassed` in `/ip hotspot ip-binding`.
- **Gotcha 5**: disabled `fasttrack` — fasttracked traffic bypasses queues, so
  per-user `Mikrotik-Rate-Limit` would silently not apply.
- `hsprof1`: `use-radius=yes radius-accounting=yes radius-interim-update=00:10:00
  login-by=http-chap,http-pap,cookie html-directory=hotspot`.
- `hotspot1` on bridge, `idle-timeout=5m`.
- Break-glass local user `admin` (local, no RADIUS accounting; password redacted).
- Custom Njeremoto portal uploaded to `hotspot/` (voucher tab auto-fills
  username=password; md5.js does the CHAP).

Portal CHAP flow (for scripting a login):
`chap-response = hex(md5(chap-id_byte + password + 16-byte-chap-challenge))`.
The challenge is embedded in the served login page as octal escapes, e.g.
`hexMD5('\107' + pwd + '\112\045...')`. POST to `http://192.168.88.1/login` with
`username`, `password` (hex), `popup=true`.

## PART 2 — Droplet + RADIUSDesk onboarding

- Droplet `165.232.33.196`; SSH `root@...` (key `~/.ssh/<droplet-key>`).
- UFW: `51820/udp`, `1812/udp` + `1813/udp` from `10.10.10.2`.
- RADIUSDesk: `https://radius.giftmugweni.com/` (admin `root`, password redacted).
- Site-wide secret (redacted) in `/etc/freeradius/3.0/sites-enabled/dynamic-clients`.
- Onboarded router: dynamic client id 37 "Njeremoto Cafe Router", type=mikrotik,
  `session_auto_close=3600`, `avail_for_all=1`. Deleted the orphan
  `unknown_dynamic_clients` row for `njeremoto-cafe-01`.
- `cloud_id=23`, realm "Dev" (id 19), timezone id 24.

RADIUSDesk v4 API pattern (important — differs from older docs):
- Auth: `POST /cake4/rd_cake/dashboard/authenticate.json` with body
  `token=&username=root&password=...` → returns `data.token`.
- All further calls: `POST /cake4/rd_cake/<controller>/<action>.json` with
  `token=<token>` in the **body** (not headers). `cloud_id` must be included
  where the controller requires it.
- Profile create: `profiles/simple-add.json` with `speed_limit_enabled`,
  `speed_download_amount`/`speed_download_unit`, `speed_upload_*`,
  `session_limit_enabled` + `session_limit` (→ `Simultaneous-Use`). WISPr
  attributes are what the API writes; `Mikrotik-Rate-Limit` (with burst) is set
  by direct radgroupreply edit.
- Voucher create: `vouchers/add.json` with `realm_id`, `profile_id`, `cloud_id`,
  `single_field=true` (user=pass), `never_expire=true`, `quantity`.
- Permanent user create: `permanent-users/add.json` with `realm_id`,
  `profile_id`, `username`, `password`, `active`. The realm "Dev" auto-appends
  `@dev` suffix → `owner@dev`.

## PART 3 — Verification (Phase 6, original 5M/5M build)

Verified end-to-end with voucher `fullchickens` (then 5M/5M profile):
tunnel pings, captive redirect, custom page, CHAP login, `SESSION-TIME-LEFT`
countdown, dynamic queue `limit-at=5M/5M`, accounting Start/Stop, CoA
disconnect (Admin-Reset), reboot self-recovery (Accounting-On retried until
tunnel up). Steady-state CPU 2 %, ~8.8 MiB free RAM.

## PART 4 — Time-cap bug (perpetual re-login) + fix

Problem: a time-capped profile (e.g. 2 min) auto-logged-out at the cap but the
same voucher could immediately re-login for a fresh full quota; `vouchers.time_used`
stayed NULL.

Root cause (two-fold):
1. `Rd-Used-Time` was computed from `user_stats` as
   `TIMESTAMPDIFF(created, timestamp)` — always ~0 because triggers insert
   `user_stats` rows with `created == timestamp`.
2. The cron jobs (`AccountingShell`, `VoucherShell`, `UsageTask`) weren't running.

Fix (chosen: repoint query + restore cron):
- `/etc/freeradius/3.0/policy.d/radiusdesk`: 6 `Rd-Used-Time` queries →
  `... (SELECT SUM(acctsessiontime) FROM radacct WHERE username=... AND
  acctstoptime IS NOT NULL)`.
- `src/Shell/Task/UsageTask.php`: `time_usage`, `time_usage_for_mac`,
  `find_no_reset_time_usage` likewise.
- `/etc/cron.d/radiusdesk`: 6 jobs (accounting, voucher, permanent-users
  sync-expiration, update_user_stats, rd auto_close, update_user_stats_dailies),
  paths normalized to `/var/www/rdcore/cake4/rd_cake` (symlink
  `/var/www/html/cake4 -> ../rdcore/cake4`).
- **Gotcha**: a leftover `.bak` inside `policy.d/` silently overrode edits
  (`$INCLUDE policy.d/` loads every file). Backups moved to `/root/freeradius-backups/`.

Verified both directions: exhausted voucher → `Reply-Message "Maximum usage
exceeded"`; fresh voucher accepted; full 2-min lifecycle re-test passed. Test
artifacts (`2min-test`, `scornfulwine`, `obesereaction`) deleted.

## PART 5 — Capacity analysis & profile hardening (this session)

Capacity reasoning (hardware-grounded):
- 650 MHz CPU + 32 MB RAM + fasttrack OFF → software-NAT ceiling ≈ 25–40 Mbps.
- Per-device budget: 480p ≈ 1–1.5 Mbps, 720p ≈ 2.5–4 Mbps.
- 2 Mbps/1 Mbps → ~15 concurrent streamers; idle devices up to ~30–50.

Decisions made with the owner:
- Q1: rate → **2 Mbps down / 1 Mbps up** ("480p comfy, ~15 users").
- Q2: vouchers → **time only** (1 h), no data cap.
- Robustness: **1** (conn-limit), **2** (verify Simultaneous-Use), **4** (burst),
  **5** (ad-blocking), **6** (HTTPS) → later **deferred 6**, and **dropped 3**
  (voucher auto-expiry: irrelevant once the time cap blocks re-login).

Implementation:
- Profile `1 Hour Uncapped` (id 49) → rate `Mikrotik-Rate-Limit := 2M/1M 4M/2M
  2M/1M 5/5` (burst). (Simultaneous-Use=1 + 3600 s hard cap already present.)
- New profile `Permanent` (id 51) via API → unlimited time, Simultaneous-Use=1,
  then WISPr attrs replaced with `Mikrotik-Rate-Limit` burst string.
- Router: conn-limit firewall rule (rule 23) `connection-limit=300,32`; DNS →
  AdGuard `94.140.14.14,94.140.15.15`.
- Seed data: voucher `easyactor`, permanent user `owner@dev`.

Verification (all live):
- `easyactor` login → queue `max-limit=2M/1M burst-limit=4M/2M burst-time=5s/5s`,
  `session-time-left` counting from 1 h.
- 2nd auth → `Access-Reject "Simultaneous connections limited to 1"` (C3).
- `owner@dev` → no `session-time-left`, same burst queue (C4).
- 350-conn flood → 299 opened / 51 dropped at the cap (C5). *(Note: the laptop's
  ethernet profile has `never-default`, so its internet went out WiFi and the
  first flood bypassed the router — re-ran with a temporary route
  `sudo ip route add 165.232.33.196/32 via 192.168.88.1 dev enp59s0`.)*
- AdGuard: `doubleclick.net` → `0.0.0.0`, `google.com` resolves (C6).
- Cleanup: test voucher deleted; `owner@dev` kept (owner account).

## PART 6 — "Internet is really slow" debugging (final)

Symptom: owner plugged a *separate* laptop into the cable; 1 device on the
network and it was "really slow".

Findings, in order:
1. Client `shadowylaugh` (voucher) on `192.168.88.252`, queue `max-limit=2M/1M`,
   **34,881 dropped download packets** → it was slamming into the 2 M cap.
2. Router `wlan1` RX ≈ 1.28 Mbps live; RouterOS `/tool fetch` gave ~0.6–0.85 Mbps.
   First hypothesis: 2.4 GHz WAN uplink is the bottleneck.
3. RF looked perfect (SNR 83 dB, CCQ 95 %, 144 Mbps phy) → "congestion" theory.
4. Cross-check from the mgmt laptop's WiFi (Cudy → Starlink, no router): **84 Mbps**.
   → Starlink is fine.
5. Owner connected the laptop to the **same 2.4 GHz Cudy** (Cudy-Outdoor, ch 11):
   **30 Mbps**. → the 2.4 GHz band/AP is fine too.
6. **Conclusion:** the "~1 Mbps WAN" reading was an artifact of RouterOS's weak
   single-stream `fetch` (small TCP window over the satellite RTT ≈ 50 ms →
   ~8 KB window ⇒ ~1.3 Mbps). The real link is ~30 Mbps. The actual cause of the
   slowness was the **2 Mbps profile cap**.
7. **Fix:** raised both profiles to `10M/5M 15M/8M 10M/5M 5/5`. Owner confirmed
   "yup it's good now".

Key lesson (for future agents): **never measure throughput with RouterOS
`/tool fetch` or `/tool speed-test`/`bandwidth-test` from the router** — both
underreport dramatically on high-latency (satellite) links. Measure from a real
client (`curl` on a device behind the router), or watch `/interface
monitor-traffic` during a real client download. Also, a dynamic simple queue
cannot be edited in place (`/queue simple set` on a dynamic queue fails) — the
client must re-login to pick up a new profile rate.

## PART 7 — Current final state (handoff)

- Profiles: `1 Hour Uncapped` (49) and `Permanent` (51), both
  `10M/5M 15M/8M 10M/5M 5/5`, Simultaneous-Use=1. Voucher time cap = 3600 s hard.
- Permanent user `owner@dev` (password redacted).
- Vouchers: none (owner deleted all; ERP will batch-generate).
- Router hardening: conn-limit 300/IP (rule 23), AdGuard DNS.
- All config is live and verified. Repo files are untracked (`?? README.md ??
  droplet/ ?? mikrotik/`) — not yet committed/pushed.

## PART 8 — Open items / future work

- Commit + (if desired) push the repo — but first decide on secrets (see
  README security note).
- Optional robustness still open: **HTTPS login page** (deferred), **burst**
  already applied, **voucher auto-expiry** (dropped as unnecessary).
- Possible future improvement: wire the Cudy → router with ethernet to sidestep
  the 2.4 GHz hop entirely (currently not needed — 30 Mbps is fine).
- ERP integration for voucher batch generation (the API patterns in PART 2 are
  what the ERP should call).
