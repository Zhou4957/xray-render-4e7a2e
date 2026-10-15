#!/bin/bash
# FFxF Ubuntu 24.04 node: Xray VLESS+WS+TLS (TCP 443, Let's Encrypt) + Hysteria2 (UDP 443)
# Real IPv4, no Cloudflare tunnel, no WARP needed.
# Secrets are generated locally on the server and never leave it except inside the subscription file.
set -e
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
export DEBIAN_FRONTEND=noninteractive

DOMAIN="vm-n7felgmy1.ffxf.zone"
LE_EMAIL="zhouzhiren@gmail.com"
G=https://github.com
MIRROR=https://gh.llkk.cc/https://github.com

apt-get update -qq
apt-get install -y -qq unzip openssl python3 ca-certificates curl certbot iproute2 >/dev/null

cd /tmp
dl() {
  local out="$1" url="$2" sha="$3"
  if ! curl -fsSL --retry 3 -o "$out" "$url"; then
    echo "direct download failed, trying mirror: $out"
    curl -fsSL --retry 3 -o "$out" "$MIRROR/${url#$G/}"
  fi
  echo "$sha  $out" | sha256sum -c --quiet
}
dl x.zip  $G/XTLS/Xray-core/releases/download/v26.3.27/Xray-linux-64.zip 23cd9af937744d97776ee35ecad4972cf4b2109d1e0fe6be9930467608f7c8ae
dl hy     $G/apernet/hysteria/releases/download/app/v2.13.0/hysteria-linux-amd64 907ba8c9693edb104b20582681fb7dc15639d5b64a9cbb616a7b539190a86691
unzip -o -q x.zip xray -d /usr/local/bin
install -m755 hy /usr/local/bin/hysteria

mkdir -p /etc/proxy /var/www/sub
if [ -f /etc/proxy/env ]; then
  . /etc/proxy/env
else
  UUID=$(cat /proc/sys/kernel/random/uuid)
  HY2_PASS=$(openssl rand -hex 16)
  WS_PATH="/$(openssl rand -hex 8)"
  SUB_PATH=$(openssl rand -hex 8)
  cat > /etc/proxy/env <<EOF
UUID=$UUID
HY2_PASS=$HY2_PASS
WS_PATH=$WS_PATH
SUB_PATH=$SUB_PATH
EOF
  chmod 600 /etc/proxy/env
  . /etc/proxy/env
fi

# TLS certificate (standalone, port 80 must be free)
if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
  certbot certonly --standalone --non-interactive --agree-tos -m "$LE_EMAIL" -d "$DOMAIN" \
    --deploy-hook "systemctl restart xray hysteria" || {
      echo "CERTBOT_FAILED: could not obtain certificate for $DOMAIN"
      exit 1
    }
fi
CERT="/etc/letsencrypt/live/$DOMAIN/fullchain.pem"
KEY="/etc/letsencrypt/live/$DOMAIN/privkey.pem"

# Xray config: VLESS+WS+TLS on TCP 443
cat > /etc/proxy/xray.json <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [{
    "port": 443,
    "protocol": "vless",
    "settings": {
      "clients": [{"id": "$UUID", "flow": ""}],
      "decryption": "none"
    },
    "streamSettings": {
      "network": "ws",
      "security": "tls",
      "tlsSettings": {
        "certificates": [{"certificateFile": "$CERT", "keyFile": "$KEY"}]
      },
      "wsSettings": {"path": "$WS_PATH"}
    }
  }],
  "outbounds": [{"protocol": "freedom", "tag": "direct"}]
}
EOF
python3 -c "import json; json.load(open('/etc/proxy/xray.json'))" && echo "XRAY_CONFIG_OK"

# Hysteria2 config: UDP 443, same cert
cat > /etc/proxy/hysteria.yaml <<EOF
listen: :443
tls:
  cert: $CERT
  key: $KEY
auth:
  mode: password
  config: $HY2_PASS
masquerade:
  type: proxy
  proxy:
    url: https://bing.com
    rewriteHost: true
EOF

# Subscription file
VLESS_URL="vless://$UUID@$DOMAIN:443?encryption=none&security=tls&sni=$DOMAIN&type=ws&host=$DOMAIN&path=${WS_PATH}##FFxF-VLESS"
HY2_URL="hysteria2://$HY2_PASS@$DOMAIN:443/?sni=$DOMAIN&insecure=0#FFxF-HY2"
printf '%s\n%s\n' "$VLESS_URL" "$HY2_URL" | base64 -w0 > "/var/www/sub/$SUB_PATH"
echo "$VLESS_URL" > /etc/proxy/vless.txt
echo "$HY2_URL" > /etc/proxy/hy2.txt

# systemd services
cat > /etc/systemd/system/xray.service <<EOF
[Unit]
Description=Xray
After=network-online.target
Wants=network-online.target
[Service]
ExecStart=/usr/local/bin/xray -config /etc/proxy/xray.json
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
cat > /etc/systemd/system/hysteria.service <<EOF
[Unit]
Description=Hysteria2
After=network-online.target xray.service
Wants=network-online.target
[Service]
ExecStart=/usr/local/bin/hysteria server -c /etc/proxy/hysteria.yaml
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
cat > /etc/systemd/system/subweb.service <<EOF
[Unit]
Description=Subscription web server
After=network-online.target
Wants=network-online.target
[Service]
ExecStart=/usr/bin/python3 -m http.server 8080 --directory /var/www/sub --bind 0.0.0.0
Restart=always
RestartSec=5
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now xray hysteria subweb
sleep 3
systemctl is-active --quiet xray && echo "xray active"
systemctl is-active --quiet hysteria && echo "hysteria active"
systemctl is-active --quiet subweb && echo "subweb active"

# Local checks
echo "--- listeners ---"
ss -tlnp | grep ':443 ' || echo "NO TCP 443 LISTENER"
ss -ulnp | grep ':443 ' || echo "NO UDP 443 LISTENER"
SUB_URL="http://$DOMAIN:8080/$SUB_PATH"
echo "--- subscription (local fetch) ---"
curl -fsSL "http://127.0.0.1:8080/$SUB_PATH" | head -c 120; echo
echo "SUB_URL=$SUB_URL"
echo "VLESS_URL=$VLESS_URL"
echo "HY2_URL=$HY2_URL"
echo "DONE"
