@echo off
rem ===========================================================================
rem  Запуск BStudio на Windows. Двойной клик по этому файлу — и студия открыта.
rem
rem  Файл один, но внутри две части: сверху обычный батник (его выполняет cmd.exe),
rem  снизу — код на PowerShell. Батник ничего не делает сам: он передаёт
rem  PowerShell'у этот же файл, и тот выполняет всё, что лежит после метки.
rem  Так сделано потому, что по двойному клику .ps1 открывается в блокноте,
rem  а .cmd запускается — а держать два файла рядом неудобно.
rem ===========================================================================
chcp 65001 >nul
set "BSTUDIO_SELF=%~f0"
set "BSTUDIO_DIR=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$m='#'+'PS-CODE-BELOW'; $s=[IO.File]::ReadAllText($env:BSTUDIO_SELF,[Text.Encoding]::UTF8); Invoke-Expression $s.Substring($s.IndexOf($m))"
if errorlevel 1 pause
exit /b %errorlevel%

#PS-CODE-BELOW
<#
    Запуск BStudio
    --------------
    Поднимает локальный сервер в той папке, где лежит этот файл (slides/),
    и открывает студию в Chrome.
    Камера в браузере работает только через http://localhost (не через file://), поэтому так.
#>

$ErrorActionPreference = 'Stop'

# ---- что и откуда ---------------------------------------------------------
# Раздаём папку, где лежит сам файл: перенесли её целиком — ничего править не надо.
$Target = $env:BSTUDIO_DIR
$Page   = 'studio.html'

# ---- оформление окна ------------------------------------------------------
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }
try { $Host.UI.RawUI.WindowTitle = 'BStudio работает — не закрывайте это окно' } catch { }

function Say  ($t) { Write-Host "     $t" -ForegroundColor Gray }
function Step ($t) { Write-Host ''; Write-Host "  $t" -ForegroundColor Cyan }
function Ok   ($t) { Write-Host ''; Write-Host "  $t" -ForegroundColor Green }
function Bad  ($t) { Write-Host ''; Write-Host "  $t" -ForegroundColor Red }

function Finish ($code) {
    Write-Host ''
    Write-Host '  ----------------------------------------------------------------' -ForegroundColor DarkGray
    Write-Host '  Нажмите Enter, чтобы закрыть это окно.' -ForegroundColor DarkGray
    try { Read-Host | Out-Null } catch { }
    exit $code
}

$types = @{
    '.html' = 'text/html; charset=utf-8'; '.htm' = 'text/html; charset=utf-8'
    '.js'   = 'text/javascript; charset=utf-8'; '.mjs' = 'text/javascript; charset=utf-8'
    '.css'  = 'text/css; charset=utf-8'
    '.json' = 'application/json; charset=utf-8'; '.md' = 'text/plain; charset=utf-8'
    '.txt'  = 'text/plain; charset=utf-8'; '.svg' = 'image/svg+xml'
    '.png'  = 'image/png'; '.jpg' = 'image/jpeg'; '.jpeg' = 'image/jpeg'; '.gif' = 'image/gif'
    '.webp' = 'image/webp'; '.avif' = 'image/avif'; '.bmp' = 'image/bmp'; '.ico' = 'image/x-icon'
    '.pdf'  = 'application/pdf'; '.webm' = 'video/webm'; '.mp4' = 'video/mp4'
    '.woff2' = 'font/woff2'; '.woff' = 'font/woff'
}

Clear-Host
Write-Host ''
Write-Host '  ================================================================' -ForegroundColor DarkCyan
Write-Host '                         B S t u d i o'                             -ForegroundColor White
Write-Host '  ================================================================' -ForegroundColor DarkCyan

$listener = $null

try {
    # ---- 1. Проверяем, что студия на месте --------------------------------
    Step '[1 из 3]  Проверяю студию...'

    $root = $null
    if ($Target -and (Test-Path -LiteralPath $Target)) { $root = (Resolve-Path -LiteralPath $Target).Path.TrimEnd('\') }
    if (-not $root -or -not (Test-Path -LiteralPath (Join-Path $root $Page))) {
        throw "Рядом с этим файлом нет $Page. Он должен лежать в папке slides/ — там же, где studio.html."
    }
    Say "Студия найдена: $root"

    # ---- 2. Поднимаем локальный сервер ------------------------------------
    Step '[2 из 3]  Запускаю студию...'

    $port = $null
    foreach ($p in 8000..8020) {
        try {
            $probe = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, $p)
            $probe.Start(); $probe.Stop()
            $port = $p; break
        } catch { }
    }
    if (-not $port) { throw 'Не нашлось свободного порта (8000-8020). Помогает перезагрузка компьютера.' }

    $listener = New-Object Net.HttpListener
    $listener.Prefixes.Add("http://localhost:$port/")
    $listener.Start()

    $url = "http://localhost:$port/$Page"

    # ---- 3. Открываем Chrome ----------------------------------------------
    Step '[3 из 3]  Открываю Chrome...'

    $chrome = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($chrome) {
        Start-Process -FilePath $chrome -ArgumentList '--new-window', $url | Out-Null
        Say 'Chrome открыт.'
    } else {
        Start-Process $url | Out-Null
        Say 'Chrome на компьютере не найден — открыл в обычном браузере.'
        Say 'Студия рассчитана на Chrome: если камера не заработает, установите его.'
    }

    Ok 'СТУДИЯ РАБОТАЕТ.'
    Say "Адрес студии: $url"
    Write-Host ''
    Write-Host '  ЭТО ОКНО ЗАКРЫВАТЬ НЕЛЬЗЯ — пока оно открыто, работает студия.' -ForegroundColor Yellow
    Say 'Закончите запись — просто закройте это окно, студия выключится.'
    Say 'Если вкладка в браузере случайно закрылась — адрес выше можно открыть заново.'
    Write-Host ''

    # ---- Сервер: раздаёт файлы студии из папки ----------------------------
    while ($listener.IsListening) {
        $ctx = $listener.GetContext()
        try {
            $rel = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath).TrimStart('/')
            if (-not $rel) { $rel = $Page }
            $file = [IO.Path]::GetFullPath((Join-Path $root ($rel -replace '/', '\')))

            if ($file.StartsWith($root, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $file -PathType Leaf)) {
                $bytes = [IO.File]::ReadAllBytes($file)
                $ext = [IO.Path]::GetExtension($file).ToLower()
                $ctx.Response.ContentType = $(if ($types.ContainsKey($ext)) { $types[$ext] } else { 'application/octet-stream' })
                $ctx.Response.Headers.Add('Cache-Control', 'no-store')   # чтобы после обновления бралась новая версия
                $ctx.Response.ContentLength64 = $bytes.Length
                $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
            } else {
                $ctx.Response.StatusCode = 404
            }
        } catch {
            try { $ctx.Response.StatusCode = 500 } catch { }
        } finally {
            try { $ctx.Response.Close() } catch { }
        }
    }

} catch {
    Bad 'НЕ ПОЛУЧИЛОСЬ ЗАПУСТИТЬ СТУДИЮ.'
    Write-Host ''
    Say 'Что именно пошло не так:'
    Write-Host "     $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host ''
    Say 'Что можно сделать:'
    Say '  1. Закройте все окна студии и запустите ещё раз.'
    Say '  2. Проверьте, что файл лежит в папке slides/ рядом со studio.html.'
    Say '  3. Если не помогло — сфотографируйте это окно и покажите тому, кто'
    Say '     давал вам этот файл.'
    Finish 1
} finally {
    if ($listener) { try { $listener.Stop(); $listener.Close() } catch { } }
}
