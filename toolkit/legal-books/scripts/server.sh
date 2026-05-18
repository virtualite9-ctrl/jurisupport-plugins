#!/usr/bin/env bash
# Manage legal-books search server (default port 18766)

set -euo pipefail

ROOT="$HOME/legal-books"
VENV="$ROOT/.venv/bin/activate"
PIDFILE="$ROOT/logs/server.pid"
LOGFILE="$ROOT/logs/server.log"
SECRETS="$HOME/.jurisupport/secrets.env"
if [[ -f "$SECRETS" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$SECRETS"
  set +a
fi
PORT="${JURISUPPORT_LEGAL_BOOKS_PORT:-18766}"

start() {
  if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "Server already running (PID $(cat "$PIDFILE"))"
    return
  fi
  # shellcheck disable=SC1090
  source "$VENV"
  nohup python3 "$ROOT/server/server.py" >> "$LOGFILE" 2>&1 &
  echo $! > "$PIDFILE"
  echo "Server started (PID $!). Log: $LOGFILE"
}

stop() {
  if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    kill "$(cat "$PIDFILE")"
    rm -f "$PIDFILE"
    echo "Server stopped"
  else
    echo "Server not running"
  fi
}

status() {
  if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "Running (PID $(cat "$PIDFILE"))"
    curl -s "http://localhost:${PORT}/health" || true
  else
    echo "Not running"
  fi
}

case "${1:-status}" in
  start)   start ;;
  stop)    stop ;;
  restart) stop; sleep 1; start ;;
  status)  status ;;
  *) echo "Usage: $0 {start|stop|restart|status}"; exit 1 ;;
esac
