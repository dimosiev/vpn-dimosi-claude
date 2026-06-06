#!/usr/bin/env bash
#
# Шаг 2. Установка Xray-core и генерация рабочего VLESS + Reality + Vision (Часть 1, §11).
# Полностью автоматический, воспроизводимый деплой без панели:
#   - ставит свежий Xray-core официальным скриптом
#   - генерирует UUID, пару ключей Reality (x25519), Short ID
#   - рендерит /usr/local/etc/xray/config.json из шаблона
#   - сохраняет секреты в STATE_DIR (chmod 600)
#   - печатает готовую vless:// ссылку и QR
#
# Использование:  sudo ./scripts/02-install-xray.sh
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_root
detect_os
load_env
REPO="$(repo_root)"

# ---------- Установка Xray-core ----------
if command -v xray >/dev/null 2>&1; then
  ok "Xray уже установлен: $(xray version | head -n1)"
else
  log "Ставлю Xray-core (официальный установщик XTLS)…"
  bash -c "$(curl -fsSL https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
fi
require_cmd xray
install -d -m 755 /var/log/xray

# ---------- Генерация секретов (один раз; повторный запуск переиспользует) ----------
UUID="$(read_state uuid)";              [[ -n "$UUID" ]]       || { UUID="$(gen_uuid)"; save_state uuid "$UUID"; }
SHORT_ID="$(read_state short_id)";      [[ -n "$SHORT_ID" ]]   || { SHORT_ID="$(gen_short_id)"; save_state short_id "$SHORT_ID"; }
PRIV="$(read_state reality_private)"
PUB="$(read_state reality_public)"
if [[ -z "$PRIV" || -z "$PUB" ]]; then
  log "Генерирую пару ключей Reality…"
  keys="$(gen_reality_keys)"
  PRIV="$(echo "$keys" | sed -n 1p)"
  PUB="$(echo "$keys" | sed -n 2p)"
  save_state reality_private "$PRIV"
  save_state reality_public  "$PUB"
fi

CLIENT_EMAIL="user1@vpn-dimosi"

# ---------- Рендер конфига ----------
log "Рендерю конфиг Xray → ${XRAY_CONFIG}"
install -d -m 755 "$(dirname "${XRAY_CONFIG}")"
render_template "${REPO}/configs/xray/config.template.json" \
  "__VLESS_PORT__"            "${VLESS_PORT}" \
  "__UUID__"                  "${UUID}" \
  "__CLIENT_EMAIL__"          "${CLIENT_EMAIL}" \
  "__REALITY_DEST__"          "${REALITY_DEST}" \
  "__REALITY_SNI__"           "${REALITY_SNI}" \
  "__REALITY_PRIVATE_KEY__"   "${PRIV}" \
  "__SHORT_ID__"              "${SHORT_ID}" \
  > "${XRAY_CONFIG}"

# ---------- Валидация и запуск ----------
log "Проверяю конфиг (xray run -test)…"
xray run -test -config "${XRAY_CONFIG}" >/dev/null || die "Конфиг невалиден. Проверьте ${XRAY_CONFIG}"
ok "Конфиг валиден."

systemctl enable --now xray
systemctl restart xray
sleep 1
if systemctl is-active --quiet xray; then
  ok "Xray запущен и слушает порт ${VLESS_PORT}."
else
  err "Xray не запустился. Логи:"; journalctl -u xray -n 30 --no-pager; exit 1
fi

# Проверка, что порт реально слушается.
if ss -tlnp 2>/dev/null | grep -q ":${VLESS_PORT}\b"; then
  ok "Порт ${VLESS_PORT}/tcp слушается процессом xray."
else
  warn "Порт ${VLESS_PORT} не обнаружен в ss — проверьте firewall и логи."
fi

# ---------- Готовая ссылка для клиента ----------
echo
log "Генерирую клиентскую ссылку…"
"${SCRIPT_DIR}/gen-client-link.sh" || true

echo
ok "VLESS + Reality + Vision развёрнут."
echo "Секреты сохранены в ${STATE_DIR} (chmod 600). Сделайте бэкап: ./scripts/backup.sh"
