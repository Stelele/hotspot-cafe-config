# Droplet disaster recovery — RESTORE runbook

> No secrets in this file or repo. Secret VALUES live in the 1Password
> `RadiusDesk` vault (`hotspot-api-router` already stored) and inside the
> private off-droplet bundle copy (kept OUT of this public repo).
> Bundle location on droplet: `/root/restore-bundle/<date>/`.

## Rebuild from scratch (new droplet, Ubuntu 24.04)

1. Base: install nginx + certbot + FreeRADIUS 3.0 + PHP 8.3-fpm + MySQL,
   WireGuard; `ufw` rules per `ufw-status.txt` in bundle.
2. TLS: restore `/etc/letsencrypt` from `letsencrypt.tar.gz`, or re-issue
   (`certbot --nginx -d radius.giftmugweni.com`) and re-enable renewal timer.
3. WireGuard: restore `/etc/wireguard/wg0.conf` (keys in 1Password if rotated),
   `systemctl enable --now wg-quick@wg0`. Router side needs no change
   (endpoint learned via keepalive) — verify `wg show wg0` handshake.
4. MySQL: create db `rd`, import `rd-dump.sql`. DB password: 1Password.
5. FreeRADIUS: extract `freeradius-etc.tar.gz` over `/etc/freeradius/3.0`.
   Site secret (`dynamic-clients`): 1Password if rotation needed.
6. RADIUSDesk: clone rdcore at the recorded commit (see bundle notes),
   apply `rdcore-tracked.diff`, extract `rdcore-untracked.tar.gz` into
   `login/`, restore `/etc/cron.d/radiusdesk` + pool env
   (`zz-njeremoto.conf` needs the API password from 1Password).
7. Verify: `certbot certificates`, detect-URL 302, `info-for` detail 21,
   API CONNECT-OK probe, on-site portal test.

## After every change session

Re-run the bundle commands (step 6 of the plan), copy the dated dir
off-droplet next to previous copies, and record the rdcore commit hash.

## Also enable

DigitalOcean droplet snapshot (control panel) — whole-disk belt-and-braces.
