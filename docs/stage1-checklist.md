# Проверка этапа 1 на роутере (KN-1811)

Установка альфы, если релиз опубликован:

    sh -c "$(curl -fsSL https://raw.githubusercontent.com/Soporif1c/GrKa-Keen/release-1.0/install.sh)" _ v1.0.0-alpha.1

Если релиза нет: скопировать `grka-keen-1.0.0-alpha.1.tar.gz` в `/opt/tmp` и выполнить:

    tar -C / -xzf /opt/tmp/grka-keen-1.0.0-alpha.1.tar.gz
    sh /opt/share/grka/bin/grka migrate && /opt/etc/init.d/S99grka-keen restart

Дальше команда `grka` — это `sh /opt/share/grka/bin/grka`.

1. `grka status` — «Состояние: ok», политика найдена, правила на месте, TUN поднят.
2. Открыть панель `http://<IP роутера>:1100`: вкладки «Статус», «Селекторы», «Конфигурация», «Логи» открываются, на «Статусе» есть строка «Сторож» и кнопка «Поставить VPN на паузу». Если панель открывается по имени (не по IP), добавьте имя в `allowed_hosts` в `/opt/etc/grka/settings.json`.
3. Перезагрузить роутер три раза. После каждой загрузки:
   `grka status` и `grka logs journal 30` — в журнале «Политика «GrKa» найдена», «Правила маршрутизации применены», состояние ok.
4. Отключить и включить интернет в веб-интерфейсе Keenetic. Через 10 секунд `grka status` — ok.
5. `kill -9 $(cat /tmp/grka/core.pid)` — через 5–10 секунд ядро снова работает, в журнале «упало, перезапуск через 5 с».
6. `grka device <MAC приставки> gaming`, затем `ip rule` — есть правила 97 и 98 с IP приставки;
   `iptables -t nat -S GRKA_DNS` — две строки с этим IP.
7. `grka pause` — интернет у устройств политики идёт напрямую; `grka resume` — снова через ядро.
8. `grka diag` — прислать получившийся файл (токены в нём скрыты, у MAC видна только первая половина).
