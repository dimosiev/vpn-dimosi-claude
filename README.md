# vpn-dimosi — устойчивая VPN-инфраструктура для РФ (2026)

Автоматизированная, воспроизводимая инфраструктура для надёжного доступа к
открытому интернету из России. Превращает ручные гайды по **VLESS + Reality**
в Infrastructure-as-Code: несколько команд — и развёрнут весь «боевой комплект»
с обороной глубиной.

> **Принцип 2026 года:** выигрывает не «самый крутой протокол», а **разнообразие
> и готовность переключаться**. Reality — ваш дом, Hysteria2 — окно, CDN/CFXHTTP —
> пожарная лестница, оффлайн-чемоданчик и второй сервер — то, что превращает
> «всё пропало» в «15 минут возни».

---

## Что это и почему именно так

К 2026 году DPI-системы РФ (ТСПУ) детектируют классические VPN (WireGuard,
OpenVPN) почти со 100% точностью. **VLESS + Reality** не прячет туннель, а
**притворяется обычным визитом на популярный HTTPS-сайт** (microsoft.com): для
DPI это легитимная веб-сессия, которую нельзя заблокировать, не сломав сам
сайт-донор. Связка Reality + Vision показывала ~98–99% обхода в начале 2026.

Поскольку с декабря 2025 ТСПУ начало местами распознавать и сам Reality (по
JA3/JA4 и поведению), эта инфраструктура изначально строит **несколько
разнотипных слоёв**, а не одну схему.

## Архитектура (оборона глубиной)

```
                        ┌──────────────── КЛИЕНТ (Hiddify / sing-box) ────────────────┐
                        │   url-test автопереключение между профилями, .ru → напрямую  │
                        └───────────────┬─────────────────────────┬───────────────────┘
                                        │ TCP                      │ UDP
                ┌───────────────────────▼───────┐     ┌────────────▼──────────────────┐
   Слой 1 (дом) │  VLESS + Reality + Vision      │     │  Hysteria2 (Salamander)        │ Слой 2 (окно)
                │  :443/tcp, маскировка под SNI  │     │  :443/udp + port hopping       │
                └───────────────────────┬────────┘     └────────────┬──────────────────┘
                                        └───────────┬───────────────┘
                                          ┌─────────▼─────────┐
                                          │  VPS (Финляндия/   │   + второй VPS в другой
                                          │  Германия/NL/SE)   │     стране (отказоустойчивость)
                                          └─────────┬─────────┘
                                                    ▼
                                            свободный интернет

   Резервы без своего сервера: CDN Cloudflare · CFXHTTP (бесплатно) · zapret/GoodbyeDPI · Tor+мосты
```

Что автоматизирует этот репозиторий:

| Слой | Инструмент | Скрипт |
|------|-----------|--------|
| Базовая защита сервера | UFW + fail2ban + sudo-юзер | `scripts/01-harden.sh` |
| **Основной туннель (TCP)** | VLESS + Reality + Vision (Xray-core) | `scripts/02-install-xray.sh` |
| Альтернатива с GUI | панель 3X-UI | `scripts/03-install-3xui.sh` |
| **UDP-резерв** | Hysteria2 + Salamander + port hopping | `scripts/04-install-hysteria2.sh` |
| Клиентские ссылки/QR | vless:// + hysteria2:// | `scripts/gen-client-link.sh` |
| Автопереключение клиента | sing-box url-test профиль | `scripts/gen-singbox-client.sh` |
| «Тревожный чемоданчик» | бэкап + Telegram | `scripts/backup.sh` |
| Мониторинг | healthcheck + проверка IP из РФ | `scripts/healthcheck.sh`, `check-ip-russia.sh` |

Резервные схемы без сервера (CDN, CFXHTTP, Tor, клиентские обходчики DPI)
описаны в [`docs/08-defense-in-depth.md`](docs/08-defense-in-depth.md).

---

## Быстрый старт

**Предусловие:** чистый VPS (Ubuntu 22.04/24.04 или Debian 12) с «чистым» IP,
доступным из РФ. Как выбрать VPS — см. [`docs/01-quickstart.md`](docs/01-quickstart.md).

```bash
# 1. На сервере: клонируйте репозиторий
git clone <repo-url> vpn-dimosi && cd vpn-dimosi

# 2. Настройте параметры (донор, порты, Telegram)
cp .env.example .env
nano .env                      # как минимум проверьте REALITY_SNI

# 3. Разверните полный боевой комплект одной командой
sudo ./deploy.sh all
#   → защита сервера + Reality(TCP) + Hysteria2(UDP) + бэкап
#   → в конце печатаются vless:// / hysteria2:// ссылки и QR-коды

# 4. Сгенерируйте клиентский профиль с автопереключением
sudo ./scripts/gen-singbox-client.sh   # → out/client-singbox.json для Hiddify
```

