# Снимки экрана для ручной проверки вида и интерфейса. Без -Menu поднимает
# игру сервером, добывает ресурс клавишей E и открывает сумку клавишей Tab.
# Запуск: powershell -ExecutionPolicy Bypass -File tools/screenshot.ps1 [-Menu]

param(
    [int]$Port = 7700,
    [switch]$Menu
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$native = @"
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr hWnd);
[DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, System.UIntPtr extra);
"@
$win32 = Add-Type -MemberDefinition $native -Name "Win32Keys" -Namespace "IgraOnline" -PassThru

$godot = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe"
if (-not (Test-Path $godot)) {
    throw "Godot не найден: $godot"
}

$root = Split-Path -Parent $PSScriptRoot
$bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
# Снимки кладём во временную папку, а не в проект: иначе Godot тянет их в
# импорт, а в репозитории появляется мусор.
$shots = Join-Path $env:TEMP "igra-online-shots"
if (-not (Test-Path $shots)) { New-Item -ItemType Directory -Path $shots | Out-Null }

function Save-Shot([string]$path) {
    $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
    Write-Host "Снимок: $path"
}

function Send-Key([int]$virtualKey) {
    $win32::keybd_event([byte]$virtualKey, 0, 0, [System.UIntPtr]::Zero)
    Start-Sleep -Milliseconds 60
    $win32::keybd_event([byte]$virtualKey, 0, 2, [System.UIntPtr]::Zero)
    Start-Sleep -Milliseconds 180
}

$gameArgs = @("--path", ".", "--", "--server", "$Port")
if ($Menu) {
    $gameArgs = @("--path", ".")
}

$game = Start-Process -FilePath $godot -ArgumentList $gameArgs `
    -WorkingDirectory $root -PassThru

Start-Sleep -Seconds 10
$game.Refresh()
$win32::SetForegroundWindow($game.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 500
Save-Shot (Join-Path $shots "shot-play.png")

if (-not $Menu) {
    # E — добыча дерева рядом со спавном, три удара на дерево.
    Send-Key 0x45
    Send-Key 0x45
    Send-Key 0x45
    Start-Sleep -Milliseconds 500
    Save-Shot (Join-Path $shots "shot-harvest.png")

    # C — окно статуса: здоровье, запас сил, характеристики.
    Send-Key 0x43
    Start-Sleep -Seconds 1
    Save-Shot (Join-Path $shots "shot-stats.png")
    Send-Key 0x43
    Start-Sleep -Milliseconds 400

    # Tab — сумка.
    Send-Key 0x09
    Start-Sleep -Seconds 1
    Save-Shot (Join-Path $shots "shot-inventory.png")
}

Start-Sleep -Milliseconds 300
if (-not $game.HasExited) {
    Stop-Process -Id $game.Id -Force
}
