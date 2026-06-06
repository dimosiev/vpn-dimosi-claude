#!/usr/bin/env bash
#
# Главный оркестратор инфраструктуры VLESS+Reality для РФ.
# Запускает шаги развёртывания в правильном порядке.
#
# Использование:
#   sudo ./deploy.sh all          # полный «боевой комплект»: harden + Xray/Reality + Hysteria2 + бэкап
#   sudo ./deploy.sh harden       # только базовая защита сервера
#   sudo ./deploy.sh reality      # только VLESS + Reality + Vision (Xray-core)
#   sudo ./deploy.sh hysteria2    # только Hysteria2 (UDP-резерв + port hopping)
#   sudo ./deploy.sh panel        # установить веб-панель 3X-UI (GUI-управление)
#   sudo ./deploy.sh backup       # собрать «тревожный чемоданчик»
#   sudo ./deploy.sh status       # показать статус и клиентские ссылки
#   sudo ./deploy.sh check        # проверить доступность IP из РФ
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
S="${SCRIPT_DIR}/scripts"
# shellcheck source=scripts/lib/common.sh
source "${S}/lib/common.sh"
load_env

banner() {
  echo -e "${C_BOLD}"
  echo "  ┌─────────────────────────────────────────────┐"
  echo "  │   VLESS + Reality инфраструктура для РФ       │"
  echo "  │   оборона глубиной · 2026                     │"
  echo "  └─────────────────────────────────────────────┘"
  echo -e "${C_RESET}"
}

cmd="${1:-help}"
case "$cmd" in
  all)
    banner
    require_root
    bash "${S}/01-harden.sh"
    bash "${S}/02-install-xray.sh"
    bash "${S}/04-install-hysteria2.sh"
    bash "${S}/backup.sh"
    echo
    ok "Полный комплект развёрнут: Reality (TCP) + Hysteria2 (UDP) + бэкап."
    echo "Дальше: импортируйте ссылки в Hiddify (см. configs/sing-box/ для автопереключения)."
    ;;
  harden)    require_root; bash "${S}/01-harden.sh" ;;
  reality)   require_root; bash "${S}/02-install-xray.sh" ;;
  hysteria2) require_root; bash "${S}/04-install-hysteria2.sh" ;;
  panel)     require_root; bash "${S}/03-install-3xui.sh" ;;
  backup)    require_root; bash "${S}/backup.sh" ;;
  link)      bash "${S}/gen-client-link.sh" "${2:-dimosi-reality}" ;;
  check)     bash "${S}/check-ip-russia.sh" "${2:-}" ;;
  health)    bash "${S}/healthcheck.sh" ;;
  status)
    banner
    echo "Публичный IP: $(public_ip)"
    systemctl is-active --quiet xray 2>/dev/null && ok "xray: active" || warn "xray: не запущен"
    systemctl is-active --quiet hysteria-server 2>/dev/null && ok "hysteria2: active" || warn "hysteria2: не установлен/не запущен"
    echo
    [[ -f "${STATE_DIR}/link-dimosi-reality.txt" ]] && { echo "Reality:"; cat "${STATE_DIR}/link-dimosi-reality.txt"; }
    [[ -f "${STATE_DIR}/link-hysteria2.txt" ]] && { echo "Hysteria2:"; cat "${STATE_DIR}/link-hysteria2.txt"; }
    ;;
  help|*)
    banner
    grep -E '^#( |$)' "$0" | grep -v 'shellcheck' | sed -E 's/^# ?//' | head -n 20
    ;;
esac