Или по шагам / через `make`:

```bash
sudo make harden        # базовая защита
sudo make reality       # VLESS + Reality + Vision
sudo make hysteria2     # Hysteria2 + port hopping
sudo make status        # статус и ссылки
make check              # доступен ли IP из РФ
sudo make backup        # тревожный чемоданчик
make help               # все команды
```

## Подключение клиентов

Нужен **современный прокси-клиент** с поддержкой свежего Xray-core и flow Vision
(обычные «классические» VPN-приложения не подойдут):

- **iOS:** v2RayTun, Streisand, Hiddify
- **Android:** v2RayTun, Hiddify, v2rayNG
- **Windows:** v2rayN, Hiddify · **macOS:** v2RayTun, Hiddify

Импортируйте `vless://…` ссылку (или QR) из вывода деплоя, либо файл
`out/client-singbox.json` в Hiddify — он сам выберет живой профиль.
Подробно: [`docs/06-clients.md`](docs/06-clients.md).

## Документация

| Документ | О чём |
|----------|-------|
| 👉 [00-poshagovo-dlya-novichka.md](docs/00-poshagovo-dlya-novichka.md) | **Пошагово для не-программиста** — от покупки сервера до подключения |
| [01-quickstart.md](docs/01-quickstart.md) | Выбор VPS, «чистый» IP, первое подключение |
| [02-server-hardening.md](docs/02-server-hardening.md) | UFW, fail2ban, SSH-ключи, защита панели |
| [03-vless-reality.md](docs/03-vless-reality.md) | Как устроен Reality, выбор донора, параметры |
| [04-hysteria2.md](docs/04-hysteria2.md) | UDP-резерв, Salamander, port hopping |
| [05-backup-restore.md](docs/05-backup-restore.md) | Бэкапы и восстановление за 15 минут |
| [06-clients.md](docs/06-clients.md) | Приложения, подписки, автопереключение |
| [07-when-blocked.md](docs/07-when-blocked.md) | План действий при блокировке (дерево решений) |
| [08-defense-in-depth.md](docs/08-defense-in-depth.md) | Каталог всех схем: CDN, CFXHTTP, AmneziaWG, Tor… |
| [09-debug.md](docs/09-debug.md) | Логи, типичные ошибки, алгоритм диагностики |

## Тотальное резервирование (чеклист)

- [ ] 2 VPS у разных хостингов в разных странах
- [ ] Основная схема: VLESS + Reality + Vision
- [ ] UDP-вариант: Hysteria2 (+ port hopping)
- [ ] Резерв без своего IP: CDN Cloudflare / CFXHTTP
- [ ] Клиент с автопереключением (Hiddify / sing-box url-test)
- [ ] Бэкап регулярно + в Telegram
- [ ] Мониторинг доступности IP из РФ
- [ ] Оффлайн «чемоданчик»: ссылки/ключи/бэкапы/установщики + Tor Browser
- [ ] Вы один раз вручную прошли «поднять сервер за 15 минут»

---

## Безопасность и право

- Поднятие **личного** сервера для доступа к открытому интернету — нормальная
  практика в большинстве юрисдикций. Законы меняются; ответственность за
  использование — на вас. Это не юридическая консультация.
- **Не используйте сервер для противоправных действий** (спам, атаки, сканирование,
  пиратство) — хостинг забанит, и вы потеряете IP.
- Гигиена: не оставляйте дефолтные пароли, не выставляйте панель наружу, делайте
  бэкапы. Секреты (`.env`, `out/`, `STATE_DIR`) **не коммитятся** (см. `.gitignore`).

## Источники

Инфраструктура построена по трём гайдам «Свой VPN на VLESS + Reality для РФ»
(части 1–3, 2026). Перед установкой сверяйтесь с актуальными репозиториями:
[Xray](https://github.com/XTLS/Xray-core) ·
[3X-UI](https://github.com/MHSanaei/3x-ui) ·
[Hysteria](https://github.com/apernet/hysteria) ·
[sing-box](https://github.com/SagerNet/sing-box) ·
[Marzban](https://github.com/Gozargah/Marzban).

*Актуально на середину 2026. Методы ТСПУ и версии ПО меняются — периодически обновляйте Xray-core.*
