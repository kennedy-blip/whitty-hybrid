#!/bin/bash
# Deploy a WireGuard exit-node on a fresh Ubuntu VPS (run as root).
# After this, generate a client config in the web UI with this server's IP:51820.
set -e
apt-get update -qq && apt-get install -y -qq wireguard-tools iptables
sysctl -w net.ipv4.ip_forward=1
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
mkdir -p /etc/wireguard
wg genkey | tee /etc/wireguard/server.key | wg pubkey > /etc/wireguard/server.pub
cat > /etc/wireguard/wg0.conf <<WG
[Interface]
PrivateKey = $(cat /etc/wireguard/server.key)
Address = 10.8.0.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE
WG
systemctl enable --now wg-quick@wg0
ufw allow 51820/udp 2>/dev/null || true
echo "✅ WireGuard up. Server pubkey:"; cat /etc/wireguard/server.pub
echo "Now generate a client config in the Whitty UI with endpoint <this-IP>:51820"
