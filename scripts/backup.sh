#!/usr/bin/env bash
#
# Бэкап «тревожного чемоданчика» (Часть 1 §14.5, Часть 2 §16).
# Складывает в один зашифрованный/обычный архив:
#   - секреты Reality/Hysteria2 (STATE_DIR)
#   - конфиги Xray и Hysteria2
#   - все клиентские ссылки
#   - базу 3X-UI (если установлена)
# Опционально отправляет архив в Telegram-бота.
#
# Использование:  sudo ./scripts/backup.sh [/путь/к/каталогу]
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_root
load_env

OUT_DIR="${1:-/root/vpn-backups}"
install -d -m 700 "${OUT_DIR}"
STAMP="$(date +%Y%m%d-%H%M%S)"
WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

log "Собираю бэкап…"
install -d "${WORK}/state" "${WORK}/configs"

# Секреты и ссылки.
[[ -d "${STATE_DIR}" ]] && cp -a "${STATE_DIR}/." "${WORK}/state/" 2>/dev/null || true
# Конфиги.
[[ -f "${XRAY_CONFIG}" ]] && cp -a "${XRAY_CONFIG}" "${WORK}/configs/xray-config.json" 2>/dev/null || true
[[ -f "${HY2_CONFIG}"  ]] && cp -a "${HY2_CONFIG}"  "${WORK}/configs/hysteria2.yaml"   2>/dev/null || true
# База 3X-UI (если есть).
for db in /etc/x-ui/x-ui.db /usr/local/x-ui/bin/x-ui.db; do
  [[ -f "$db" ]] && cp -a "$db" "${WORK}/configs/x-ui.db" 2>/dev/null || true
done

# Краткое README восстановления внутри архива.
cat > "${WORK}/RESTORE.txt" <<EOF
Бэкап инфраструктуры VPN от ${STAMP}.

Восстановление на новом сервере за ~15 минут:
1. Поставьте чистую Ubuntu 22.04/24.04 или Debian 12.
2. Клонируйте репозиторий vpn-dimosi-claude.
3. Скопируйте каталог state/ обратно в ${STATE_DIR} (chmod 600).
4. Запустите: sudo ./deploy.sh all
   Скрипты переиспользуют сохранённые ключи (UUID/Reality/Hysteria2) ->
   старые vless:// ссылки продолжат работать на новом IP (поменяется только адрес).
5. Перевыпустите ссылки под новый IP: sudo ./scripts/gen-client-link.sh

Файлы:
- state/        : UUID, ключи Reality, пароли Hysteria2, готовые ссылки
- configs/      : рабочие конфиги Xray/Hysteria2 и база 3X-UI
EOF

ARCHIVE="${OUT_DIR}/vpn-backup-${STAMP}.tar.gz"
tar -czf "${ARCHIVE}" -C "${WORK}" .
chmod 600 "${ARCHIVE}"
ok "Бэкап создан: ${ARCHIVE}"

# Отправка в Telegram, если настроено.
if [[ -n "${TG_BOT_TOKEN}" && -n "${TG_CHAT_ID}" ]]; then
  log "Отправляю бэкап в Telegram…"
  if curl -fsS --max-time 60 \
      "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendDocument" \
      -F chat_id="${TG_CHAT_ID}" \
      -F caption="🔐 VPN backup ${STAMP} ($(public_ip))" \
      -F document=@"${ARCHIVE}" >/dev/null; then
    ok "Бэкап отправлен в Telegram."
  else
    warn "Не удалось отправить бэкап в Telegram."
  fi
fi

# Ротация: оставляем последние 10.
ls -1t "${OUT_DIR}"/vpn-backup-*.tar.gz 2>/dev/null | tail -n +11 | xargs -r rm -f
ok "Готово. Сохраните копию ОФФЛАЙН (флешка/менеджер паролей) — это часть «тревожного чемоданчика»."
