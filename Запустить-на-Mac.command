#!/bin/bash
cd "$(dirname "$0")"
PORT=8765
if lsof -iTCP:$PORT -sTCP:LISTEN >/dev/null 2>&1; then
  open "http://localhost:$PORT"
  exit 0
fi
nohup python3 -m http.server "$PORT" >/tmp/tutor-desk-web-server.log 2>&1 &
sleep 1
open "http://localhost:$PORT"
echo "TUTOR DESK открыт в браузере: http://localhost:$PORT"
echo "Сервер работает в фоне. Чтобы остановить его, выполните: pkill -f 'http.server 8765'"
