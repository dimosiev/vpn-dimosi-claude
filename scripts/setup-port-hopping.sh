#!/usr/bin/env bash
#
# Port hopping для Hysteria2 (Часть 3, Рецепт 9).
# Перенаправляет диапазон UDP-портов на основной порт сервиса через nftables.
# Правило ставится персистентно (systemd-сервис vpn-hopping).
#
# Использование:  sudo ./scripts/setup-port-hopping.sh
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_root
load_env
require_cmd nft

RANGE="${HY2_HOP_RANGE/:/-}"   # 20000:50000 -> 20000-50000
DEST="${HY2_PORT}"

log "Применяю nftables redirect: udp ${RANGE} → :${DEST}"
nft delete table inet vpnhop 2>/dev/null || true
nft add table inet vpnhop
nft add chain inet vpnhop prerouting "{ type nat hook prerouting priority -100 ; }"
nft add rule  inet vpnhop prerouting udp dport "${RANGE}" redirect to :"${DEST}"

# Персистентность через systemd (правило слетает после перезагрузки).
RULE_FILE="/etc/nftables-vpnhop.nft"
cat > "${RULE_FILE}" <<EOF
#!/usr/sbin/nft -f
table inet vpnhop
delete table inet vpnhop
table inet vpnhop {
  chain prerouting {
    type nat hook prerouting priority -100;
    udp dport ${RANGE} redirect to :${DEST}
  }
}
EOF

cat > /etc/systemd/system/vpn-hopping.service <<EOF
[Unit]
Description=Hysteria2 UDP port-hopping (nftables redirect)
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/nft -f ${RULE_FILE}
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now vpn-hopping.service
ok "Port hopping активен и переживёт перезагрузку."
