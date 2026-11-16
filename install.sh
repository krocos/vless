#!/bin/bash

set -e

if [ "$EUID" -ne 0 ]; then
  echo "Чо ты как не мужык, запускай от root!"
  exit 1
fi

apt update -y
apt install openssl unzip wget -y

REMARK="${1:-double_bouble_trouble}"
PORT="${2:-443}"
SNI="${3:-www.nvidia.com}"
PUBLIC_IP=$(curl -s ipv4.ip.sb)

if [ -z "$PUBLIC_IP" ]; then
  echo "Не удалось определить публичный IP!"
  exit 1
fi

rm -f Xray-linux-64.zip
### wget -q https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
### Самая последняя версия xray не работает ибо там пиздец правила хэндшейка и всякие там sing-box'ы не пашут
wget https://github.com/XTLS/Xray-core/releases/download/v26.6.27/Xray-linux-64.zip
unzip -o Xray-linux-64.zip xray

mv -f xray /usr/local/bin
xray version

UUID=$(xray uuid)
KEYS=$(xray x25519)
PRIVATE_KEY=$(echo "$KEYS" | grep "PrivateKey" | awk '{print $2}')
PUBLIC_KEY=$(echo "$KEYS" | grep "Password" | awk '{print $3}')
SHORT_ID=$(openssl rand -hex 8)

mkdir -p /etc/xray
cat <<EOF | tee /etc/xray/config.json
{
  "inbounds": [
    {
      "port": $PORT,
      "protocol": "vless",
      "settings": {
        "clients": [
          {
            "id": "$UUID",
            "flow": "xtls-rprx-vision"
          }
        ],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "raw",
        "security": "reality",
        "realitySettings": {
          "target": "$SNI:443",
          "serverNames": ["$SNI"],
          "privateKey": "$PRIVATE_KEY",
          "shortIds": ["$SHORT_ID"]
        }
      }
    }
  ],
  "outbounds":[
    {
      "protocol":"freedom",
      "tag":"direct"
    }
   ]
}
EOF

xray run -test -config /etc/xray/config.json

cat <<EOF | tee /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS
After=network.target nss-lookup.target

[Service]
User=root
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reexec
systemctl enable --now xray

if ! systemctl is-active --quiet xray; then
  echo "Сервис не запустился, проверь journalctl -u xray -n 50"
  exit 1
fi

VLESS_URL="vless://$UUID@$PUBLIC_IP:$PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=$SNI&fp=chrome&pbk=$PUBLIC_KEY&sid=$SHORT_ID&type=tcp&headerType=none#$REMARK"

echo ""
echo "Ссылка:"
echo "$VLESS_URL"
echo ""
echo "Она же в файле ~/xray_url.txt"
echo "$VLESS_URL" > ~/xray_url.txt
