#!/usr/bin/env bash
#
# Генерация vless:// ссылки и QR-кода из сохранённого состояния (STATE_DIR).
# Эти же данные нужны для импорта в v2RayTun / Hiddify / v2rayN.
#
# Использование:  sudo ./scripts/gen-client-link.sh [имя_профиля]
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_env
PROFILE_NAME="${1:-dimosi-reality}"

UUID="$(read_state uuid)"
PUB="$(read_state reality_public)"
SHORT_ID="$(read_state short_id)"
[[ -n "$UUID" && -n "$PUB" && -n "$SHORT_ID" ]] || \
  die "Нет сохранённых ключей в ${STATE_DIR}. Сначала запустите ./scripts/02-install-xray.sh"

IP="$(public_ip)"
[[ -n "$IP" ]] || die "Не удалось определить публичный IP."

# Адрес для подключения: домен, если задан, иначе IP.
HOST="${DOMAIN:-$IP}"

LINK="vless://${UUID}@${HOST}:${VLESS_PORT}"
LINK+="?type=tcp&security=reality&encryption=none"
LINK+="&pbk=${PUB}&fp=chrome&sni=${REALITY_SNI}&sid=${SHORT_ID}"
LINK+="&flow=xtls-rprx-vision"
LINK+="#${PROFILE_NAME}"

echo
echo -e "${C_BOLD}=== Параметры подключения (сверяйте 1:1 на клиенте) ===${C_RESET}"
printf '  %-14s %s\n' "Address"     "${HOST}"
printf '  %-14s %s\n' "Port"        "${VLESS_PORT}"
printf '  %-14s %s\n' "UUID"        "${UUID}"
printf '  %-14s %s\n' "Flow"        "xtls-rprx-vision"
printf '  %-14s %s\n' "Public Key"  "${PUB}"
printf '  %-14s %s\n' "Short ID"    "${SHORT_ID}"
printf '  %-14s %s\n' "SNI"         "${REALITY_SNI}"
printf '  %-14s %s\n' "Fingerprint" "chrome"
echo
echo -e "${C_BOLD}=== vless:// ссылка ===${C_RESET}"
echo "${LINK}"
echo

# QR-код в терминал, если есть qrencode.
if command -v qrencode >/dev/null 2>&1; then
  echo -e "${C_BOLD}=== QR (наведите камеру приложения) ===${C_RESET}"
  qrencode -t ANSIUTF8 "${LINK}"
else
  warn "qrencode не установлен — QR в терминале недоступен (apt install -y qrencode)."
fi

# Сохраняем ссылку в STATE_DIR для бэкапа/«тревожного чемоданчика».
save_state "link-${PROFILE_NAME}.txt" "${LINK}"
ok "Ссылка сохранена: ${STATE_DIR}/link-${PROFILE_NAME}.txt"
