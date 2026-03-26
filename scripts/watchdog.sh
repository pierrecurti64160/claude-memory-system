#!/bin/bash
# Watchdog : alerte si aucun heartbeat depuis 1h
source /root/claude-heartbeat/telegram.sh

LOG_DIR="/root/claude-memory/logs"
TODAY=$(date +%Y-%m-%d)
LOG_FILE="$LOG_DIR/$TODAY.md"

if [ ! -f "$LOG_FILE" ]; then
  send_message "WATCHDOG: pas de log du jour. Les heartbeats ne tournent pas."
  exit 0
fi

# Derniere modification du log
LAST_MOD=$(stat -c %Y "$LOG_FILE" 2>/dev/null || echo 0)
NOW=$(date +%s)
DIFF=$(( (NOW - LAST_MOD) / 60 ))

if [ "$DIFF" -gt 75 ]; then
  send_message "WATCHDOG: aucun heartbeat depuis ${DIFF} minutes. Verifier les crons."
fi
