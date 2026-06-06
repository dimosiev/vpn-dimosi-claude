#!/usr/bin/env bash
#
# Проверка доступности сервера из России (Часть 1 §5, Часть 2 §17).
# Использует публичные сервисы проверки доступности с российских узлов.
# «IP жив из РФ» — ключевой индикатор: если нет, значит IP заблокирован -> меняем IP/схему.
#
# Использование:  ./scripts/check-ip-russia.sh [IP|домен]
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_env
TARGET="${1:-${DOMAIN:-$(public_ip)}}"
[[ -n "$TARGET" ]] || die "Не удалось определить цель. Укажите IP/домен аргументом."

log "Проверяю доступность ${TARGET} из России…"
echo

# check-host.net — есть российские узлы (msk/spb). Возвращает request_id, по нему берём результат.
API="https://check-host.net/check-tcp?host=${TARGET}:${VLESS_PORT}&node=ru1.node.check-host.net&node=ru2.node.check-host.net&node=ru3.node.check-host.net"
RID="$(curl -fsS -H 'Accept: application/json' "${API}" 2>/dev/null | jq -r '.request_id // empty')"

if [[ -z "$RID" ]]; then
  warn "Не удалось обратиться к check-host.net (или нет jq). Альтернатива:"
  echo "  • Откройте вручную: https://check-host.net/check-tcp?host=${TARGET}:${VLESS_PORT}"
  echo "  • Или попросите знакомого в РФ открыть https://${TARGET} / пингануть ${TARGET}"
  exit 0
fi

sleep 6   # узлам нужно время на проверку
RESULT="$(curl -fsS -H 'Accept: application/json' "https://check-host.net/check-result/${RID}" 2>/dev/null)"

echo -e "${C_BOLD}Результат TCP-проверки порта ${VLESS_PORT} с российских узлов:${C_RESET}"
ALIVE=0; DEAD=0
while IFS= read -r node; do
  val="$(echo "$RESULT" | jq -r --arg n "$node" '.[$n][0]')"
  if echo "$val" | jq -e '.time' >/dev/null 2>&1; then
    t="$(echo "$val" | jq -r '.time')"
    echo -e "  ${C_GRN}✓${C_RESET} ${node}: доступен (${t}s)"; ((ALIVE++)) || true
  else
    echo -e "  ${C_RED}✗${C_RESET} ${node}: недоступен"; ((DEAD++)) || true
  fi
done < <(echo "$RESULT" | jq -r 'keys[]')

echo
if [[ "$ALIVE" -gt 0 ]]; then
  ok "Сервер доступен из РФ (${ALIVE} узл(ов)). IP, скорее всего, жив."
else
  err "Сервер НЕ доступен из РФ. Вероятна блокировка IP → см. docs/07-when-blocked.md"
  tg_notify "⚠️ VPN: ${TARGET}:${VLESS_PORT} недоступен из РФ. Возможна блокировка IP."
  exit 2
fi
