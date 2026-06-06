#!/usr/bin/env bash
#
# Шаг 1. Базовая безопасность сервера (Часть 1, разделы 6–7).
#   - обновление системы
#   - отдельный sudo-пользователь
#   - UFW (открываем ТОЛЬКО нужные порты, SSH — первым!)
#   - fail2ban
#
# Использование:  sudo ./scripts/01-harden.sh
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

require_root
detect_os
load_env

log "Обновляю систему (apt update && upgrade)…"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y

log "Ставлю базовые пакеты (ufw, fail2ban, curl, wget, openssl, jq, nftables)…"
apt-get install -y ufw fail2ban curl wget openssl jq nftables ca-certificates

# ---------- Отдельный пользователь ----------
if id "${ADMIN_USER}" >/dev/null 2>&1; then
  ok "Пользователь ${ADMIN_USER} уже существует."
else
  log "Создаю sudo-пользователя ${ADMIN_USER}…"
  adduser --disabled-password --gecos "" "${ADMIN_USER}"
  usermod -aG sudo "${ADMIN_USER}"
  warn "Задайте пароль для ${ADMIN_USER}:  passwd ${ADMIN_USER}"
  warn "Или (рекомендуется) настройте вход по SSH-ключу: ssh-copy-id ${ADMIN_USER}@<IP>"
fi

# ---------- Файрвол ----------
# КРИТИЧНО: сначала разрешаем SSH, иначе потеряем доступ при enable.
log "Настраиваю UFW (SSH:${SSH_PORT}, VLESS:${VLESS_PORT}/tcp, панель:${PANEL_PORT}/tcp)…"
ufw --force reset >/dev/null
ufw default deny incoming
ufw default allow outgoing
ufw allow "${SSH_PORT}/tcp"          comment 'SSH'
ufw allow "${VLESS_PORT}/tcp"        comment 'VLESS Reality / XHTTP'
ufw allow "${PANEL_PORT}/tcp"        comment '3X-UI panel'

# Hysteria2 (если используется тот же или другой UDP-порт) + диапазон port hopping.
if [[ -n "${HY2_PORT:-}" ]]; then
  ufw allow "${HY2_PORT}/udp"        comment 'Hysteria2'
fi
if [[ -n "${HY2_HOP_RANGE:-}" ]]; then
  ufw allow "${HY2_HOP_RANGE}/udp"   comment 'Hysteria2 port hopping'
fi

ufw --force enable
ufw status verbose

# ---------- fail2ban ----------
log "Включаю fail2ban (защита SSH от перебора паролей)…"
systemctl enable --now fail2ban

ok "Базовая защита настроена."
echo
warn "Дальше рекомендуется: вход по SSH-ключу + отключение входа по паролю root."
warn "См. docs/02-server-hardening.md"
