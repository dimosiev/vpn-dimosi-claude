# shellcheck shell=bash
# Общая библиотека для всех скриптов инфраструктуры.
# Подключается через:  source "$(dirname "$0")/lib/common.sh"

set -Eeuo pipefail

# ---------- Цветной вывод / логирование ----------
if [[ -t 1 ]]; then
  C_RESET='\033[0m'; C_RED='\033[0;31m'; C_GRN='\033[0;32m'
  C_YEL='\033[0;33m'; C_BLU='\033[0;34m'; C_BOLD='\033[1m'
else
  C_RESET=''; C_RED=''; C_GRN=''; C_YEL=''; C_BLU=''; C_BOLD=''
fi

log()  { echo -e "${C_BLU}[*]${C_RESET} $*"; }
ok()   { echo -e "${C_GRN}[✓]${C_RESET} $*"; }
warn() { echo -e "${C_YEL}[!]${C_RESET} $*" >&2; }
err()  { echo -e "${C_RED}[✗]${C_RESET} $*" >&2; }
die()  { err "$*"; exit 1; }

# ---------- Базовые проверки ----------
require_root() {
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Запустите от root или через sudo."
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Не найдена команда: $1"
}

# Корень репозитория (на 1 уровень выше каталога scripts/).
repo_root() {
  cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd
}

# Загрузка .env из корня репозитория (если есть), затем подстановка дефолтов.
load_env() {
  local root; root="$(repo_root)"
  if [[ -f "$root/.env" ]]; then
    log "Загружаю конфигурацию из .env"
    set -a; # shellcheck disable=SC1091
    source "$root/.env"; set +a
  else
    warn ".env не найден — использую значения по умолчанию (см. .env.example)."
  fi

  # Дефолты — безопасные значения из гайда.
  : "${DOMAIN:=}"
  : "${REALITY_SNI:=www.microsoft.com}"
  : "${REALITY_DEST:=www.microsoft.com:443}"
  : "${VLESS_PORT:=443}"
  : "${HY2_PORT:=443}"
  : "${HY2_HOP_RANGE:=20000:50000}"
  : "${PANEL_PORT:=2053}"
  : "${SSH_PORT:=22}"
  : "${ADMIN_USER:=myadmin}"
  : "${TG_BOT_TOKEN:=}"
  : "${TG_CHAT_ID:=}"
  : "${XRAY_CONFIG:=/usr/local/etc/xray/config.json}"
  : "${HY2_CONFIG:=/etc/hysteria/config.yaml}"
  : "${STATE_DIR:=/etc/vpn-dimosi}"
}

# ---------- ОС ----------
detect_os() {
  [[ -f /etc/os-release ]] || die "Не удалось определить ОС (/etc/os-release отсутствует)."
  # shellcheck disable=SC1091
  source /etc/os-release
  OS_ID="${ID:-unknown}"; OS_VER="${VERSION_ID:-unknown}"
  case "$OS_ID" in
    ubuntu|debian) : ;;
    *) warn "ОС $OS_ID $OS_VER не тестировалась. Гайд рассчитан на Ubuntu 22.04/24.04 и Debian 12." ;;
  esac
}

# ---------- Генераторы секретов ----------
gen_uuid() {
  if command -v xray >/dev/null 2>&1; then xray uuid
  elif [[ -r /proc/sys/kernel/random/uuid ]]; then cat /proc/sys/kernel/random/uuid
  else require_cmd uuidgen; uuidgen
  fi
}

# Короткий ID Reality — hex, чётная длина 2..16.
gen_short_id() { openssl rand -hex 8; }

# Пара ключей Reality x25519. Печатает: "PRIVATE\nPUBLIC".
gen_reality_keys() {
  require_cmd xray
  local out; out="$(xray x25519)"
  local priv pub
  priv="$(echo "$out" | awk -F': ' '/Private/{print $2}')"
  pub="$(echo "$out" | awk -F': ' '/Public/{print $2}')"
  printf '%s\n%s\n' "$priv" "$pub"
}

gen_password() { openssl rand -base64 24 | tr -d '/+=' | head -c 32; }

# ---------- Утилиты ----------
# Подстановка __PLACEHOLDER__ -> значение в файле-шаблоне. Печатает результат в stdout.
render_template() {
  local tpl="$1"; shift
  [[ -f "$tpl" ]] || die "Шаблон не найден: $tpl"
  local content; content="$(cat "$tpl")"
  while [[ $# -gt 1 ]]; do
    local key="$1" val="$2"; shift 2
    content="${content//$key/$val}"
  done
  printf '%s\n' "$content"
}

# Публичный IPv4 сервера.
public_ip() {
  curl -fsS4 --max-time 5 https://api.ipify.org 2>/dev/null \
    || curl -fsS4 --max-time 5 https://ifconfig.me 2>/dev/null \
    || ip -4 route get 1 2>/dev/null | awk '{print $7; exit}'
}

# Отправка сообщения в Telegram (если настроено).
tg_notify() {
  [[ -n "${TG_BOT_TOKEN:-}" && -n "${TG_CHAT_ID:-}" ]] || return 0
  curl -fsS --max-time 10 \
    "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TG_CHAT_ID}" \
    -d parse_mode="HTML" \
    --data-urlencode text="$1" >/dev/null 2>&1 || warn "Не удалось отправить уведомление в Telegram."
}

# Безопасное сохранение секрета в STATE_DIR (chmod 600).
save_state() {
  install -d -m 700 "${STATE_DIR}"
  printf '%s\n' "$2" > "${STATE_DIR}/$1"
  chmod 600 "${STATE_DIR}/$1"
}
read_state() { cat "${STATE_DIR}/$1" 2>/dev/null || true; }
