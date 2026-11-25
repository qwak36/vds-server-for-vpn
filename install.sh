#!/usr/bin/env bash

set -e

if [ "$EUID" -ne 0 ]; then
echo "[!] Please run the script with root (sudo ./install.sh)"
exit 1
fi

read -p "Enter the server’s external IP address (or domain): " SERVER_IP

if [ -z "$SERVER_IP" ]; then
echo "[!] The IP address cannot be empty."
exit 1
fi



echo -e "Downloading and installing dependencies..."
apt update && apt upgrade -y
apt install -y curl wget software-properties-common ufw iptables nano udev
add-apt-repository ppa:amnezia/ppa -y
apt update
apt install -y amneziawg amneziawg-tools nginx
curl -s -S -L https://raw.githubusercontent.com/AdguardTeam/AdGuardHome/master/scripts/install.sh | sh -s -- -v

AWG_FILE="/etc/amnezia/amneziawg/awg0.conf"
AMNEZIA_DIR="/etc/amnezia/amneziawg"
SERVER_PRIV_KEY=$(awg genkey)
SERVER_PUB_KEY=$(echo "$SERVER_PRIV_KEY" | awg pubkey)






if [ ! -d "$AMNEZIA_DIR" ]; then
mkdir -p /etc/amnezia/amneziawg
fi

if [ ! -f "$AWG_FILE" ]; then
cat <<EOF > /etc/amnezia/amneziawg/awg0.conf
[Interface]
PrivateKey = ${SERVER_PRIV_KEY}
Address = 10.0.0.1/24
ListenPort = 51820
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

# AmneziaWG noise parameters
Jc = 4
Jmin = 40
Jmax = 70
S1 = 15
S2 = 25

EOF
else
echo "File already exists: /etc/amnezia/amneziawg/awg0.conf. Skipping creation."
exit 1
fi
chmod 600 /etc/amnezia/amneziawg/awg0.conf
systemctl enable awg-quick@awg0
systemctl restart awg-quick@awg0 || echo "[!] Warning: Check the awg-quick status manually."






echo -e "\n[2/5] Enabling IP forwarding..."
sysctl -w net.ipv4.ip_forward=1
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf; then
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi







echo -e "\n[3/5] Configuring AdGuard Home..."
mkdir -p /opt/AdGuardHome
cat <<EOF > /opt/AdGuardHome/AdGuardHome.yaml
http:
    address: 0.0.0.0:3000
    session_ttl: 720h
dns:
    bind_hosts:
        - 0.0.0.0
    port: 53
    upstream_dns:
        - https://dns.cloudflare.com/dns-query
        - https://dns.google/dns-query
        - 1.1.1.1
        - 8.8.8.8
EOF
systemctl restart AdGuardHome







echo -e "\n[4/5] Configuring Nginx..."
rm -f /etc/nginx/sites-enabled/default
cat <<EOF > /etc/nginx/sites-available/adguard
server {
    listen 80;
    server_name ${SERVER_IP};

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # WebSockets support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

ln -sf /etc/nginx/sites-available/adguard /etc/nginx/sites-enabled/
nginx -t
systemctl restart nginx





echo -e "\n[5/5] Setting up firewall UFW..."
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP Nginx'
ufw allow 443/tcp comment 'HTTPS Nginx'
ufw allow 51820/udp comment 'AmneziaWG'
ufw allow 53/udp comment 'DNS AdGuard'
ufw allow 53/tcp comment 'DNS AdGuard'

echo "y" | ufw enable

echo "The installation is complete."
echo "The AdGuard Home web panel is available at: http://${SERVER_IP}/"

echo "$SERVER_PUB_KEY" > /etc/amnezia/amneziawg/server_public_key.txt
echo "Server public key in /etc/amnezia/amneziawg/server_public_key.txt"

