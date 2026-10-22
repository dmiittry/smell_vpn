# Скачать закреплённое официальное ядро и проверить SHA-256 перед упаковкой.
$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$taskVersion = '1.13.9'
$taskArchive = "sing-box-$taskVersion-windows-amd64.zip"
$taskBase = "https://github.com/SagerNet/sing-box/releases/download/v$taskVersion"
$taskCache = Join-Path $taskRoot 'third_party/windows/downloads'
$taskCore = Join-Path $taskRoot 'third_party/windows/core'
New-Item -ItemType Directory -Path $taskCache,$taskCore -Force | Out-Null
$taskZip = Join-Path $taskCache $taskArchive
$taskRelease = Invoke-RestMethod -Uri "https://api.github.com/repos/SagerNet/sing-box/releases/tags/v$taskVersion"
$taskAsset = @($taskRelease.assets | Where-Object { $_.name -eq $taskArchive })
if ($taskAsset.Count -ne 1 -or $taskAsset[0].digest -notmatch '^sha256:[0-9a-f]{64}$') {
    throw 'Официальный SHA-256 архива не найден в метаданных GitHub Release.'
}
if (-not (Test-Path -LiteralPath $taskZip)) {
    Invoke-WebRequest -Uri "$taskBase/$taskArchive" -OutFile $taskZip
}
$taskExpected = $taskAsset[0].digest.Substring(7).ToLowerInvariant()
$taskActual = (Get-FileHash -LiteralPath $taskZip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($taskExpected -ne $taskActual) { throw 'SHA-256 не совпадает. Ядро не будет установлено.' }
$taskExtract = Join-Path $taskCache "extracted-$taskVersion"
Expand-Archive -LiteralPath $taskZip -DestinationPath $taskExtract -Force
$taskExe = Get-ChildItem -LiteralPath $taskExtract -Recurse -Filter sing-box.exe | Select-Object -First 1
if (-not $taskExe) { throw 'В официальном архиве отсутствует sing-box.exe.' }
Copy-Item -LiteralPath $taskExe.FullName -Destination (Join-Path $taskCore 'sing-box.exe') -Force
Get-ChildItem -LiteralPath $taskExe.DirectoryName -Filter '*.dll' | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $taskCore -Force
}
Copy-Item -LiteralPath (Join-Path $taskRoot 'LICENSE') -Destination (Join-Path $taskCore 'LICENSE') -Force
Copy-Item -LiteralPath (Join-Path $taskExe.DirectoryName 'LICENSE') -Destination (Join-Path $taskCore 'SING_BOX_LICENSE.txt') -Force
"sing-box $taskVersion`nSHA256: $taskActual`nИсточник: $taskBase" | Set-Content -LiteralPath (Join-Path $taskCore 'SOURCE.txt') -Encoding utf8
Write-Output "Официальное ядро sing-box $taskVersion подготовлено и проверено."
