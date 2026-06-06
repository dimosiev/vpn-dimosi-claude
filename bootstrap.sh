#!/usr/bin/env bash
#
# bootstrap.sh — самодостаточный установщик «всё в одном».
# Разворачивает на ЧИСТОМ сервере: защита (UFW+fail2ban) + VLESS+Reality+Vision
# + Hysteria2 (Salamander + port hopping). Не требует git/репозитория/домена.
#
# Запуск на сервере (от root):   bash bootstrap.sh
#
# Параметры можно переопределить переменными окружения, напр.:
#   REALITY_SNI=www.apple.com bash bootstrap.sh
#
set -Eeuo pipefail

# ---------- Параметры (значения по умолчанию рабочие) ----------
REALITY_SNI="${REALITY_SNI:-www.microsoft.com}"
REALITY_DEST="${REALITY_DEST:-${REALITY_SNI}:443}"
VLESS_PORT="${VLESS_PORT:-443}"
HY2_PORT="${HY2_PORT:-443}"
HY2_HOP_RANGE="${HY2_HOP_RANGE:-20000:50000}"
SSH_PORT="${SSH_PORT:-22}"
ADMIN_USER="${ADMIN_USER:-myadmin}"
STATE_DIR="${STATE_DIR:-/etc/vpn-dimosi}"
XRAY_CONFIG="/usr/local/etc/xray/config.json"
HY2_CONFIG="/etc/hysteria/config.yaml"

C_G='\033[0;32m'; C_Y='\033[0;33m'; C_B='\033[0;34m'; C_R='\033[0;31m'; C_0='\033[0m'
log(){ echo -e "${C_B}[*]${C_0} $*"; }
ok(){ echo -e "${C_G}[✓]${C_0} $*"; }
warn(){ echo -e "${C_Y}[!]${C_0} $*" >&2; }
die(){ echo -e "${C_R}[✗]${C_0} $*" >&2; exit 1; }

