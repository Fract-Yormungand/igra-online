# Сквозной тест сети: поднимает сервер в отдельном процессе, запускает
# клиента с тестом добычи и печатает логи обеих сторон.
# Вердикт берётся из отчёта клиента: строка "[E2E] проверок: N, провалов: M".
# Запуск: powershell -ExecutionPolicy Bypass -File tools/e2e.ps1 -Port 7788

param(
    [int]$Port = 7788
)

$ErrorActionPreference = "Stop"

$godot = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
if (-not (Test-Path $godot)) {
    throw "Godot не найден: $godot"
}

$root = Split-Path -Parent $PSScriptRoot
$serverLog = Join-Path $env:TEMP "igra-online-server.log"
$serverErr = Join-Path $env:TEMP "igra-online-server.err.log"
$clientLog = Join-Path $env:TEMP "igra-online-client.log"
$clientErr = Join-Path $env:TEMP "igra-online-client.err.log"

foreach ($file in @($serverLog, $serverErr, $clientLog, $clientErr)) {
    if (Test-Path $file) { Remove-Item $file -Force }
}

$server = Start-Process -FilePath $godot `
    -ArgumentList "--headless", "--path", ".", "--", "--server", "$Port" `
    -WorkingDirectory $root `
    -PassThru -RedirectStandardOutput $serverLog -RedirectStandardError $serverErr `
    -WindowStyle Hidden

Start-Sleep -Seconds 6

$client = Start-Process -FilePath $godot `
    -ArgumentList "--headless", "--path", ".", "--", "--e2e", "127.0.0.1", "$Port" `
    -WorkingDirectory $root `
    -PassThru -RedirectStandardOutput $clientLog -RedirectStandardError $clientErr `
    -WindowStyle Hidden

$client.WaitForExit(90000) | Out-Null
if (-not $client.HasExited) {
    Stop-Process -Id $client.Id -Force
}

Start-Sleep -Seconds 1
if (-not $server.HasExited) {
    Stop-Process -Id $server.Id -Force
}

Write-Host "--- клиент ---"
if (Test-Path $clientLog) { Get-Content $clientLog -Encoding UTF8 }
if ((Test-Path $clientErr) -and (Get-Item $clientErr).Length -gt 0) {
    Write-Host "--- ошибки клиента ---"
    Get-Content $clientErr -Encoding UTF8
}

Write-Host "--- сервер ---"
if (Test-Path $serverLog) { Get-Content $serverLog -Encoding UTF8 }
if ((Test-Path $serverErr) -and (Get-Item $serverErr).Length -gt 0) {
    Write-Host "--- ошибки сервера ---"
    Get-Content $serverErr -Encoding UTF8
}

$report = ""
if (Test-Path $clientLog) {
    foreach ($line in (Get-Content $clientLog -Encoding UTF8)) {
        if ($line -like "*RESULT checks=*") {
            $report = $line
        }
    }
}

if ($report -eq "") {
    Write-Host "VERDICT: no client report, test did not run"
    exit 2
}

Write-Host "VERDICT: $report"
if ($report -like "*failures=0") {
    exit 0
}
exit 1
