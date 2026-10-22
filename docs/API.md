# Внутренние интерфейсы

Публичного HTTP API нет. Приложение использует локальные платформенные каналы и интерфейс `VpnEngine`.

## VpnEngine

`initialize`, `connect(config, mode, packages, profileNames)`, `selectEndpoint(tag)`, `checkEndpoints(config, tags, requireRunning: false)`, `disconnect`, `applications`, `dispose`; поток `EngineEvent` содержит состояние туннеля, сообщения, статистику, фактический выбранный tag и результаты проверок. Внутренний необязательный флаг `requireRunning: true` используется для пинга главного экрана: если работающее ядро уже остановлено, вызов завершается ошибкой и не запускает временный сервис проверки.

`AppController.checkConnection()` проверяет фактический активный сервер текущей сессии. `connectionCheck`, `verifyingConnection`, `connectionVerified` описывают результат отдельно от состояния VPN-сервиса. Неудачная проба попадает в фильтр ошибок журнала.

Состояния: disconnected, connecting, running, disconnecting, failed. Ошибка сохраняется после stopped. Все вызовы подключений проходят через AppController.

## Канал Android `sme11_vpn/apps`

- `listApps` → список `{id, name}` приложений с активностью запуска.
- `validateApps(List<String>)` → список отсутствующих пакетов.
- `requestNotifications` → bool, POST_NOTIFICATIONS на Android 13+, отказ не блокирует VPN.
- `notificationSettings` → открывает системные настройки уведомлений приложения.
- `currentControl` → `{port, secret}` работающего собственного VPN service для восстановления управления после повторного открытия Activity; профиль не экспортируется.
- `runtimeDiagnostics` → `{events: [{id, time, level, message}], userStop}`: безопасный служебный журнал и признак запроса штатной остановки текущего сеанса. Время — Unix milliseconds. Профили и тексты системных crash dumps не передаются.

EngineEvent дополнительно содержит source, исходное time, необязательный id и userInitiated. Чтение служебного журнала не меняет состояние туннеля и не вызывает переподключение VPN.

Список приложений строится в фоновом executor, ответы приходят в главный поток. Широкое разрешение QUERY_ALL_PACKAGES не запрашивается.

## Канал Windows `sme11_vpn/lifecycle`

`attachProcess(int pid)` → bool. Привязывает процесс ядра к Job Object runner. При ошибке привязки подключение отменяется, чтобы не оставить работающий туннель после закрытия UI.

Параметры VLESS передаются ядру через JSON в stdin. Пользовательские данные не попадают в аргументы оболочки.

## Локальный API sing-box

Clash API слушает только `127.0.0.1` на случайном свободном порту; каждый запуск получает криптографически случайный Bearer-токен. Внешний UI не загружается. `GET /version`, `GET /proxies`, `PUT /proxies/proxy` с `{name: tag}`, `GET /proxies/<tag>/delay?timeout=5000&url=<HTTPS>` используются только внутри приложения. CORS разрешает только локальный origin, доступ частной сети браузера выключен. В Windows конфигурация с секретом передаётся в stdin.

Группы: `proxy` — selector, `auto` — URLTest, `ep_<local-id>` — отдельный VLESS. Ручной выбор подтверждается чтением `now`; UI опрашивает реальный активный tag каждые 2 секунды. При ошибке сохранения выбора приложение пытается восстановить прежний выбор ядра. HTTPS-пробы выполняются максимум по две одновременно. HTTP URL в delay API sing-box 1.13.9 заменяется ядром на стандартный HTTPS URL; производственная проверка использует HTTPS.