[[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Запустите от root (sudo bash bootstrap.sh)."

save(){ install -d -m700 "$STATE_DIR"; printf '%s\n' "$2" >"$STATE_DIR/$1"; chmod 600 "$STATE_DIR/$1"; }
read_s(){ cat "$STATE_DIR/$1" 2>/dev/null || true; }

# ---------- 1. Система и базовые пакеты ----------
log "Обновляю систему и ставлю базовые пакеты…"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y
apt-get install -y ufw fail2ban curl wget openssl jq qrencode nftables ca-certificates

# ---------- 2. Отдельный sudo-пользователь ----------
if ! id "$ADMIN_USER" >/dev/null 2>&1; then
  log "Создаю sudo-пользователя $ADMIN_USER (задайте пароль позже: passwd $ADMIN_USER)…"
  adduser --disabled-password --gecos "" "$ADMIN_USER"
  usermod -aG sudo "$ADMIN_USER"
fi

# ---------- 3. Файрвол (SSH первым!) ----------
log "Настраиваю UFW…"
ufw --force reset >/dev/null
ufw default deny incoming >/dev/null
ufw default allow outgoing >/dev/null
ufw allow "${SSH_PORT}/tcp"      comment 'SSH'      >/dev/null
ufw allow "${VLESS_PORT}/tcp"    comment 'Reality'  >/dev/null
ufw allow "${HY2_PORT}/udp"      comment 'Hysteria2'>/dev/null
[[ -n "$HY2_HOP_RANGE" ]] && ufw allow "${HY2_HOP_RANGE}/udp" comment 'HY2 hopping' >/dev/null
ufw --force enable >/dev/null
systemctl enable --now fail2ban >/dev/null 2>&1 || true
ok "Файрвол включён, fail2ban запущен."

# ---------- 4. Xray-core ----------
if ! command -v xray >/dev/null 2>&1; then
  log "Ставлю Xray-core…"
  bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
fi
command -v xray >/dev/null 2>&1 || die "Xray не установился."
install -d -m755 /var/log/xray

# ---------- 5. Секреты Reality (генерим один раз) ----------
UUID="$(read_s uuid)";          [[ -n "$UUID" ]]     || { UUID="$(xray uuid)"; save uuid "$UUID"; }
SHORT_ID="$(read_s short_id)";  [[ -n "$SHORT_ID" ]] || { SHORT_ID="$(openssl rand -hex 8)"; save short_id "$SHORT_ID"; }
PRIV="$(read_s reality_private)"; PUB="$(read_s reality_public)"
if [[ -z "$PRIV" || -z "$PUB" ]]; then
  log "Генерирую пару ключей Reality…"
  KX="$(xray x25519)"
  PRIV="$(echo "$KX" | sed -n '1p' | awk '{print $NF}')"
  PUB="$(echo  "$KX" | sed -n '2p' | awk '{print $NF}')"
  save reality_private "$PRIV"; save reality_public "$PUB"
fi

# ---------- 6. Конфиг Xray ----------
log "Пишу конфиг Xray…"
install -d -m755 "$(dirname "$XRAY_CONFIG")"
cat > "$XRAY_CONFIG" <<JSON
{
  "log": { "loglevel": "warning", "access": "/var/log/xray/access.log", "error": "/var/log/xray/error.log" },
  "inbounds": [{
    "tag": "vless-reality-vision", "listen": "0.0.0.0", "port": ${VLESS_PORT}, "protocol": "vless",
    "settings": { "clients": [{ "id": "${UUID}", "flow": "xtls-rprx-vision", "email": "user1@vpn-dimosi" }], "decryption": "none" },
    "streamSettings": { "network": "tcp", "security": "reality",
      "realitySettings": { "show": false, "dest": "${REALITY_DEST}", "xver": 0,
        "serverNames": ["${REALITY_SNI}"], "privateKey": "${PRIV}", "shortIds": ["${SHORT_ID}"] } },
    "sniffing": { "enabled": true, "destOverride": ["http","tls","quic"], "routeOnly": true }
  }],
  "outbounds": [ { "tag": "direct", "protocol": "freedom" }, { "tag": "block", "protocol": "blackhole" } ],
  "routing": { "domainStrategy": "IPIfNonMatch", "rules": [
    { "type": "field", "ip": ["geoip:private"], "outboundTag": "block" },
    { "type": "field", "protocol": ["bittorrent"], "outboundTag": "block" } ] }
}
JSON

xray run -test -config "$XRAY_CONFIG" >/dev/null || die "Конфиг Xray невалиден."
systemctl enable xray >/dev/null 2>&1 || true
systemctl restart xray
sleep 1
systemctl is-active --quiet xray && ok "Xray запущен на :${VLESS_PORT}." || { journalctl -u xray -n 20 --no-pager; die "Xray не стартовал."; }

# ---------- 7. Hysteria2 ----------
if ! command -v hysteria >/dev/null 2>&1; then
  log "Ставлю Hysteria2…"
  bash <(curl -fsSL https://get.hy2.sh/) || warn "Установщик Hysteria2 вернул ошибку — пропускаю."
fi

if command -v hysteria >/dev/null 2>&1; then
  OBFS="$(read_s hy2_obfs)"; [[ -n "$OBFS" ]] || { OBFS="$(openssl rand -base64 24 | tr -d '/+=' | head -c32)"; save hy2_obfs "$OBFS"; }
  AUTH="$(read_s hy2_auth)"; [[ -n "$AUTH" ]] || { AUTH="$(openssl rand -base64 24 | tr -d '/+=' | head -c32)"; save hy2_auth "$AUTH"; }
  install -d -m700 /etc/hysteria
  if [[ ! -f /etc/hysteria/server.key ]]; then
    openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
      -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt \
      -subj "/CN=${REALITY_SNI}" -days 3650 >/dev/null 2>&1
  fi
  cat > "$HY2_CONFIG" <<YAML
listen: :${HY2_PORT}
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
obfs:
  type: salamander
  salamander:
    password: ${OBFS}
auth:
  type: password
  password: ${AUTH}
bandwidth:
  up: 100 mbps
  down: 100 mbps
masquerade:
  type: proxy
  proxy:
    url: https://${REALITY_SNI}/
    rewriteHost: true
YAML
  chmod 600 "$HY2_CONFIG"

  # Port hopping через nftables (персистентно).
  if [[ -n "$HY2_HOP_RANGE" ]]; then
    RANGE="${HY2_HOP_RANGE/:/-}"
    cat > /etc/nftables-vpnhop.nft <<NFT
#!/usr/sbin/nft -f
table inet vpnhop
delete table inet vpnhop
table inet vpnhop {
  chain prerouting {
    type nat hook prerouting priority -100;
    udp dport ${RANGE} redirect to :${HY2_PORT}
  }
}
NFT
    cat > /etc/systemd/system/vpn-hopping.service <<UNIT
[Unit]
Description=Hysteria2 UDP port-hopping
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/sbin/nft -f /etc/nftables-vpnhop.nft
RemainAfterExit=yes
[Install]
WantedBy=multi-user.target
UNIT
    systemctl daemon-reload
    systemctl enable --now vpn-hopping.service >/dev/null 2>&1 || warn "Не удалось включить port hopping."
  fi

  systemctl enable hysteria-server.service >/dev/null 2>&1 || true
  systemctl restart hysteria-server.service
  sleep 1
  systemctl is-active --quiet hysteria-server.service && ok "Hysteria2 запущена на :${HY2_PORT}/udp." || warn "Hysteria2 не стартовала (не критично, Reality работает)."
fi

# ---------- 8. Бэкап секретов ----------
install -d -m700 /root/vpn-backups
tar -czf "/root/vpn-backups/vpn-backup-$(date +%Y%m%d-%H%M%S).tar.gz" -C / "etc/vpn-dimosi" 2>/dev/null || true

# ---------- 9. Ссылки для клиента ----------
IP="$(curl -fsS4 --max-time 5 https://api.ipify.org 2>/dev/null || curl -fsS4 --max-time 5 https://ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')"
VLESS_LINK="vless://${UUID}@${IP}:${VLESS_PORT}?type=tcp&security=reality&encryption=none&pbk=${PUB}&fp=chrome&sni=${REALITY_SNI}&sid=${SHORT_ID}&flow=xtls-rprx-vision#dimosi-reality"
save link-reality.txt "$VLESS_LINK"

echo
echo "============================================================"
ok "ГОТОВО. Инфраструктура развёрнута."
echo "============================================================"
echo
echo "Публичный IP: ${IP}"
echo
echo "── Параметры VLESS+Reality (для ручного ввода) ──"
printf '  %-12s %s\n' Address "$IP"
printf '  %-12s %s\n' Port "$VLESS_PORT"
printf '  %-12s %s\n' UUID "$UUID"
printf '  %-12s %s\n' Flow "xtls-rprx-vision"
printf '  %-12s %s\n' PublicKey "$PUB"
printf '  %-12s %s\n' ShortID "$SHORT_ID"
printf '  %-12s %s\n' SNI "$REALITY_SNI"
printf '  %-12s %s\n' Fingerprint chrome
echo
echo "── Ссылка VLESS (импортируй в v2RayTun/Hiddify) ──"
echo "$VLESS_LINK"
echo
command -v qrencode >/dev/null 2>&1 && { echo "── QR-код (наведи камеру приложения) ──"; qrencode -t ANSIUTF8 "$VLESS_LINK"; }

if command -v hysteria >/dev/null 2>&1 && [[ -n "${AUTH:-}" ]]; then
  HOP=""; [[ -n "$HY2_HOP_RANGE" ]] && HOP=",${HY2_HOP_RANGE/:/-}"
  HY_LINK="hysteria2://${AUTH}@${IP}:${HY2_PORT}${HOP}/?obfs=salamander&obfs-password=${OBFS}&sni=${REALITY_SNI}&insecure=1#dimosi-hy2"
  save link-hysteria2.txt "$HY_LINK"
  echo; echo "── Ссылка Hysteria2 (резервный быстрый канал) ──"; echo "$HY_LINK"
fi

echo
warn "ВАЖНО: смени пароль root прямо сейчас — командой:  passwd"
echo "Секреты сохранены в ${STATE_DIR} (chmod 600), бэкап — в /root/vpn-backups/."
