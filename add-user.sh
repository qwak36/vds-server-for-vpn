#!/usr/bin/env bash

set -e

if [ "$EUID" -ne 0 ]; then
  echo "[!] to run script with root (sudo ./add-user.sh [client_name])"
  exit 1
fi








AWG_CONF="/etc/amnezia/amneziawg/awg0.conf"
INTERFACE="awg0"

if [ ! -f "$AWG_CONF" ]; then
  echo "[!] error: configuration file $AWG_CONF dont find."
  exit 1
fi

if ! command -v qrencode &> /dev/null; then
  apt update -qq && apt install -y qrencode -qq
fi







CLIENT_NAME="$1"
if [ -z "$CLIENT_NAME" ]; then
  read -p "to insert name new client (example: phone, laptop): " CLIENT_NAME
fi

CLIENT_NAME=$(echo "$CLIENT_NAME" | sed 's/[^a-zA-Z0-9_-]//g')

if [ -z "$CLIENT_NAME" ]; then
  echo "[!] Client name cannot be empty."
  exit 1
fi

# Checking for the existence of a client with that name
if grep -q "# Client: ${CLIENT_NAME}$" "$AWG_CONF"; then
  echo "[!] error: client with '${CLIENT_NAME}' already exist in $AWG_CONF"
  exit 1
fi

# ------------------------------------------------------------------------------
# 1. Definition of a free IP address in the 10.0.0.0/24 network
# ------------------------------------------------------------------------------
USED_IPS=$(grep -E -o '10\.0\.0\.[0-9]+' "$AWG_CONF" | cut -d. -f4 | sort -n)

NEW_IP_LAST=0
for last_octet in $(seq 2 254); do
  if ! echo "$USED_IPS" | grep -q -w "$last_octet"; then
    NEW_IP_LAST=$last_octet
    break
  fi
done

if [ "$NEW_IP_LAST" -eq 0 ]; then
  echo "[!] error: Limit of IP addresses in subnet 10.0.0.0/24 reached"
  exit 1
fi

CLIENT_IP="10.0.0.${NEW_IP_LAST}"

SERVER_PUB_KEY=$(awg pubkey < <(grep "PrivateKey" "$AWG_CONF" | awk '{print $3}'))
SERVER_PORT=$(grep "ListenPort" "$AWG_CONF" | awk '{print $3}')

# Searching for the external IP address of the server
SERVER_IP=$(curl -s4 ifconfig.me || curl -s4 api.ipify.org)






# Extracting noise parameters from the interface
JC=$(grep -i "^Jc" "$AWG_CONF" | awk '{print $3}' || echo "4")
JMIN=$(grep -i "^Jmin" "$AWG_CONF" | awk '{print $3}' || echo "40")
JMAX=$(grep -i "^Jmax" "$AWG_CONF" | awk '{print $3}' || echo "70")
S1=$(grep -i "^S1" "$AWG_CONF" | awk '{print $3}' || echo "15")
S2=$(grep -i "^S2" "$AWG_CONF" | awk '{print $3}' || echo "25")






CLIENT_PRIV_KEY=$(awg genkey)
CLIENT_PUB_KEY=$(echo "$CLIENT_PRIV_KEY" | awg pubkey)

cat <<EOF >> "$AWG_CONF"
[Peer]
# Client: ${CLIENT_NAME}
PublicKey = ${CLIENT_PUB_KEY}
AllowedIPs = ${CLIENT_IP}/32
EOF






# ------------------------------------------------------------------------------
# 5. Hot interface update without restarting (without disconnecting connections)
# ------------------------------------------------------------------------------
if systemctl is-active --quiet "awg-quick@${INTERFACE}"; then
  awg set "$INTERFACE" peer "$CLIENT_PUB_KEY" allowed-ips "${CLIENT_IP}/32"
else
  echo "[!] Warning: Service awg-quick@${INTERFACE} is not active. Changes saved only in config."
fi






# ------------------------------------------------------------------------------
# 6. Saving the client configuration file and displaying the QR code
# ------------------------------------------------------------------------------
OUTPUT_DIR="./clients"
mkdir -p "$OUTPUT_DIR"
CLIENT_CONF_PATH="${OUTPUT_DIR}/${CLIENT_NAME}.conf"

cat <<EOF > "$CLIENT_CONF_PATH"
[Interface]
PrivateKey = ${CLIENT_PRIV_KEY}
Address = ${CLIENT_IP}/24
DNS = 10.0.0.1

Jc = ${JC}
Jmin = ${JMIN}
Jmax = ${JMAX}
S1 = ${S1}
S2 = ${S2}

[Peer]
PublicKey = ${SERVER_PUB_KEY}
Endpoint = ${SERVER_IP}:${SERVER_PORT}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

chmod 600 "$CLIENT_CONF_PATH"

echo "=================================================="
echo "   Client added successfully: ${CLIENT_NAME}"
echo "=================================================="
echo " Assigned IP: ${CLIENT_IP}"
echo " Config saved to: ${CLIENT_CONF_PATH}"
echo "--------------------------------------------------"
echo "Scan the QR code in the AmneziaWG app:"
echo ""

qrencode -t ansiutf8 < "$CLIENT_CONF_PATH"

echo "--------------------------------------------------"