#!/bin/bash
set -euo pipefail
export TZ=Europe/Paris

# ---------------------------------------------------------------------------
# Debrief interactif — pose des questions ciblees a Pierre en fin de journee
# ---------------------------------------------------------------------------
# Lance par cron toutes les 30 min entre 18h et 20h30 Paris.
#
# Logique :
#  - Si 18h00 (premiere execution) : genere et envoie les questions
#  - Sinon si debrief ouvert : envoie un rappel doux
#  - Si 21h (appel manuel par summary.sh) : cloture force
# ---------------------------------------------------------------------------

/root/claude-heartbeat/sync-memory.sh

MEMORY_DIR="/root/claude-memory"
LOG_DIR="$MEMORY_DIR/logs"
PROJECTS_DIR="/root/projects"
VAULT_DIR="/root/obsidian-vault"
DAILY_DIR="$VAULT_DIR/5 TOOLS/Notes quotidienne"
DEBRIEF_DIR="/root/claude-heartbeat/debriefs"
TODAY=$(date +%Y-%m-%d)
NOW=$(date +%H:%M)
HOUR=$(date +%H)
MINUTE=$(date +%M)
DAILY_NOTE="$DAILY_DIR/$TODAY.md"
DEBRIEF_FILE="$DEBRIEF_DIR/$TODAY.md"
LOG_FILE="$LOG_DIR/$TODAY.md"

mkdir -p "$DEBRIEF_DIR" "$LOG_DIR"

source /root/claude-heartbeat/telegram.sh

# ---------------------------------------------------------------------------
# Mode 1 — Lancement initial (18h00)
# ---------------------------------------------------------------------------
if [ "$HOUR" = "18" ] && [ "$MINUTE" = "00" ] && [ ! -f "$DEBRIEF_FILE" ]; then

  # Collecter le contexte
  COMMITS_TODAY=""
  for dir in "$PROJECTS_DIR"/*/; do
    if [ -d "$dir/.git" ]; then
      PROJECT_NAME=$(basename "$dir")
      COMMITS=$(cd "$dir" && git log --since="$TODAY 00:00" --oneline 2>/dev/null || true)
      if [ -n "$COMMITS" ]; then
        COMMITS_TODAY="$COMMITS_TODAY
$PROJECT_NAME: $COMMITS"
      fi
    fi
  done

  DAILY_NOTE_CONTENT=""
  if [ -f "$DAILY_NOTE" ]; then
    DAILY_NOTE_CONTENT=$(cat "$DAILY_NOTE")
  fi

  TODAY_LOG=""
  if [ -f "$LOG_FILE" ]; then
    TODAY_LOG=$(cat "$LOG_FILE")
  fi

  PROMPT="Tu es le Chief of Staff de Pierre. Il est 18h, fin de journee.

Ton job : identifier les TROUS NOIRS — ce que le systeme ne sait PAS encore — et poser 3 a 5 questions ciblees a Pierre. Il repondra en vocal.

=== DAILY NOTE DU MATIN ===
$DAILY_NOTE_CONTENT

=== COMMITS DU JOUR ===
${COMMITS_TODAY:-Aucun commit}

=== LOG DU JOUR ===
$TODAY_LOG

=== PRIMER ===
$(cat $MEMORY_DIR/primer.md 2>/dev/null)

Identifie :
1. Les priorites du matin non cochees — est-ce fait/pas fait/autre ?
2. Les projets qui ont bouge (commits) sans explication dans les logs
3. Les promesses attendues (ex: Celia envoie contenu, RDV a caler)
4. Les gens dont Pierre attend une reponse
5. Les deadlines qui approchent (robot FTMO, deplacements, etc.)

Produis UN message Telegram avec 3 a 5 questions numerotees. Ton : direct, amical, pas de blabla.
Format :
Debrief du jour. Reponds en vocal quand tu as 2 min, une question a la fois ou tout en bloc.

1. [question courte et precise]
2. [question]
3. [question]

Quand t'as fini, tape fin.

IMPORTANT : la reponse que tu produis SERA envoyee telle quelle sur Telegram. Pas de markdown, pas de backticks."

  QUESTIONS=$(timeout 180 claude -p "$PROMPT" \
    --allowedTools "Read" \
    --max-turns 5 \
    2>/dev/null || echo "ERREUR: timeout lors de la generation")

  # Creer le fichier debrief avec les questions
  cat > "$DEBRIEF_FILE" <<EOF
---
date: $TODAY
status: open
started_at: $NOW
reminders: 0
---

# Debrief $TODAY

## Questions posees a 18h
$QUESTIONS

## Reponses de Pierre
EOF

  # Envoyer sur Telegram
  send_message "$QUESTIONS"

  # Logger
  echo "" >> "$LOG_FILE"
  echo "## $NOW [debrief] — Debrief envoye, $(echo "$QUESTIONS" | grep -c '^[0-9]') questions" >> "$LOG_FILE"

  exit 0
fi

# ---------------------------------------------------------------------------
# Mode 2 — Rappel (si debrief ouvert et heure entre 18h30 et 20h30)
# ---------------------------------------------------------------------------
if [ -f "$DEBRIEF_FILE" ]; then
  STATUS=$(grep -E "^status:" "$DEBRIEF_FILE" | head -1 | awk '{print $2}')

  if [ "$STATUS" = "open" ]; then
    # Verifier si Pierre a deja repondu (presence de "### Reponse" dans le fichier)
    REPONSES=$(grep -c "^### Reponse" "$DEBRIEF_FILE" 2>/dev/null || echo "0")
    REPONSES="${REPONSES//[^0-9]/}"
    REPONSES="${REPONSES:-0}"
    REMINDERS=$(grep -E "^reminders:" "$DEBRIEF_FILE" | head -1 | awk '{print $2}')
    REMINDERS="${REMINDERS:-0}"

    if [ "$REPONSES" -eq 0 ] && [ "$REMINDERS" -lt 5 ]; then
      NEW_REMINDERS=$((REMINDERS + 1))
      # Mettre a jour le compteur de rappels
      sed -i "s/^reminders: $REMINDERS/reminders: $NEW_REMINDERS/" "$DEBRIEF_FILE"

      case "$NEW_REMINDERS" in
        1) MSG="Rappel debrief — tes questions de 18h attendent tes reponses vocales." ;;
        2) MSG="2e rappel — 2 min pour repondre au debrief du jour ?" ;;
        3) MSG="3e rappel — ca te prendra 3 min max. Reponds en vocal." ;;
        4) MSG="Avant-dernier rappel — a 21h je cloture avec ce que j'ai." ;;
        5) MSG="Dernier rappel — 30 min avant cloture automatique." ;;
      esac

      send_message "$MSG"

      echo "" >> "$LOG_FILE"
      echo "## $NOW [debrief] — Rappel $NEW_REMINDERS envoye" >> "$LOG_FILE"
    fi
  fi
fi

exit 0
