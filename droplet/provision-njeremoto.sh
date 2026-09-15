#!/usr/bin/env bash
# Provisions duration profiles for the Njeremoto realm on RadiusDesk.
# Secrets via env only — never commit them:
#   RD_HOST   RadiusDesk host, e.g. radius.giftmugweni.com
#   RD_PASS   RadiusDesk root password
#   DB_PASS   (only needed if you run the emitted SQL yourself; the script
#              never touches MySQL — cap/burst rows live behind authored SQL)
#   CLOUD_ID  default 23
#
# Design (see radius_desk spec 2026-09-15-njeremoto-realm-profiles-https):
# - Profiles are realm-agnostic in RadiusDesk (no realm_id on the profile;
#   realm binds at the voucher). The 1h plan keeps profile 49.
# - New profiles are created via profiles/simple-add.json with ALL limits
#   disabled, so the API only creates the shell + SimpleAdd_<id> component
#   (+ Fall-Through reply). Cap/burst rows are then written with explicit,
#   reviewable SQL that exactly mirrors live profile 49:
#     check: Rd-Reset-Type-Time := never, Rd-Total-Time := <cap>,
#            Rd-Cap-Type-Time := hard, Simultaneous-Use := 1
#     reply: Fall-Through := Yes, Mikrotik-Rate-Limit := 10M/5M 15M/8M 10M/5M 5/5
#   (simple-add cannot write the burst string; guessing at it is how money
#   gets lost. The API verifies via time_cap_in_profile; the live gate
#   verifies behavior.)
set -euo pipefail
: "${RD_HOST:?set RD_HOST}" ; : "${RD_PASS:?set RD_PASS}"
CLOUD_ID="${CLOUD_ID:-23}"
MODE="${1:---run}"

api() { # api <controller/action.json> [curl-data-args...]
	local endpoint="$1"; shift
	curl -s --max-time 30 -X POST "https://$RD_HOST/cake4/rd_cake/$endpoint" \
		--data-urlencode token="$TOKEN" "$@"
}

echo "== authenticate =="
TOKEN=$(curl -s --max-time 30 -X POST "https://$RD_HOST/cake4/rd_cake/dashboard/authenticate.json" \
	--data-urlencode token= --data-urlencode username=root \
	--data-urlencode password="$RD_PASS" | jq -r .data.token)
test -n "$TOKEN" && test "$TOKEN" != null || { echo "AUTH FAILED"; exit 1; }
echo "AUTH OK"

profile_id_by_name() {
	api "profiles/index.json" --data-urlencode cloud_id="$CLOUD_ID" \
		| jq -r --arg n "$1" '.items[] | select(.name == $n) | .id // empty' | head -1
}

realm_id_by_name() {
	api "realms/index.json" --data-urlencode cloud_id="$CLOUD_ID" \
		| jq -r --arg n "$1" '.items[] | select(.name == $n) | .id // empty' | head -1
}

echo "== realm =="
REALM_ID=$(realm_id_by_name Njeremoto)
if [ -z "$REALM_ID" ]; then
	echo "creating realm Njeremoto..."
	api "realms/add.json" --data-urlencode name=Njeremoto --data-urlencode cloud_id="$CLOUD_ID" | jq '{success, id: .data.id, name: .data.name}'
	REALM_ID=$(realm_id_by_name Njeremoto)
else
	echo "realm Njeremoto already exists — skipping create"
fi
test -n "$REALM_ID" || { echo "realm ID lookup failed"; exit 1; }
echo "REALM_ID=$REALM_ID"

# name -> cap seconds. 1h keeps live profile 49 (realm-agnostic), so only 3/5/24h are created.
declare -A CAPS=( ["3 Hour Uncapped"]=10800 ["5 Hour Uncapped"]=18000 ["24 Hour Uncapped"]=86400 )

if [ "$MODE" = "--inspect-only" ]; then
	echo "== inspect-only: would ensure these profiles =="
	for name in "${!CAPS[@]}"; do
		id=$(profile_id_by_name "$name")
		echo "  $name -> cap ${CAPS[$name]}s (exists id=${id:-no})"
	done
	echo "No writes performed."
	exit 0
fi

if [ "$MODE" = "--verify" ]; then
	echo "== verify =="
	fail=0
	for name in "${!CAPS[@]}"; do
		flag=$(api "profiles/index.json" --data-urlencode cloud_id="$CLOUD_ID" \
			| jq -r --arg n "$name" '.items[] | select(.name == $n) | .time_cap_in_profile // empty')
		echo "  $name time_cap_in_profile=${flag:-MISSING}"
		[ "$flag" = "true" ] || fail=1
	done
	test "$fail" -eq 0 && echo "VERIFY OK" || { echo "VERIFY FAILED"; exit 1; }
	exit 0
fi

if [ "$MODE" = "--force" ]; then
	echo "NOTE: --force deletes same-name profiles first (API delete cleans components)."
fi

echo "== profiles =="
for name in "${!CAPS[@]}"; do
	id=$(profile_id_by_name "$name")
	if [ -n "$id" ] && [ "$MODE" != "--force" ]; then
		echo "  $name exists (id=$id) — skipping create"
	else
		if [ -n "$id" ]; then
			echo "  --force: deleting $name (id=$id)..."
			api "profiles/delete.json" --data-urlencode id="$id" | jq -c '{success}'
		fi
		echo "  creating $name (limits disabled; cap rows land via SQL)..."
		api "profiles/simple-add.json" \
			--data-urlencode name="$name" \
			--data-urlencode cloud_id="$CLOUD_ID" \
			--data-urlencode sel_language="4_4" | jq -c '{success, id: .data.id}'
		id=$(profile_id_by_name "$name")
		test -n "$id" || { echo "profile create failed for $name"; exit 1; }
	fi
	echo "  $name -> profile id $id, component group SimpleAdd_$id, cap ${CAPS[$name]}s"
	echo
	echo "  -- droplet MySQL for $name (run on the droplet, database rd) --"
	cat <<SQL
DELETE FROM radgroupcheck WHERE groupname = 'SimpleAdd_$id';
DELETE FROM radgroupreply WHERE groupname = 'SimpleAdd_$id';
INSERT INTO radgroupcheck (groupname, attribute, op, value) VALUES
 ('SimpleAdd_$id', 'Rd-Reset-Type-Time', ':=', 'never'),
 ('SimpleAdd_$id', 'Rd-Total-Time', ':=', '${CAPS[$name]}'),
 ('SimpleAdd_$id', 'Rd-Cap-Type-Time', ':=', 'hard'),
 ('SimpleAdd_$id', 'Simultaneous-Use', ':=', '1');
INSERT INTO radgroupreply (groupname, attribute, op, value) VALUES
 ('SimpleAdd_$id', 'Fall-Through', ':=', 'Yes'),
 ('SimpleAdd_$id', 'Mikrotik-Rate-Limit', ':=', '10M/5M 15M/8M 10M/5M 5/5');
SQL
	echo
done

echo "Next: apply the SQL blocks on the droplet, then re-run with --verify,"
echo "then proceed to the realm-auth gate (live test voucher + hotspot login)."
