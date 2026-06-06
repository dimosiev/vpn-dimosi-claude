#!/usr/bin/env bash
#
# Рендер клиентского конфига sing-box (автопереключение Reality <-> Hysteria2)
# из сохранённого состояния. Результат -> ./out/client-singbox.json для импорта в Hiddify/sing-box.
#
# Использование:  sudo ./scripts/gen-singbox-client.sh
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

load_env
REPO="$(repo_root)"

UUID="$(read_state uuid)"
PUB="$(read_state reality_public)"
SHORT_ID="$(read_state short_id)"
HY2_AUTH="$(read_state hy2_auth)"
HY2_OBFS="$(read_state hy2_obfs)"
IP="$(public_ip)"
HOST="${DOMAIN:-$IP}"

[[ -n "$UUID" && -n "$PUB" && -n "$SHORT_ID" ]] || \
  die "Нет ключей Reality в ${STATE_DIR}. Сначала: ./scripts/02-install-xray.sh"

OUT_DIR="${REPO}/out"; install -d "${OUT_DIR}"
OUT="${OUT_DIR}/client-singbox.json"

render_template "${REPO}/configs/sing-box/client.template.json" \
  "__SERVER_IP__"             "${HOST}" \
  "__VLESS_PORT__"            "${VLESS_PORT}" \
  "__UUID__"                  "${UUID}" \
  "__REALITY_SNI__"           "${REALITY_SNI}" \
  "__REALITY_PUBLIC_KEY__"    "${PUB}" \
  "__SHORT_ID__"              "${SHORT_ID}" \
  "__HY2_PORT__"              "${HY2_PORT}" \
  "__HY2_AUTH_PASSWORD__"     "${HY2_AUTH:-CHANGEME}" \
  "__HY2_OBFS_PASSWORD__"     "${HY2_OBFS:-CHANGEME}" \
  > "${OUT}"

# Валидация, если установлен sing-box.
if command -v sing-box >/dev/null 2>&1; then
  sing-box check -c "${OUT}" && ok "Конфиг sing-box валиден." || warn "sing-box сообщил об ошибке в конфиге."
fi

chmod 600 "${OUT}"
ok "Клиентский конфиг: ${OUT}"
echo "Импортируйте его в Hiddify (Add profile from file) или запустите в sing-box."
echo "В нём собраны Reality + Hysteria2 с url-test автопереключением и обходом .ru напрямую."
