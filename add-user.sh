#!/usr/bin/env bash

set -e

if [ "$EUID" -ne 0 ]; then
  echo "[!] to run script with root (sudo ./add-user.sh [client_name])"
  exit 1
fi

WG_CONF="/etc/amnezia/amneziawg/awg0.conf"
INTERFACE="awg0"

if [ ! -f "$WG_CONF" ]; then
  echo "[!] error: configuration file $WG_CONF dont find."
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
  echo "[!] Имя клиента не может быть пустым."
  exit 1
fi

# Проверка на существование клиента с таким именем
if grep -q "# Client: ${CLIENT_NAME}$" "$WG_CONF"; then
  echo "[!] error: client with '${CLIENT_NAME}' already exist in $WG_CONF"
  exit 1
fi

# ------------------------------------------------------------------------------
# 1. Определение свободного IP-адреса в сети 10.0.0.0/24
# ------------------------------------------------------------------------------
USED_IPS=$(grep -E -o '10\.0\.0\.[0-9]+' "$WG_CONF" | cut -d. -f4 | sort -n)

NEW_IP_LAST=0
for last_octet in $(seq 2 254); do
  if ! echo "$USED_IPS" | grep -q -w "$last_octet"; then
    NEW_IP_LAST=$last_octet
    break
  fi
done

if [ "$NEW_IP_LAST" -eq 0 ]; then
  echo "[!] error: Достигнут лимит IP-адресов в подсети 10.0.0.0/24"
  exit 1
fi

CLIENT_IP="10.0.0.${NEW_IP_LAST}"

SERVER_PUB_KEY=$(awg pubkey < <(grep "PrivateKey" "$WG_CONF" | awk '{print $3}'))
SERVER_PORT=$(grep "ListenPort" "$WG_CONF" | awk '{print $3}')

# Поиск внешнего IP сервера
SERVER_IP=$(curl -s4 ifconfig.me || curl -s4 api.ipify.org)

# Извлечение параметров зашумления из интерфейса
JC=$(grep -i "^Jc" "$WG_CONF" | awk '{print $3}' || echo "4")
JMIN=$(grep -i "^Jmin" "$WG_CONF" | awk '{print $3}' || echo "40")
JMAX=$(grep -i "^Jmax" "$WG_CONF" | awk '{print $3}' || echo "70")
S1=$(grep -i "^S1" "$WG_CONF" | awk '{print $3}' || echo "15")
S2=$(grep -i "^S2" "$WG_CONF" | awk '{print $3}' || echo "25")


CLIENT_PRIV_KEY=$(awg genkey)
CLIENT_PUB_KEY=$(echo "$CLIENT_PRIV_KEY" | awg pubkey)

cat <<EOF >> "$WG_CONF"
[Peer]
# Client: ${CLIENT_NAME}
PublicKey = ${CLIENT_PUB_KEY}
AllowedIPs = ${CLIENT_IP}/32
EOF

# ------------------------------------------------------------------------------
# 5. Горячее обновление интерфейса без перезапуска (без разрыва соединений)
# ------------------------------------------------------------------------------
if systemctl is-active --quiet "awg-quick@${INTERFACE}"; then
  awg set "$INTERFACE" peer "$CLIENT_PUB_KEY" allowed-ips "${CLIENT_IP}/32"
else
  echo "[!] Предупреждение: Служба awg-quick@${INTERFACE} не активна. Изменения сохранены только в конфиг."
fi

# ------------------------------------------------------------------------------
# 6. Сохранение файла конфигурации клиента и вывод QR-кода
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
echo "   Успешно добавлен клиент: ${CLIENT_NAME}"
echo "=================================================="
echo " Назначенный IP: ${CLIENT_IP}"
echo " Конфиг сохранен в: ${CLIENT_CONF_PATH}"
echo "--------------------------------------------------"
echo "Отсканируйте QR-код в приложении AmneziaWG:"
echo ""

qrencode -t ansiutf8 < "$CLIENT_CONF_PATH"

echo "--------------------------------------------------"