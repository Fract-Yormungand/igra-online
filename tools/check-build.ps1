# Проверка собранного клиента: поднимает сервер из проекта, подключает к нему
# сборку из build/windows и смотрит, дошла ли регистрация игрока до сервера.
# Запуск: powershell -ExecutionPolicy Bypass -File tools/check-build.ps1 -Port 7820

param(
    [int]$Port = 7820
)

$ErrorActionPreference = "Stop"

$godot = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
if (-not (Test-Path $godot)) {
    throw "Godot не найден: $godot"
}

$root = Split-Path -Parent $PSScriptRoot
$exe = Join-Path $root "build\windows\IgraOnline.exe"
if (-not (Test-Path $exe)) {
    throw "Нет сборки: $exe. Сначала godot --headless --path . --export-release 'Windows Desktop' build/windows/IgraOnline.exe"
}

$serverLog = Join-Path $env:TEMP "igra-online-build-server.log"
$serverErr = Join-Path $env:TEMP "igra-online-build-server.err.log"
$clientLog = Join-Path $env:TEMP "igra-online-build-client.log"
$clientErr = Join-Path $env:TEMP "igra-online-build-client.err.log"

foreach ($file in @($serverLog, $serverErr, $clientLog, $clientErr)) {
    if (Test-Path $file) { Remove-Item $file -Force }
}

$server = Start-Process -FilePath $godot `
    -ArgumentList "--headless", "--path", ".", "--", "--server", "$Port" `
    -WorkingDirectory $root `
    -PassThru -RedirectStandardOutput $serverLog -RedirectStandardError $serverErr `
    -WindowStyle Hidden

Start-Sleep -Seconds 6

$client = Start-Process -FilePath $exe `
    -ArgumentList "--headless", "--", "--client", "127.0.0.1", "$Port" `
    -WorkingDirectory (Split-Path -Parent $exe) `
    -PassThru -RedirectStandardOutput $clientLog -RedirectStandardError $clientErr `
    -WindowStyle Hidden

Start-Sleep -Seconds 10

Stop-Process -Id $client.Id -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Stop-Process -Id $server.Id -Force -ErrorAction SilentlyContinue

Write-Host "--- лог сборки ---"
if (Test-Path $clientLog) { Get-Content $clientLog -Encoding UTF8 }
if ((Test-Path $clientErr) -and (Get-Item $clientErr).Length -gt 0) {
    Write-Host "--- ошибки сборки ---"
    Get-Content $clientErr -Encoding UTF8
}

Write-Host "--- лог сервера ---"
if (Test-Path $serverLog) { Get-Content $serverLog -Encoding UTF8 }

$joined = $false
if (Test-Path $serverLog) {
    foreach ($line in (Get-Content $serverLog -Encoding UTF8)) {
        if ($line -like "*player_joined*") { $joined = $true }
    }
}

if ($joined) {
    Write-Host "VERDICT: сборка подключилась к серверу"
    exit 0
}

Write-Host "VERDICT: сборка не подключилась"
exit 1
