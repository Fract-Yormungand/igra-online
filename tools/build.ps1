# Windows build for sharing: export exe+pck, copy handout, pack zip.
# Run from anywhere:  powershell -NoProfile -ExecutionPolicy Bypass -File tools/build.ps1
param(
    [string]$Godot = "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe",
    [string]$Preset = "Windows Desktop",
    [string]$OutDir = "build\windows",
    [string]$Zip = "build\IgraOnline-windows.zip"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    if (-not (Test-Path $Godot)) { throw "Godot not found: $Godot" }
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Zip) | Out-Null

    $exe = Join-Path $OutDir "IgraOnline.exe"
    $pck = Join-Path $OutDir "IgraOnline.pck"
    # Старые файлы убираем, иначе непонятно, свежая это сборка или прошлая.
    Remove-Item $exe, $pck -Force -ErrorAction SilentlyContinue
    # Имя пресета содержит пробел, а Start-Process не добавляет кавычки сам.
    $argLine = '--headless --path . --export-release "' + $Preset + '" "' + $exe + '"'
    $proc = Start-Process -FilePath $Godot -ArgumentList $argLine -NoNewWindow -Wait -PassThru
    if ($proc.ExitCode -ne 0) { throw "export failed, exit code $($proc.ExitCode)" }
    if (-not (Test-Path $exe) -or -not (Test-Path $pck)) { throw "export produced no exe/pck" }

    Copy-Item -Path "docs\handout\*.txt" -Destination $OutDir -Force

    if (Test-Path $Zip) { Remove-Item $Zip -Force }
    Compress-Archive -Path (Join-Path $OutDir "*") -DestinationPath $Zip -Force

    Get-ChildItem $OutDir | ForEach-Object { "{0,-24} {1}" -f $_.Name, $_.Length }
    $packed = Get-Item $Zip
    "ZIP {0} {1}" -f $packed.Name, $packed.Length
}
finally { Pop-Location }
