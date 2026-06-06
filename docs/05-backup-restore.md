# 05. Бэкап и восстановление за 15 минут

Ключевое правило устойчивости: **держите бэкап и умейте поднять сервер заново за
15 минут**. Один раз пройдите весь путь — и блокировки перестанут пугать.

## Что бэкапим

`scripts/backup.sh` собирает в один архив:

- **Секреты** (`STATE_DIR`, по умолчанию `/etc/vpn-dimosi`): UUID, ключи Reality,
  пароли Hysteria2, готовые ссылки.
- **Конфиги:** `config.json` Xray, `config.yaml` Hysteria2, база 3X-UI (если есть).
- `RESTORE.txt` с инструкцией внутри архива.

```bash
sudo ./scripts/backup.sh                 # → /root/vpn-backups/vpn-backup-ДАТА.tar.gz
sudo ./scripts/backup.sh /mnt/storage    # свой каталог
```

Хранятся последние 10 архивов (ротация). Если в `.env` заданы `TG_BOT_TOKEN` и
`TG_CHAT_ID` — архив отправляется в Telegram-бота.

> Сделайте бэкап **после каждой значимой настройки** и **перед обновлениями**.
> Храните копию **оффлайн** (флешка / зашифрованный архив / менеджер паролей) —
> это часть «тревожного чемоданчика».

## Восстановление на новом сервере (смена IP)

Когда IP заблокировали — это штатная ситуация, а не поломка:

1. Закажите новый VPS (другой хостинг/страна), чистая Ubuntu/Debian.
2. Клонируйте репозиторий, распакуйте бэкап:
   ```bash
   git clone <repo-url> vpn-dimosi && cd vpn-dimosi
   sudo tar -xzf vpn-backup-ДАТА.tar.gz -C /tmp/restore
   sudo install -d -m 700 /etc/vpn-dimosi
   sudo cp -a /tmp/restore/state/. /etc/vpn-dimosi/
   sudo chmod 600 /etc/vpn-dimosi/*
   cp .env.example .env   # верните свои настройки (донор/порты)
   ```
3. Разверните:
   ```bash
   sudo ./deploy.sh all
   ```
   Скрипты **переиспользуют сохранённые ключи** → UUID/Reality/Hysteria2 те же,
   меняется только адрес сервера.
4. Перевыпустите ссылки под новый IP:
   ```bash
   sudo ./scripts/gen-client-link.sh
   sudo ./scripts/gen-singbox-client.sh
   ```

С **подпиской** (Marzban/3X-UI) раздавать ничего не надо — клиент сам обновит
подписку и получит свежие конфиги (см. [06-clients.md](06-clients.md)).

## Оффлайн «тревожный чемоданчик»

Сохраните локально, не только в облаке:
- все vless:// / hysteria2:// / подписочные ссылки и QR;
- бэкап (`vpn-backup-*.tar.gz`);
- установщики клиентов (v2RayTun/Hiddify/v2rayN), GoodbyeDPI/zapret, Tor Browser —
  магазины и сайты загрузок тоже могут оказаться недоступны.
