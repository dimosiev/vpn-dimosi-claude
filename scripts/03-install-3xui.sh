#!/usr/bin/env bash
#
# Опционально. Веб-панель 3X-UI для управления Xray мышкой (Часть 1, §8–9).
# Альтернатива чистому Xray (02-install-xray.sh). Удобна для нескольких пользователей,
# статистики трафика, лимитов и подписок через GUI.
#
# ВНИМАНИЕ: не запускайте вместе с 02-install-xray.sh на одном порту 443 —
# конфликт за порт. Выберите ОДИН способ управления Xray:
#   - чистый Xray (IaC, воспроизводимо)  → 02-install-xray.sh
#   - панель 3X-UI (GUI)                  → этот скрипт
#
# Использование:  sudo ./scripts/03-install-3xui.sh
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_root
detect_os
load_env

if systemctl is-active --quiet xray 2>/dev/null; then
  warn "Обнаружен запущенный чистый Xray (02-install-xray.sh)."
  warn "3X-UI поднимет свой Xray и будет конфликтовать за порт ${VLESS_PORT}."
  read -r -p "Остановить и отключить чистый Xray перед установкой панели? [y/N] " ans
  if [[ "${ans,,}" == "y" ]]; then
    systemctl disable --now xray
    ok "Чистый Xray остановлен."
  else
    die "Отменено. Выберите один способ управления Xray."
  fi
fi

log "Устанавливаю 3X-UI (официальный скрипт MHSanaei)…"
echo
warn "В процессе установки ОБЯЗАТЕЛЬНО:"
warn "  • задайте свой логин/пароль (не оставляйте admin/admin)"
warn "  • задайте нестандартный порт панели (например ${PANEL_PORT})"
warn "  • задайте секретный web base path (например /$(openssl rand -hex 4)/)"
echo
bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh)

echo
ok "3X-UI установлена."
cat <<EOF

Следующие шаги (GUI):
1. Откройте панель ТОЛЬКО через SSH-туннель (безопасно):
     ssh -L ${PANEL_PORT}:localhost:<ПОРТ_ПАНЕЛИ> ${ADMIN_USER}@$(public_ip)
   затем в браузере: http://localhost:${PANEL_PORT}/<ВАШ_ПУТЬ>
   После этого порт панели можно закрыть в UFW наружу:  ufw delete allow ${PANEL_PORT}/tcp

2. Panel Settings → включите 2FA, проверьте секретный web base path.

3. Inbounds → Add Inbound с параметрами максимальной устойчивости:
     Protocol=vless  Port=443  Security=reality
     Flow=xtls-rprx-vision  Fingerprint=chrome
     Dest=${REALITY_DEST}  SNI=${REALITY_SNI}
     -> сгенерируйте Reality keys и Short ID кнопками, Save → Restart Xray.

4. У клиента нажмите QR/Copy — получите vless:// ссылку.

Подробности и защита панели: docs/02-server-hardening.md, docs/03-vless-reality.md
EOF
