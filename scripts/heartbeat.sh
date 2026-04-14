#!/bin/bash
set -euo pipefail
export TZ=Europe/Paris

# ---------------------------------------------------------------------------
# Heartbeat intelligent — silencieux sauf si signal detecte
# Appele toutes les 30 min par cron. Ne consomme un appel Claude que si :
#   1. Des fichiers source ont change depuis le dernier scan
#   2. Une deadline dans le primer est a moins de 48h
# Sinon : touch du timestamp et sortie immediate. Zero bruit.
# ---------------------------------------------------------------------------

/root/claude-heartbeat/sync-memory.sh

MEMORY_DIR="/root/claude-memory"
LOG_DIR="$MEMORY_DIR/logs"
PROJECTS_DIR="/root/projects"
TODAY=$(date +%Y-%m-%d)
NOW=$(date +%H:%M)
LOG_FILE="$LOG_DIR/$TODAY.md"
LAST_SCAN="/root/claude-heartbeat/last-scan"
PRIMER="$MEMORY_DIR/primer.md"

mkdir -p "$LOG_DIR"
if [ ! -f "$LOG_FILE" ]; then
  echo "# $TODAY" > "$LOG_FILE"
  echo "" >> "$LOG_FILE"
fi

# --- 1. Detection de fichiers modifies depuis le dernier scan ---

MODIFIED=""
if [ -f "$LAST_SCAN" ]; then
  MODIFIED=$(find "$PROJECTS_DIR" -type f \
    \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.tsx" \
       -o -name "*.mq5" -o -name "*.mqh" -o -name "*.css" -o -name "*.html" \
       -o -name "*.json" -o -name "*.md" \) \
    -newer "$LAST_SCAN" \
    ! -path "*/node_modules/*" \
    ! -path "*/.git/*" \
    ! -path "*/venv/*" \
    ! -path "*/__pycache__/*" \
    2>/dev/null | sed "s|$PROJECTS_DIR/||" | head -30 || true)
else
  # Premier run : ne scanner que la derniere heure
  MODIFIED=$(find "$PROJECTS_DIR" -type f \
    \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.tsx" \
       -o -name "*.mq5" -o -name "*.mqh" \) \
    -mmin -60 \
    ! -path "*/node_modules/*" \
    ! -path "*/.git/*" \
    2>/dev/null | sed "s|$PROJECTS_DIR/||" | head -30 || true)
fi

FILE_COUNT=0
if [ -n "$MODIFIED" ]; then
  FILE_COUNT=$(echo "$MODIFIED" | wc -l | tr -d ' ')
fi

# --- 2. Detection de deadlines imminentes (<48h) ---

DEADLINE_ALERT=""
if [ -f "$PRIMER" ]; then
  # Generer les dates a verifier : aujourd'hui, demain, apres-demain
  CHECK_DATES=""
  for offset in 0 1 2; do
    CHECK_DATES="$CHECK_DATES|$(date -d "+${offset} days" +%Y-%m-%d)"
  done
  CHECK_DATES="${CHECK_DATES:1}"  # Retirer le premier |

  DEADLINE_ALERT=$(grep -iE "(deadline|echeance|livraison|date limite|avant le|pour le|doit etre|du $CHECK_DATES)" "$PRIMER" 2>/dev/null || true)

  # Chercher aussi des dates au format JJ/MM ou JJ-MM dans les 48h
  for offset in 0 1 2; do
    DAY_CHECK=$(date -d "+${offset} days" +%d/%m)
    DAY_CHECK_ALT=$(date -d "+${offset} days" +%d-%m)
    FOUND=$(grep -E "($DAY_CHECK|$DAY_CHECK_ALT)" "$PRIMER" 2>/dev/null || true)
    if [ -n "$FOUND" ]; then
      DEADLINE_ALERT="$DEADLINE_ALERT
$FOUND"
    fi
  done

  DEADLINE_ALERT=$(echo "$DEADLINE_ALERT" | sed '/^$/d' | head -10)
fi

# --- 3. Decision : signal ou silence ---

HAS_SIGNAL=false

if [ "$FILE_COUNT" -gt 0 ]; then
  HAS_SIGNAL=true
fi

if [ -n "$DEADLINE_ALERT" ]; then
  HAS_SIGNAL=true
fi

# Pas de signal → silence total
if [ "$HAS_SIGNAL" = false ]; then
  touch "$LAST_SCAN"
  exit 0
fi

# --- 4. Signal detecte → appel Claude cible ---

# Git status uniquement pour les projets qui ont des fichiers modifies
GIT_STATUS=""
if [ -n "$MODIFIED" ]; then
  # Extraire les noms de projets uniques depuis les fichiers modifies
  CHANGED_PROJECTS=$(echo "$MODIFIED" | cut -d'/' -f1 | sort -u)
  for PROJECT_NAME in $CHANGED_PROJECTS; do
    PROJECT_DIR="$PROJECTS_DIR/$PROJECT_NAME"
    if [ -d "$PROJECT_DIR/.git" ]; then
      UNCOMMITTED=$(cd "$PROJECT_DIR" && git status --short 2>/dev/null | wc -l | tr -d ' ' || echo "0")
      LAST_COMMIT=$(cd "$PROJECT_DIR" && git log -1 --oneline --format="%s (%cr)" 2>/dev/null || echo "aucun")
      GIT_STATUS="$GIT_STATUS
$PROJECT_NAME: $UNCOMMITTED non commites, dernier: $LAST_COMMIT"
    fi
  done
fi

PROMPT="Tu es le Chief of Staff de Pierre. Heartbeat cible — analyse UNIQUEMENT ce qui a change.

Il est $NOW (Europe/Paris), $TODAY.

=== FICHIERS MODIFIES ($FILE_COUNT) ===
${MODIFIED:-Aucun}

=== GIT (projets concernes) ===
${GIT_STATUS:-Aucun changement git}

=== DEADLINES IMMINENTES (<48h) ===
${DEADLINE_ALERT:-Aucune}

=== MEMOIRE ===
$(cat "$MEMORY_DIR/MEMORY.md" 2>/dev/null)

Instructions :
1. Si un projet a change de statut (nouveau deploiement, avancee majeure, regression), mets a jour le project_*.md correspondant dans $MEMORY_DIR avec le tool Edit.
2. Si une deadline est a moins de 48h, signale-la clairement avec [ALERTE DEADLINE].
3. Si un service semble down ou anormal, signale avec [ALERTE SERVICE].
4. Resume en UNE phrase ce qui merite attention. Pas de filler, pas de RAS.

Reponds UNIQUEMENT avec le resume en une phrase (commence par [ALERTE ...] si alerte, sinon juste le resume)."

RESULT=$(timeout 180 claude -p "$PROMPT" \
  --allowedTools "Read,Write,Edit" \
  --max-turns 10 \
  2>/dev/null || echo "ERREUR: timeout ou echec Claude")

touch "$LAST_SCAN"

# --- 5. Log ---

echo "" >> "$LOG_FILE"
echo "## $NOW [heartbeat] — $RESULT" >> "$LOG_FILE"

/root/claude-heartbeat/sync-memory.sh

# --- 6. Notification Telegram uniquement sur alerte ---

if echo "$RESULT" | grep -qiE "\[ALERTE"; then
  source /root/claude-heartbeat/telegram.sh
  send_message "ALERTE heartbeat $NOW

$RESULT"
fi
