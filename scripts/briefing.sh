#!/bin/bash
set -euo pipefail
/root/claude-heartbeat/sync-memory.sh

MEMORY_DIR="/root/claude-memory"
LOG_DIR="$MEMORY_DIR/logs"
PROJECTS_DIR="/root/projects"
VAULT_DIR="/root/obsidian-vault"
TODAY=$(date +%Y-%m-%d)
YESTERDAY=$(date -d "yesterday" +%Y-%m-%d)
NOW=$(date +%H:%M)
LOG_FILE="$LOG_DIR/$TODAY.md"

mkdir -p "$LOG_DIR"
if [ ! -f "$LOG_FILE" ]; then
  echo "# $TODAY" > "$LOG_FILE"
  echo "" >> "$LOG_FILE"
fi

GIT_ACTIVITY=""
for dir in "$PROJECTS_DIR"/*/; do
  if [ -d "$dir/.git" ]; then
    PROJECT_NAME=$(basename "$dir")
    COMMITS=$(cd "$dir" && git log --since="$YESTERDAY 00:00" --oneline --all 2>/dev/null || true)
    UNCOMMITTED=$(cd "$dir" && git status --short 2>/dev/null | wc -l || echo "0")
    GIT_ACTIVITY="$GIT_ACTIVITY
$PROJECT_NAME: ${COMMITS:-aucun commit}, $UNCOMMITTED non commites"
  fi
done

MODIFIED=$(find "$PROJECTS_DIR" -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.tsx" -o -name "*.mq5" -o -name "*.mqh" \) -newer "$LOG_DIR/$YESTERDAY.md" 2>/dev/null | sed "s|$PROJECTS_DIR/||" | head -20 || true)

VAULT_RECENT=""
if [ -d "$VAULT_DIR" ]; then
  VAULT_RECENT=$(find "$VAULT_DIR" -name "*.md" -mtime -2 2>/dev/null | sed "s|$VAULT_DIR/||" | head -15 || true)
fi

ABOUT_ME=""
if [ -f "$VAULT_DIR/about-me.md" ]; then
  ABOUT_ME=$(cat "$VAULT_DIR/about-me.md")
fi

PROMPT="Tu es le cerveau autonome de Pierre. Il est $NOW (Europe/Paris). Briefing matinal.

=== LOGS HIER ===
$(cat "$LOG_DIR/$YESTERDAY.md" 2>/dev/null || echo "Pas de log hier")

=== GIT ===
$GIT_ACTIVITY

=== FICHIERS MODIFIES HIER ===
${MODIFIED:-Aucun}

=== NOTES OBSIDIAN RECENTES ===
${VAULT_RECENT:-Aucune}

=== ABOUT-ME ===
${ABOUT_ME:-Non disponible}

=== MEMOIRE ===
$(cat "$MEMORY_DIR/MEMORY.md" 2>/dev/null)

=== PRIMER ===
$(cat "$MEMORY_DIR/primer.md" 2>/dev/null)

Tu dois faire 2 choses :

1. BRIEFING : Ecris un briefing structure :
- Hier : resume activite (ATTENTION : verifie s il y a des entrees dans le log d hier APRES le [summary] de 19h/20h — si oui, signale-les en premier car elles n ont pas ete couvertes par le resume)
- Par projet : statut
- Taches ouvertes
- Priorite du jour

2. MEMOIRE : Utilise Edit pour mettre a jour les project_*.md et user_pierre.md dans $MEMORY_DIR si necessaire.

Reponds UNIQUEMENT avec le briefing."

RESULT=$(timeout 240 claude -p "$PROMPT" \
  --allowedTools "Read,Write,Edit" \
  --max-turns 12 \
  2>/dev/null || echo "ERREUR: timeout")

echo "" >> "$LOG_FILE"
echo "## $NOW [briefing] — Briefing matinal" >> "$LOG_FILE"
echo "$RESULT" >> "$LOG_FILE"

/root/claude-heartbeat/sync-memory.sh
/root/claude-heartbeat/notify.sh "$LOG_FILE" briefing
