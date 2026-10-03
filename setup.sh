#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Jalankan sebagai root: sudo -i"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y curl wget ca-certificates jq openssl wireguard-tools nginx cron dnsutils iproute2 procps

install -d /opt/nat-vps-aio /etc/nat-vps-aio

cat >/etc/nat-vps-aio/config.env <<'EOF'
# NAT VPS AIO configuration
DOMAIN=""
XRAY_PORT="10000"
WG_PORT="51820"
DDNS_PROVIDER="none"
CF_API_TOKEN=""
CF_ZONE_ID=""
CF_RECORD_ID=""
CF_RECORD=""
EOF

cat >/opt/nat-vps-aio/ddns-update.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /etc/nat-vps-aio/config.env

[[ "${DDNS_PROVIDER:-none}" == "cloudflare" ]] || exit 0
[[ -n "${CF_API_TOKEN:-}" && -n "${CF_ZONE_ID:-}" && -n "${CF_RECORD_ID:-}" && -n "${CF_RECORD:-}" ]] || exit 0

IP="$(curl -4fsS --max-time 10 https://api.ipify.org || true)"
[[ "$IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || exit 1

curl -fsS -X PUT "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${CF_RECORD_ID}" \
  -H "Authorization: Bearer ${CF_API_TOKEN}" \
  -H "Content-Type: application/json" \
  --data "$(jq -n --arg ip "$IP" --arg name "$CF_RECORD" \
    '{type:"A",name:$name,content:$ip,ttl:60,proxied:false}')"
EOF
chmod +x /opt/nat-vps-aio/ddns-update.sh

cat >/opt/nat-vps-aio/status.sh <<'EOF'
#!/usr/bin/env bash
source /etc/nat-vps-aio/config.env
clear
echo "=============================================="
echo "          NAT VPS AIO PANEL v1.0"
echo "=============================================="
echo "Local IP : $(hostname -I 2>/dev/null | awk '{print $1}')"
echo "Public IP: $(curl -4fsS --max-time 5 https://api.ipify.org 2>/dev/null || echo '-')"
echo "Domain   : ${DOMAIN:-belum diset}"
echo "----------------------------------------------"
for svc in ssh nginx xray wg-quick@wg0; do
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    printf "%-18s : RUNNING\n" "$svc"
  else
    printf "%-18s : STOPPED/NOT INSTALLED\n" "$svc"
  fi
done
echo "----------------------------------------------"
echo "Xray port : ${XRAY_PORT}"
echo "WireGuard : ${WG_PORT}"
echo "=============================================="
EOF
chmod +x /opt/nat-vps-aio/status.sh

cat >/opt/nat-vps-aio/install-xray.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /etc/nat-vps-aio/config.env

bash -c "$(curl -LfsS https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
UUID="$(cat /proc/sys/kernel/random/uuid)"
PORT="${XRAY_PORT:-10000}"

mkdir -p /usr/local/etc/xray
cat >/usr/local/etc/xray/config.json <<JSON
{
  "log": {"loglevel": "warning"},
  "inbounds": [{
    "listen": "0.0.0.0",
    "port": ${PORT},
    "protocol": "vless",
    "settings": {
      "clients": [{"id": "${UUID}", "email": "nat-vps-aio"}],
      "decryption": "none"
    },
    "streamSettings": {"network": "tcp"}
  }],
  "outbounds": [{"protocol": "freedom"}]
}
JSON

systemctl enable xray --now
systemctl restart xray

cat >/etc/nat-vps-aio/xray-info.txt <<INFO
UUID=${UUID}
PORT=${PORT}
DOMAIN=${DOMAIN}
PROTOCOL=VLESS TCP
INFO

echo
echo "Xray VLESS TCP terpasang."
echo "UUID   : ${UUID}"
echo "PORT   : ${PORT}"
echo "DOMAIN : ${DOMAIN:-gunakan domain/DDNS kamu}"
EOF
chmod +x /opt/nat-vps-aio/install-xray.sh

cat >/opt/nat-vps-aio/install-wireguard.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /etc/nat-vps-aio/config.env

mkdir -p /etc/wireguard
if [[ ! -f /etc/wireguard/server.key ]]; then
  umask 077
  wg genkey | tee /etc/wireguard/server.key >/dev/null
  cat /etc/wireguard/server.key | wg pubkey > /etc/wireguard/server.pub
fi

PRIV="$(cat /etc/wireguard/server.key)"
PORT="${WG_PORT:-51820}"

cat >/etc/wireguard/wg0.conf <<CONF
[Interface]
Address = 10.66.66.1/24
ListenPort = ${PORT}
PrivateKey = ${PRIV}
SaveConfig = true
CONF

systemctl enable wg-quick@wg0
systemctl restart wg-quick@wg0 || systemctl start wg-quick@wg0

echo "WireGuard server aktif di port ${PORT}."
echo "Public key server: $(cat /etc/wireguard/server.pub)"
EOF
chmod +x /opt/nat-vps-aio/install-wireguard.sh

cat >/opt/nat-vps-aio/menu.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cfg=/etc/nat-vps-aio/config.env
source "$cfg"

pause(){ read -rp "Tekan Enter untuk kembali..." _; }
setcfg(){
  local key="$1" val="$2"
  sed -i -E "s|^${key}=.*|${key}=\"${val}\"|" "$cfg"
}

while true; do
  clear
  echo "╔══════════════════════════════════════════════╗"
  echo "║          NAT VPS AIO PANEL v1.0             ║"
  echo "╠══════════════════════════════════════════════╣"
  echo "║ Public IP : $(curl -4fsS --max-time 4 https://api.ipify.org 2>/dev/null || echo '-')"
  echo "║ Domain    : ${DOMAIN:-belum diset}"
  echo "╠══════════════════════════════════════════════╣"
  /opt/nat-vps-aio/status.sh | sed -n '5,12p'
  echo "╠══════════════════════════════════════════════╣"
  echo "[1] Install/Setup Xray VLESS TCP"
  echo "[2] Install/Setup WireGuard"
  echo "[3] Nginx"
  echo "[4] SSH"
  echo "[5] Set Domain"
  echo "[6] Cloudflare DDNS"
  echo "[7] Cek Port & IP NAT"
  echo "[8] Restart Services"
  echo "[9] System Info"
  echo "[0] Exit"
  echo "══════════════════════════════════════════════"
  read -rp "Pilih [0-9]: " n
  case "$n" in
    1) /opt/nat-vps-aio/install-xray.sh; pause;;
    2) /opt/nat-vps-aio/install-wireguard.sh; pause;;
    3) systemctl enable nginx --now; systemctl restart nginx; echo "Nginx aktif."; pause;;
    4) systemctl enable ssh --now; systemctl restart ssh; echo "SSH aktif."; pause;;
    5) read -rp "Domain/DDNS: " d; setcfg DOMAIN "$d"; source "$cfg"; echo "Domain disimpan."; pause;;
    6)
      read -rp "Cloudflare API Token: " t
      read -rp "Zone ID: " z
      read -rp "DNS Record ID: " r
      read -rp "Nama record (contoh vpn.example.com): " name
      setcfg DDNS_PROVIDER cloudflare
      setcfg CF_API_TOKEN "$t"
      setcfg CF_ZONE_ID "$z"
      setcfg CF_RECORD_ID "$r"
      setcfg CF_RECORD "$name"
      /opt/nat-vps-aio/ddns-update.sh || true
      (crontab -l 2>/dev/null | grep -v '/opt/nat-vps-aio/ddns-update.sh' || true; echo "*/5 * * * * /opt/nat-vps-aio/ddns-update.sh >/dev/null 2>&1") | crontab -
      echo "Cloudflare DDNS diatur setiap 5 menit."
      pause;;
    7)
      echo "Local addresses:"; ip -br addr
      echo
      echo "Public IPv4:"; curl -4fsS https://api.ipify.org || true; echo
      echo
      echo "NAT biasanya memerlukan port-forward dari provider."
      pause;;
    8)
      systemctl restart nginx 2>/dev/null || true
      systemctl restart xray 2>/dev/null || true
      systemctl restart wg-quick@wg0 2>/dev/null || true
      systemctl restart ssh 2>/dev/null || true
      echo "Service yang terpasang sudah direstart."; pause;;
    9) uname -a; echo; free -h; echo; df -h /; pause;;
    0) exit 0;;
    *) echo "Pilihan tidak valid."; sleep 1;;
  esac
done
EOF
chmod +x /opt/nat-vps-aio/menu.sh

cat >/usr/local/bin/nat-vps-aio <<'EOF'
#!/usr/bin/env bash
exec /opt/nat-vps-aio/menu.sh
EOF
chmod +x /usr/local/bin/nat-vps-aio

cat >/etc/systemd/system/nat-vps-ddns.service <<'EOF'
[Unit]
Description=NAT VPS DDNS update
After=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/nat-vps-aio/ddns-update.sh
EOF

cat >/etc/systemd/system/nat-vps-ddns.timer <<'EOF'
[Unit]
Description=Run NAT VPS DDNS updater periodically

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now nat-vps-ddns.timer

echo
echo "=============================================="
echo " NAT VPS AIO berhasil diinstall"
echo "=============================================="
echo "Jalankan panel:"
echo "  nat-vps-aio"
echo
echo "Catatan: NAT provider tetap harus menyediakan"
echo "port forwarding. Script ini tidak membypass NAT."
echo "=============================================="
