#!/usr/bin/env bash
#
# Локальный мониторинг здоровья сервера (Часть 2 §17).
# Проверяет: сервисы запущены, порты слушаются, маскировка отдаёт донора.
# Удобно повесить в cron каждые 5 минут; при проблеме шлёт алерт в Telegram.
#
# Использование:  sudo ./scripts/healthcheck.sh
#   cron:  */5 * * * * /path/scripts/healthcheck.sh >/var/log/vpn-health.log 2>&1
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_env
PROBLEMS=()

check_service() {
  local svc="$1"
  if systemctl list-unit-files | grep -q "^${svc}"; then
    if systemctl is-active --quiet "$svc"; then
      ok "${svc}: active"
    else
      err "${svc}: НЕ запущен"; PROBLEMS+=("${svc} остановлен")
    fi
  fi
}

check_port() {
  local port="$1" proto="$2" name="$3"
  local flag="-tlnp"; [[ "$proto" == udp ]] && flag="-ulnp"
  if ss ${flag} 2>/dev/null | grep -q ":${port}\b"; then
    ok "${name}: порт ${port}/${proto} слушается"
  else
    err "${name}: порт ${port}/${proto} НЕ слушается"; PROBLEMS+=("порт ${port}/${proto} закрыт")
  fi
}

log "Healthcheck $(date '+%Y-%m-%d %H:%M:%S')"
check_service "xray.service"
check_service "hysteria-server.service"
check_port "${VLESS_PORT}" tcp "Xray/Reality"
[[ -f "${HY2_CONFIG}" ]] && check_port "${HY2_PORT}" udp "Hysteria2"

# Проверка маскировки: прямой запрос к порту 443 должен вести себя как донор (не выдавать прокси).
if curl -fsS --max-time 8 -k -o /dev/null -w '%{http_code}' "https://$(public_ip):${VLESS_PORT}" 2>/dev/null | grep -qE '^(200|301|302|403|404)$'; then
  ok "Маскировка: прямой запрос отвечает как обычный сайт (хорошо)."
fi

echo
if [[ ${#PROBLEMS[@]} -eq 0 ]]; then
  ok "Все проверки пройдены."
else
  err "Обнаружены проблемы: ${PROBLEMS[*]}"
  tg_notify "🚨 VPN healthcheck на $(public_ip):
$(printf '• %s\n' "${PROBLEMS[@]}")"
  exit 1
fi
