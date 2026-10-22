param([string]$Flutter = 'flutter')
$ErrorActionPreference = 'Stop'
$previousWindows = $env:FLUTTER_WINDOWS
Push-Location (Join-Path $PSScriptRoot '..')
try {
    # Только в этом процессе: Android не требует Windows symlink или Visual Studio.
    $env:FLUTTER_WINDOWS = 'false'
    & $Flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Не удалось настроить Flutter-зависимости.' }
    if (-not (Test-Path 'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java')) {
        throw 'Flutter не создал регистрацию Android-плагинов. Сборка остановлена.'
    }
    & $Flutter analyze --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Статический анализ не прошёл.' }
    & $Flutter test --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Тесты не прошли.' }
    & $Flutter build apk --release --split-per-abi --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Сборка APK не прошла.' }
} finally {
    $env:FLUTTER_WINDOWS = $previousWindows
    Pop-Location
}
