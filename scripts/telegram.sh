#!/bin/bash
# Telegram bot utilities
BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-8647578786:AAHf8sknMnDr0dAWWAk0dJLCrHZot3rRQ-U}"
CHAT_ID="${TELEGRAM_CHAT_ID:-2002390235}"
API="https://api.telegram.org/bot$BOT_TOKEN"

send_message() {
  local text="$1"
  # Telegram max 4096 chars, tronquer si besoin
  text="${text:0:4000}"
  curl -s -X POST "$API/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d text="$text" \
    -d disable_web_page_preview=true > /dev/null 2>&1
}

get_updates() {
  local offset="${1:-0}"
  curl -s "$API/getUpdates?offset=$offset&timeout=30"
}
