#!/bin/bash
set -euo pipefail
/root/claude-heartbeat/sync-memory.sh

MEMORY_DIR="/root/claude-memory"
LOG_DIR="$MEMORY_DIR/logs"
PROJECTS_DIR="/root/projects"
TODAY=$(date +%Y-%m-%d)
NOW=$(date +%H:%M)
LOG_FILE="$LOG_DIR/$TODAY.md"
LAST_SCAN="/root/claude-heartbeat/last-scan"

mkdir -p "$LOG_DIR"
if [ ! -f "$LOG_FILE" ]; then
  echo "# $TODAY" > "$LOG_FILE"
  echo "" >> "$LOG_FILE"
fi

# Fichiers modifies depuis le dernier scan
MODIFIED=""
if [ -f "$LAST_SCAN" ]; then
  MODIFIED=$(find "$PROJECTS_DIR" -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.tsx" -o -name "*.mq5" -o -name "*.mqh" -o -name "*.css" -o -name "*.html" -o -name "*.json" -o -name "*.md" \) -newer "$LAST_SCAN" 2>/dev/null | sed "s|$PROJECTS_DIR/||" | head -20 || true)
else
  MODIFIED=$(find "$PROJECTS_DIR" -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.tsx" -o -name "*.mq5" -o -name "*.mqh" \) -mmin -60 2>/dev/null | sed "s|$PROJECTS_DIR/||" | head -20 || true)
fi
touch "$LAST_SCAN"

# Git status rapide
GIT_STATUS=""
for dir in "$PROJECTS_DIR"/*/; do
  if [ -d "$dir/.git" ]; then
    PROJECT_NAME=$(basename "$dir")
    UNCOMMITTED=$(cd "$dir" && git status --short 2>/dev/null | wc -l || echo "0")
    LAST_COMMIT=$(cd "$dir" && git log -1 --oneline --format="%s (%cr)" 2>/dev/null || echo "aucun")
    GIT_STATUS="$GIT_STATUS
$PROJECT_NAME: $UNCOMMITTED non commites, dernier: $LAST_COMMIT"
  fi
done

PROMPT="Tu es le cerveau autonome de Pierre. Il est $NOW (Europe/Paris). Heartbeat.

=== FICHIERS MODIFIES DEPUIS DERNIER SCAN ===
${MODIFIED:-Aucun}

=== GIT STATUS ===
$GIT_STATUS

=== MEMOIRE ===
$(cat "$MEMORY_DIR/MEMORY.md" 2>/dev/null)

Tu dois faire 2 choses :

1. ANALYSE : Ecris un resume en UNE phrase de l etat des projets. Si rien n a change, dis RAS. Si activite, dis quels fichiers dans quel projet.

2. MEMOIRE : Si un projet a change de statut, utilise le tool Edit pour mettre a jour le fichier project_*.md correspondant dans $MEMORY_DIR. Si rien n a change, ne fais rien.

Reponds UNIQUEMENT avec le resume en une phrase."

# Claude analyse et met a jour la memoire si besoin
RESULT=$(timeout 180 claude -p "$PROMPT" \
  --allowedTools "Read,Write,Edit" \
  --max-turns 10 \
  2>/dev/null || echo "ERREUR: timeout")

# Bash ecrit le log (fiable a 100%)
echo "" >> "$LOG_FILE"
echo "## $NOW [heartbeat] — $RESULT" >> "$LOG_FILE"

/root/claude-heartbeat/sync-memory.sh
/root/claude-heartbeat/notify.sh "$LOG_FILE" heartbeat
