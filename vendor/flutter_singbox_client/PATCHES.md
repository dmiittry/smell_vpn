# Локальная модификация для Sme11_VPN 0.2.1

Исходный пакет: flutter_singbox_client 1.1.0 из локального Pub-кэша, источник https://pub.dev/packages/flutter_singbox_client/versions/1.1.0 и https://github.com/amir-zr/flutter_singbox_client . Оригинальный LICENSE сохранён. Это адаптер стороннего автора, не собственная реализация VLESS/Reality.

Изменения:

- Dart/Kotlin NotificationConfig принимает отображаемые имена профилей по tag.
- ServiceNotificationHelper показывает реальный активный профиль и скорость в кбит/с или Мбит/с, с раскрываемым текстом уведомления.
- BoxService следит за выбором proxy/auto; межпоточный tag хранится в AtomicReference.
- Flutter plugin освобождает SingboxManager при detach только для остановленного сервиса; работающий сервис продолжает обновлять уведомление.
- SingboxManager при повторной инициализации не переподключает существующий CommandClient: краткий STOPPED мешал восстановлению API после пересоздания Activity.
- SingboxVPNService возвращает своей Activity только port/secret локального API для восстановления управления.
- Добавлен JVM-тест преобразования байт/с в битовые единицы.
- В 0.2.1 callbacks CommandClient больше не меняют lifecycle-состояние; канал управления восстанавливается максимум три раза с защитой поколения клиента.
- EventChannel отменяет старые collectors при отмене или повторной подписке.
- DefaultNetworkMonitor игнорирует onLost/обновления старой сети и фиксирует блокировку сети Android.
- RuntimeDiagnostics атомарно сохраняет фиксированные lifecycle/сеть/питание и Android-коды завершения процесса. CoreLogSummary сохраняет безопасные категории WARN/ERROR без произвольного текста; независимые квоты и ограничение повторов защищают важную историю.
- Сервисы не перезапускаются с пустой конфигурацией, повторный Intent не создаёт второе ядро; остановка подтверждается после onDestroy. Поздний результат отменённого запуска не возвращает STARTED.

libbox.aar оставлен без изменений, включённое ядро 1.14.0-alpha.20. SHA-256: `b40bc7e0448858e93c5baef36bbca0b5e0d2ba9ce659b3b31fda55e8473a44c5`.

После переноса SDK из Pub-кэша существующий Kotlin incremental cache может ссылаться на старое расположение. Перекомпиляция без удаления данных: `android/gradlew.bat :flutter_singbox_client:compileReleaseKotlin '-Pkotlin.incremental=false' --rerun-tasks`.
