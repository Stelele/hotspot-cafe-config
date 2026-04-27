#!/bin/sh
set -e

# Wait for WireGuard interface to be ready
sleep 2

# Forward RADIUS traffic from WireGuard clients to daloradius container
# daloradius is at 172.19.0.4 on the Docker bridge network
iptables -t nat -A PREROUTING -i wg0 -p udp --dport 1812 -j DNAT --to-destination 172.19.0.4:1812
iptables -t nat -A PREROUTING -i wg0 -p udp --dport 1813 -j DNAT --to-destination 172.19.0.4:1813
iptables -A FORWARD -i wg0 -p udp -d 172.19.0.4 --dport 1812 -j ACCEPT
iptables -A FORWARD -i wg0 -p udp -d 172.19.0.4 --dport 1813 -j ACCEPT

echo "RADIUS forwarding rules applied"

# Pass through to original entrypoint
exec /usr/local/bin/docker-entrypoint.sh "$@"
