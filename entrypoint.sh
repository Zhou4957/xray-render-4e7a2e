#!/bin/sh
set -e
: "${PORT:=8080}"
: "${UUID:?UUID env must be set}"
: "${WS_PATH:?WS_PATH env must be set}"
cat > /etc/xray.json <<EOF
{
  "log": {"loglevel": "warning"},
  "inbounds": [
    {
      "port": $PORT,
      "listen": "0.0.0.0",
      "protocol": "vless",
      "settings": {"clients": [{"id": "$UUID"}], "decryption": "none"},
      "streamSettings": {"network": "ws", "wsSettings": {"path": "$WS_PATH"}}
    }
  ],
  "outbounds": [{"protocol": "freedom", "tag": "direct"}]
}
EOF
exec /usr/local/bin/xray run -c /etc/xray.json
