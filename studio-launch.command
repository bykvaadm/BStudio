#!/bin/bash
# Двойной клик → поднимает локальный сервер в папке slides/ и открывает BStudio.
# Камера в браузере работает только через http://localhost (не file://), поэтому так.
cd "$(dirname "$0")" || exit 1
PORT=8000
python3 -m http.server "$PORT" >/dev/null 2>&1 &
SRV=$!
sleep 1
open "http://localhost:${PORT}/studio.html"
echo "BStudio открыта: http://localhost:${PORT}/studio.html"
echo "Это окно держит сервер. Закончишь — Ctrl+C или закрой окно."
wait $SRV
