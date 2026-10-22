param(
    [string]$Flutter = 'C:\flutter\bin\flutter.bat',
    [string]$InnoCompiler = '',
    [switch]$SkipChecks
)
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskPreviousWindows = $env:FLUTTER_WINDOWS
Push-Location $taskRoot
try {
    if (-not (Test-Path -LiteralPath 'third_party/windows/core/sing-box.exe')) {
        throw 'Сначала выполните scripts/prepare_windows.ps1.'
    }
    # Pub get без symlink-привилегий; build использует только локальные junction.
    $env:FLUTTER_WINDOWS = 'false'
    & $Flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'Не удалось разрешить закреплённые зависимости.' }
    $taskMetadata = Get-Content -LiteralPath '.flutter-plugins-dependencies' -Raw | ConvertFrom-Json
    $taskLinks = Join-Path $taskRoot 'windows/flutter/ephemeral/.plugin_symlinks'
    New-Item -ItemType Directory -Path $taskLinks -Force | Out-Null
    foreach ($taskPlugin in $taskMetadata.plugins.windows) {
        if ($taskPlugin.name -notmatch '^[a-zA-Z0-9_]+$') { throw 'Некорректное имя зависимости.' }
        $taskTarget = [IO.Path]::GetFullPath($taskPlugin.path)
        $taskLink = Join-Path $taskLinks $taskPlugin.name
        if (-not (Test-Path -LiteralPath $taskTarget)) { throw 'Каталог зависимости отсутствует.' }
        if (Test-Path -LiteralPath $taskLink) {
            $taskExisting = Get-Item -LiteralPath $taskLink
            if (-not $taskExisting.LinkType) { throw "Ожидалась ссылка зависимости: $taskLink" }
        } else {
            New-Item -ItemType Junction -Path $taskLink -Target $taskTarget | Out-Null
        }
    }
    $env:FLUTTER_WINDOWS = 'true'
    # Метаданные уже актуальны: повторный pub get генерирует Windows-регистратор,
    # сохраняя существующие junction вместо запроса Developer Mode.
    & $Flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'Не удалось сгенерировать Windows-регистрацию плагинов.' }
    if (-not $SkipChecks) {
        & $Flutter analyze --no-pub
        if ($LASTEXITCODE -ne 0) { throw 'Статический анализ не прошёл.' }
        & $Flutter test --no-pub
        if ($LASTEXITCODE -ne 0) { throw 'Тесты не прошли.' }
    }
    & $Flutter build windows --release --no-pub
    if ($LASTEXITCODE -ne 0) { throw 'Сборка Windows не прошла.' }

    $taskBundle = Join-Path $taskRoot 'build/windows/x64/runner/Release'
    $taskVsWhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio/Installer/vswhere.exe'
    $taskVsInstall = & $taskVsWhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($LASTEXITCODE -ne 0 -or -not $taskVsInstall) { throw 'Не найдены библиотеки Visual C++ Runtime.' }
    $taskRedistVersion = Get-ChildItem -LiteralPath (Join-Path $taskVsInstall 'VC/Redist/MSVC') -Directory |
        Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } |
        Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    $taskCrt = Join-Path $taskRedistVersion.FullName 'x64/Microsoft.VC143.CRT'
    if (-not (Test-Path -LiteralPath $taskCrt)) { throw 'Не найден x64 CRT для автономной установки.' }
    Get-ChildItem -LiteralPath $taskCrt -Filter '*.dll' | Copy-Item -Destination $taskBundle -Force
    Copy-Item -LiteralPath 'LICENSE' -Destination $taskBundle -Force
    Copy-Item -LiteralPath 'docs/DEPENDENCIES.md' -Destination (Join-Path $taskBundle 'DEPENDENCIES_RU.md') -Force
    Copy-Item -LiteralPath 'packaging/windows/INSTALL_RU.txt' -Destination (Join-Path $taskBundle 'README_RU.txt') -Force

    $taskVersionText = Get-Content -LiteralPath 'pubspec.yaml' -Raw
    if ($taskVersionText -notmatch '(?m)^version:\s+([0-9]+\.[0-9]+\.[0-9]+)') { throw 'Не найдена версия приложения.' }
    $taskVersion = $Matches[1]
    $taskOutput = Join-Path $taskRoot 'dist'
    New-Item -ItemType Directory -Path $taskOutput -Force | Out-Null
    $taskPortable = Join-Path $taskOutput "Sme11_VPN-$taskVersion-Windows-x64-Portable.zip"
    Compress-Archive -Path (Join-Path $taskBundle '*') -DestinationPath $taskPortable -Force

    if (-not $InnoCompiler) {
        $taskCandidates = @((Join-Path $taskRoot '.tools/inno/ISCC.exe'),
            (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6/ISCC.exe'))
        $InnoCompiler = $taskCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    }
    if (-not $InnoCompiler) { throw 'Portable ZIP готов, но для Setup.exe требуется Inno Setup 6.' }
    & $InnoCompiler "/DAppVersion=$taskVersion" "/DBundleDir=$taskBundle" "/DOutputFolder=$taskOutput" 'packaging/windows/Sme11_VPN.iss'
    if ($LASTEXITCODE -ne 0) { throw 'Установщик не собран.' }
    $taskSetup = Join-Path $taskOutput "Sme11_VPN-$taskVersion-Windows-x64-Setup.exe"
    @($taskPortable, $taskSetup) | ForEach-Object {
        $taskHash = Get-FileHash -LiteralPath $_ -Algorithm SHA256
        '{0}  {1}' -f $taskHash.Hash.ToLowerInvariant(), [IO.Path]::GetFileName($_)
    } | Set-Content -LiteralPath (Join-Path $taskOutput "SHA256-Windows-$taskVersion.txt") -Encoding ascii
    Write-Output "Готовы установщик и переносимая Windows-сборка: $taskOutput"
} finally {
    $env:FLUTTER_WINDOWS = $taskPreviousWindows
    Pop-Location
}
