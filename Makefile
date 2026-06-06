# Удобные сокращения. Под капотом — ./deploy.sh.
# Использование:  sudo make all   |   make help

.PHONY: help all harden reality hysteria2 panel backup update versions status check health link singbox lint

help:        ## показать список команд
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

all:         ## полный боевой комплект (harden + reality + hysteria2 + backup)
	sudo ./deploy.sh all

harden:      ## базовая защита сервера (UFW, fail2ban, пользователь)
	sudo ./deploy.sh harden

reality:     ## VLESS + Reality + Vision (чистый Xray)
	sudo ./deploy.sh reality

hysteria2:   ## Hysteria2 UDP-резерв + port hopping
	sudo ./deploy.sh hysteria2

panel:       ## веб-панель 3X-UI (GUI вместо чистого Xray)
	sudo ./deploy.sh panel

backup:      ## собрать «тревожный чемоданчик»
	sudo ./deploy.sh backup

update:      ## обновить всё до свежих версий (Xray, Hysteria2, код)
	sudo ./deploy.sh update

versions:    ## показать установленные и последние доступные версии
	./deploy.sh versions

status:      ## статус сервисов и клиентские ссылки
	sudo ./deploy.sh status

check:       ## проверить доступность IP из РФ
	./deploy.sh check

health:      ## локальный healthcheck (сервисы/порты)
	sudo ./deploy.sh health

link:        ## перевыпустить vless:// ссылку и QR
	sudo ./scripts/gen-client-link.sh

singbox:     ## сгенерировать клиентский конфиг sing-box с автопереключением
	sudo ./scripts/gen-singbox-client.sh

lint:        ## проверить все скрипты shellcheck'ом
	@command -v shellcheck >/dev/null 2>&1 || { echo "Установите shellcheck"; exit 1; }
	shellcheck -x deploy.sh scripts/*.sh
