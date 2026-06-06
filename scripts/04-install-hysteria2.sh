#!/usr/bin/env bash
#
# Шаг 3 (резерв). Hysteria2 — UDP/QUIC + Salamander + port hopping (Часть 3, Рецепт 4).
# UDP-протокол ломается иначе, чем TCP-Reality → держим оба для «обороны глубиной».
#
# Использование:  sudo ./scripts/04-install-hysteria2.sh
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_root
detect_os
load_env
REPO="$(repo_root)"

# ---------- Установка ----------
if command -v hysteria >/dev/null 2>&1; then
  ok "Hysteria уже установлена: $(hysteria version 2>/dev/null | head -n1)"
else
  log "Ставлю Hysteria2 (официальный установщик)…"
  bash <(curl -fsSL https://get.hy2.sh/)
fi

# ---------- Секреты ----------
OBFS_PW="$(read_state hy2_obfs)";  [[ -n "$OBFS_PW" ]] || { OBFS_PW="$(gen_password)"; save_state hy2_obfs "$OBFS_PW"; }
AUTH_PW="$(read_state hy2_auth)";  [[ -n "$AUTH_PW" ]] || { AUTH_PW="$(gen_password)"; save_state hy2_auth "$AUTH_PW"; }

# ---------- TLS-блоки в зависимости от наличия домена ----------
if [[ -n "${DOMAIN}" ]]; then
  ACME_BLOCK=$(printf 'acme:\n  domains:\n    - %s\n  email: admin@%s' "${DOMAIN}" "${DOMAIN}")
  TLS_BLOCK="# (используется ACME выше)"
else
  warn "DOMAIN не задан — генерирую самоподписанный сертификат для Hysteria2."
  install -d -m 700 /etc/hysteria
  if [[ ! -f /etc/hysteria/server.key ]]; then
    openssl req -x509 -nodes -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
      -keyout /etc/hysteria/server.key -out /etc/hysteria/server.crt \
      -subj "/CN=${REALITY_SNI}" -days 3650 >/dev/null 2>&1
  fi
  ACME_BLOCK="# (домен не задан — используется самоподписанный сертификат ниже)"
  TLS_BLOCK=$(printf 'tls:\n  cert: /etc/hysteria/server.crt\n  key: /etc/hysteria/server.key')
fi

# ---------- Рендер конфига ----------
log "Рендерю конфиг Hysteria2 → ${HY2_CONFIG}"
install -d -m 700 "$(dirname "${HY2_CONFIG}")"
render_template "${REPO}/configs/hysteria2/config.yaml.template" \
  "__HY2_PORT__"       "${HY2_PORT}" \
  "__ACME_BLOCK__"     "${ACME_BLOCK}" \
  "__TLS_BLOCK__"      "${TLS_BLOCK}" \
  "__OBFS_PASSWORD__"  "${OBFS_PW}" \
  "__AUTH_PASSWORD__"  "${AUTH_PW}" \
  "__REALITY_SNI__"    "${REALITY_SNI}" \
  > "${HY2_CONFIG}"
chmod 600 "${HY2_CONFIG}"

# ---------- Port hopping (nftables redirect диапазона UDP на основной порт) ----------
if [[ -n "${HY2_HOP_RANGE}" ]]; then
  log "Настраиваю port hopping (${HY2_HOP_RANGE}/udp → ${HY2_PORT})…"
  "${SCRIPT_DIR}/setup-port-hopping.sh" || warn "Не удалось настроить port hopping (не критично)."
fi

# ---------- Запуск ----------
systemctl enable --now hysteria-server.service
systemctl restart hysteria-server.service
sleep 1
if systemctl is-active --quiet hysteria-server.service; then
  ok "Hysteria2 запущена на :${HY2_PORT}/udp."
else
  err "Hysteria2 не запустилась. Логи:"; journalctl -u hysteria-server -n 30 --no-pager; exit 1
fi

# ---------- Клиентская ссылка ----------
IP="$(public_ip)"; HOST="${DOMAIN:-$IP}"
INSECURE=""; [[ -z "${DOMAIN}" ]] && INSECURE="&insecure=1"
HOP=""; [[ -n "${HY2_HOP_RANGE}" ]] && HOP=",${HY2_HOP_RANGE/:/-}"
HY_LINK="hysteria2://${AUTH_PW}@${HOST}:${HY2_PORT}${HOP}/?obfs=salamander&obfs-password=${OBFS_PW}&sni=${REALITY_SNI}${INSECURE}#dimosi-hy2"

echo
echo -e "${C_BOLD}=== Hysteria2 ссылка ===${C_RESET}"
echo "${HY_LINK}"
save_state "link-hysteria2.txt" "${HY_LINK}"
command -v qrencode >/dev/null 2>&1 && qrencode -t ANSIUTF8 "${HY_LINK}"
echo
ok "Hysteria2 развёрнута. UFW: ${HY2_PORT}/udp + ${HY2_HOP_RANGE}/udp должны быть открыты."
