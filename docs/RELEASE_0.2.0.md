# Sme11_VPN 0.2.0 — результат работы

## Что сделано

- Каталог до 20 профилей VLESS/Reality TCP, ручное добавление и вставка из буфера, сохранение старого профиля при переносе.
- Вкладка «Серверы»: ручной выбор, фактический активный сервер, HTTPS-доступность, задержка и возраст проверки.
- Необязательный автовыбор по задержке: URLTest раз в минуту, допуск 100 мс. По умолчанию выключен. Авто не выбирает direct при отказе профилей.
- Android-уведомление с реальным статусом, профилем и скоростью в кбит/с или Мбит/с, кнопкой отключения. Управление восстанавливается после пересоздания Activity.
- Выбор приложений и фильтры журнала сохранены; секреты всех профилей маскируются.

## Файлы

Основной код изменён или добавлен:

- `lib/app_controller.dart` — каталог, проверки, выбор и возврат прежнего выбора при ошибке хранения.
- `lib/domain/profile_catalog.dart`, `config_builder.dart`, `traffic.dart` — модели, selector/URLTest и единицы скорости.
- `lib/services/storage.dart`, `core_control.dart`, `vpn_engine.dart` — перенос данных, loopback API, native/Windows управление.
- `lib/ui/app.dart`, `profile_editor.dart`, `servers_page.dart`, `page_frame.dart` — четыре вкладки и форма отдельных профилей.
- `android/app/src/main/kotlin/com/sme11/sme11_vpn/MainActivity.kt` — разрешение уведомлений, настройки и восстановление API.
- `vendor/flutter_singbox_client` — локальная копия SDK 1.1.0 с сохранением лицензии. Изменены NotificationConfig, BoxService, ServiceNotificationHelper, SingboxVPNService, FlutterSingboxClientPlugin, SingboxManager; добавлены RuntimeConnection и TrafficFormatTest. Подробности в `PATCHES.md`.
- `pubspec.yaml`, `pubspec.lock`, `analysis_options.yaml` — версия, path-зависимость и исключение стороннего example из анализа.
- `test/catalog_test.dart`, `support.dart`, `widget_test.dart` — проверки переноса, выбора, отказов и компоновки.
- `scripts/check_config.dart`, `check_multi_core.dart` — проверка JSON и настоящего API sing-box.

Созданы документы `docs/RELEASE_0.2.0.md`, `vendor/flutter_singbox_client/PATCHES.md`. Обновлены README, PROJECT, ARCHITECTURE, ROADMAP, CHANGELOG, DATABASE, API, DEPLOY, TESTING, DECISIONS, DEPENDENCIES, индекс docs и согласованное предложение MULTI_PROFILE_PROPOSAL. Превью интерфейса обновлены в `docs/screenshots`.

## Проверки

Анализ без замечаний; 24 Flutter-теста и один Kotlin JVM-тест прошли. Пять конфигураций приняты официальным sing-box 1.13.9. На настоящем API проверены авторизация, HTTPS-пробы, ручной выбор, автовыбор доступного тестового пути и отказ пробы. APK установлен и проверен в Android API 36: каталог, allowlist, временная offline-проверка, TUN, уведомление при свёрнутом UI, восстановление активного сервера и переход в Auto после пересоздания Activity. Реальный Reality-сервер не использовался.

## Установка

Для POCO использовать `dist/Sme11_VPN-0.2.0-arm64-v8a.apk`. Перед обновлением отключить VPN. Устанавливать поверх 0.1.1, не удаляя приложение: сертификаты подписей совпадают. Контрольные суммы — `dist/SHA256-0.2.0.txt`. Сборка подписана тестовым ключом и предназначена для личного тестирования.

## Риски и следующие улучшения

Переключение может прервать открытые соединения. Задержка не равна максимальной скорости; несколько портов одного хоста не защищают от отказа всего сервера. Kill switch и восстановление уничтоженного сервис-процесса отсутствуют. Android SDK содержит alpha-ядро, поэтому нужен тест на POCO/HyperOS с реальными профилями, ненулевым трафиком, блокировкой экрана и отказом текущего сервера. Windows исходники обновлены; EXE не собран из-за отсутствия Visual Studio C++.

Далее: испытания на вашем сервере, полноценная Windows-сборка, стабильное Android-ядро и собственная release-подпись.
