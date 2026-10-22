# Зависимости и атрибуция

| Компонент | Назначение | Источник |
| --- | --- | --- |
| Flutter / Dart | Интерфейс и код клиента | https://github.com/flutter/flutter |
| sing-box 1.13.9 (Windows) | VLESS/Reality и TUN | https://github.com/SagerNet/sing-box/tree/v1.13.9 |
| flutter_singbox_client 1.1.0 (Android) | Готовый адаптер libbox, VPN Service и события | https://github.com/amir-zr/flutter_singbox_client |
| flutter_secure_storage | Защищённый профиль | https://pub.dev/packages/flutter_secure_storage |
| shared_preferences | Выбор приложений и настройки | https://pub.dev/packages/shared_preferences |
| path_provider | Каталог журнала | https://pub.dev/packages/path_provider |
| file_picker | Выбор EXE и экспорт TXT | https://pub.dev/packages/file_picker |
| Roboto | Встроенный шрифт из Flutter SDK, Apache 2.0 | `assets/fonts/LICENSE.txt` |

Версии Dart-зависимостей закреплены в `pubspec.lock`. Бинарный Windows-архив проверяется по SHA-256 GitHub Release; сведения об источнике упаковываются в `core/SOURCE.txt`. Оригинальные лицензии адаптера и ядра сохраняются.

В 0.2.0 Android-адаптер используется через path-зависимость `vendor/flutter_singbox_client`, исходная версия 1.1.0. Локальные изменения и происхождение описаны в `PATCHES.md` внутри этой папки; пример стороннего приложения исключён из анализа основного проекта. Исходники SDK и оригинальная GPL-лицензия должны включаться при передаче исходного проекта. Включённый libbox.aar не изменялся: SHA-256 `b40bc7e0448858e93c5baef36bbca0b5e0d2ba9ce659b3b31fda55e8473a44c5`.

sing-box распространяется под GPLv3 или последующей версией с уведомлением об использовании имени. Android-адаптер — GPLv3. Корневой LICENSE содержит оригинальный текст GPLv3. При распространении клиента необходимо предоставить соответствующие исходники и атрибуцию; материалы нельзя выдавать за разработку Hiddify или SagerNet.

Hiddify изучен как пример пользовательского сценария: https://github.com/hiddify/hiddify-app и https://hiddify.com/app/How-to-use-Hiddify-app/ . Его код и изображения в проект не включены.

Windows-упаковка 2026-10-21: Microsoft Visual Studio Build Tools 2022 17.14.42, Windows SDK 26100, app-local Microsoft Visual C++ Runtime и Inno Setup 6.7.3. Microsoft bootstrapper проверен Authenticode (Microsoft Corporation); Inno Setup — SHA-256 официального GitHub Release и Authenticode (Pyrsys B.V.). Использование Inno Setup — некоммерческая личная сборка. Официальные источники: https://learn.microsoft.com/visualstudio/install/use-command-line-parameters-to-install-visual-studio и https://jrsoftware.org/isdl.php .
