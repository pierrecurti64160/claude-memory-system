#!/bin/bash
# Envoie une notification Telegram
source /root/claude-heartbeat/telegram.sh

LOG_FILE="$1"
NOW=$(date +%H:%M)
TYPE="${2:-heartbeat}"

# Extraire le dernier bloc summary (tout apres la derniere ligne [summary])
extract_last_summary() {
  local file="$1"
  FILE="$file" python3 -c "
import os, sys
lines = open(os.environ['FILE']).readlines()
last_idx = -1
for i, line in enumerate(lines):
    if '[summary]' in line:
        last_idx = i
if last_idx >= 0:
    block = []
    for line in lines[last_idx+1:]:
        if line.startswith('## ') and '[summary]' not in line:
            break
        block.append(line.rstrip())
    print('\n'.join(block).strip()[:3800])
" 2>/dev/null
}

# Extraire la derniere entree du log a l heure NOW
extract_last_entry() {
  local file="$1"
  FILE="$file" NOW="$NOW" python3 -c "
import os, sys
lines = open(os.environ['FILE']).readlines()
now = os.environ['NOW']
last_idx = -1
for i, line in enumerate(lines):
    if line.startswith('## ' + now):
        last_idx = i
if last_idx >= 0:
    block = []
    for line in lines[last_idx:]:
        if line.startswith('## ') and lines.index(line) > last_idx:
            break
        block.append(line.rstrip())
    print('\n'.join(block).strip()[:3800])
" 2>/dev/null
}

case "$TYPE" in
  briefing)
    ENTRY=$(extract_last_entry "$LOG_FILE")
    [ -n "$ENTRY" ] && send_message "Briefing matinal

$ENTRY"
    ;;
  summary)
    SUMMARY=$(extract_last_summary "$LOG_FILE")
    [ -n "$SUMMARY" ] && send_message "Resume du jour

$SUMMARY"
    ;;
  heartbeat)
    ENTRY=$(extract_last_entry "$LOG_FILE")
    if [ -n "$ENTRY" ] && ! echo "$ENTRY" | grep -qi "RAS"; then
      send_message "Heartbeat

$ENTRY"
    fi
    ;;
esac
