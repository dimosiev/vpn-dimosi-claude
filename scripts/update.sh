#!/usr/bin/env bash
#
# Обновление ВСЕЙ инфраструктуры до самых свежих версий — одной командой.
# Порядок: бэкап -> обновление кода (git) -> Xray-core + geodata -> Hysteria2
#          -> проверка конфигов -> перезапуск -> отчёт версий «было -> стало».
#
# Использование:
#   sudo ./scripts/update.sh           # обновить всё
#   sudo ./scripts/update.sh check     # только показать: что стоит и что вышло (без изменений)
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
load_env
REPO="$(repo_root)"

XRAY_INSTALLER='https://github.com/XTLS/Xray-install/raw/main/install-release.sh'
HY2_INSTALLER='https://get.hy2.sh/'

# Текущая установленная версия.
xray_ver()  { command -v xray     >/dev/null 2>&1 && xray version 2>/dev/null | head -1 | awk '{print $2}' || echo "—"; }
hy2_ver()   { command -v hysteria >/dev/null 2>&1 && hysteria version 2>/dev/null | awk '/^Version/{print $2}' | head -1 || echo "—"; }

# Последняя доступная версия (через редирект страницы релизов; нужен только curl).
latest_ver() {
  curl -fsSI "https://github.com/$1/releases/latest" 2>/dev/null \
    | grep -i '^location:' | tr -d '\r' | awk -F/ '{print $NF}'
}

show_versions() {
  echo
  echo -e "${C_BOLD}Компонент      Установлено      Доступно (последняя)${C_RESET}"
  printf "Xray-core      %-16s %s\n" "$(xray_ver)" "$(latest_ver XTLS/Xray-core)"
  printf "Hysteria2      %-16s %s\n" "$(hy2_ver)"  "$(latest_ver apernet/hysteria)"
  echo
}

# ---------- Режим «только проверить» ----------
if [[ "${1:-}" == "check" ]]; then
  log "Проверяю версии (ничего не меняю)…"
  show_versions
  echo "Чтобы обновить — запусти: sudo ./deploy.sh update"
  exit 0
fi

require_root
log "Версии ДО обновления:"
show_versions

# ---------- 0. Бэкап перед обновлением ----------
log "Шаг 0/4: делаю бэкап на случай отката…"
bash "${SCRIPT_DIR}/backup.sh" >/dev/null 2>&1 && ok "Бэкап создан (/root/vpn-backups/)." || warn "Бэкап не удался — продолжаю."

# ---------- 1. Обновление самого репозитория ----------
log "Шаг 1/4: обновляю код инфраструктуры (git pull)…"
if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  if git -C "$REPO" pull --ff-only 2>&1 | sed 's/^/  /'; then
    ok "Код обновлён."
  else
    warn "git pull не прошёл (репозиторий приватный без доступа, или есть локальные правки)."
    warn "Это не мешает обновить сами протоколы ниже."
  fi
else
  warn "Каталог не является git-репозиторием — пропускаю обновление кода."
fi

# ---------- 2. Xray-core + geodata ----------
if command -v xray >/dev/null 2>&1; then
  log "Шаг 2/4: обновляю Xray-core до последней стабильной…"
  bash -c "$(curl -fsSL "$XRAY_INSTALLER")" @ install || warn "Обновление Xray-core завершилось с ошибкой."
  log "         обновляю geodata (geoip/geosite — списки маршрутизации)…"
  bash -c "$(curl -fsSL "$XRAY_INSTALLER")" @ install-geodata || warn "geodata обновить не удалось."
  if xray run -test -config "${XRAY_CONFIG}" >/dev/null 2>&1; then
    systemctl restart xray && ok "Xray перезапущен, конфиг валиден."
  else
    err "Конфиг Xray не прошёл проверку после обновления! Сервис НЕ перезапущен."
    warn "Проверь: xray run -test -config ${XRAY_CONFIG}  (или восстановись из бэкапа)."
  fi
else
  warn "Xray не установлен — пропускаю."
fi

# ---------- 3. Hysteria2 ----------
if command -v hysteria >/dev/null 2>&1; then
  log "Шаг 3/4: обновляю Hysteria2 до последней…"
  bash <(curl -fsSL "$HY2_INSTALLER") || warn "Обновление Hysteria2 завершилось с ошибкой."
  # Переустановка могла сбросить права — возвращаем доступ сервисному пользователю.
  if id hysteria >/dev/null 2>&1; then
    chown -R hysteria /etc/hysteria 2>/dev/null || true
    chmod 750 /etc/hysteria 2>/dev/null || true
    chmod 640 /etc/hysteria/config.yaml /etc/hysteria/server.crt /etc/hysteria/server.key 2>/dev/null || true
  fi
  systemctl restart hysteria-server 2>/dev/null && ok "Hysteria2 перезапущен." || warn "Hysteria2 не перезапустился (проверь логи)."
else
  warn "Hysteria2 не установлен — пропускаю."
fi

# ---------- 4. Итог ----------
log "Шаг 4/4: готово. Версии ПОСЛЕ обновления:"
show_versions
ok "Обновление завершено. Если что-то сломалось — восстановись из бэкапа (docs/05-backup-restore.md)."
tg_notify "🔄 VPN обновлён на $(public_ip): Xray $(xray_ver), Hysteria2 $(hy2_ver)."
