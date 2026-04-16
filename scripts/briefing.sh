#!/bin/bash
set -euo pipefail
export TZ=Europe/Paris

# ---------------------------------------------------------------------------
# Briefing matinal — Chief of Staff
# Produit 3 priorites scorees, detecte les patterns comportementaux,
# ecrit la daily note Obsidian, et envoie le top 3 sur Telegram.
# ---------------------------------------------------------------------------

/root/claude-heartbeat/sync-memory.sh

MEMORY_DIR="/root/claude-memory"
LOG_DIR="$MEMORY_DIR/logs"
PROJECTS_DIR="/root/projects"
VAULT_DIR="/root/obsidian-vault"
DAILY_DIR="$VAULT_DIR/5 TOOLS/Notes quotidienne"
REUNIONS_DIR="$VAULT_DIR/2 CAPS/Reunions"
PRIORITY_ENGINE="/root/claude-heartbeat/priority-engine.md"
TODAY=$(date +%Y-%m-%d)
YESTERDAY=$(date -d "yesterday" +%Y-%m-%d)
NOW=$(date +%H:%M)
LOG_FILE="$LOG_DIR/$TODAY.md"
DAILY_NOTE="$DAILY_DIR/$TODAY.md"

mkdir -p "$LOG_DIR"
mkdir -p "$DAILY_DIR"

if [ ! -f "$LOG_FILE" ]; then
  echo "# $TODAY" > "$LOG_FILE"
  echo "" >> "$LOG_FILE"
fi

# --- 1. Collecte du contexte ---

# Git : activite depuis hier
GIT_ACTIVITY=""
for dir in "$PROJECTS_DIR"/*/; do
  if [ -d "$dir/.git" ]; then
    PROJECT_NAME=$(basename "$dir")
    COMMITS=$(cd "$dir" && git log --since="$YESTERDAY 00:00" --oneline --all 2>/dev/null || true)
    UNCOMMITTED=$(cd "$dir" && git status --short 2>/dev/null | wc -l | tr -d ' ' || echo "0")
    if [ -n "$COMMITS" ] || [ "$UNCOMMITTED" -gt 0 ]; then
      GIT_ACTIVITY="$GIT_ACTIVITY
$PROJECT_NAME: ${COMMITS:-aucun commit}, $UNCOMMITTED non commites"
    fi
  fi
done

# Fichiers modifies depuis hier (avec fallback si le log d'hier n'existe pas)
YESTERDAY_REF="$LOG_DIR/$YESTERDAY.md"
if [ ! -f "$YESTERDAY_REF" ]; then
  YESTERDAY_REF="$LOG_FILE"  # fallback : depuis aujourd'hui
fi
MODIFIED=$(find "$PROJECTS_DIR" -type f \
  \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.tsx" \
     -o -name "*.mq5" -o -name "*.mqh" \) \
  -newer "$YESTERDAY_REF" \
  ! -path "*/node_modules/*" \
  ! -path "*/.git/*" \
  ! -path "*/venv/*" \
  ! -path "*/__pycache__/*" \
  2>/dev/null | sed "s|$PROJECTS_DIR/||" | head -30 || true)

# Notes Obsidian recentes (2 derniers jours)
VAULT_RECENT=""
if [ -d "$VAULT_DIR" ]; then
  VAULT_RECENT=$(find "$VAULT_DIR" -name "*.md" -mtime -2 \
    ! -path "*/node_modules/*" \
    ! -path "*/.git/*" \
    2>/dev/null | sed "s|$VAULT_DIR/||" | head -20 || true)
fi

# Reunions des 7 derniers jours
RECENT_MEETINGS=""
if [ -d "$REUNIONS_DIR" ]; then
  RECENT_MEETINGS=$(find "$REUNIONS_DIR" -name "*.md" -mtime -7 2>/dev/null | sort -r | head -5 || true)
  if [ -n "$RECENT_MEETINGS" ]; then
    MEETINGS_CONTENT=""
    while IFS= read -r meeting_file; do
      MEETING_NAME=$(basename "$meeting_file" .md)
      MEETING_EXCERPT=$(head -50 "$meeting_file" 2>/dev/null || true)
      MEETINGS_CONTENT="$MEETINGS_CONTENT
--- $MEETING_NAME ---
$MEETING_EXCERPT
"
    done <<< "$RECENT_MEETINGS"
    RECENT_MEETINGS="$MEETINGS_CONTENT"
  fi
fi

# Priority Engine (modele de scoring)
PRIORITY_MODEL=""
if [ -f "$PRIORITY_ENGINE" ]; then
  PRIORITY_MODEL=$(cat "$PRIORITY_ENGINE" 2>/dev/null)
fi

# --- 2. Appel Claude — Chief of Staff ---

PROMPT="Tu es le Chief of Staff de Pierre. Pas un reporter — un decideur.
Il est $NOW (Europe/Paris), $TODAY.

=== PRIORITY ENGINE (modele de scoring) ===
${PRIORITY_MODEL:-Pas de modele charge. Score par defaut : urgence (deadline) > impact business > effort inverse.}

=== LOGS HIER ===
$(cat "$LOG_DIR/$YESTERDAY.md" 2>/dev/null || echo "Pas de log hier")

=== GIT ACTIVITE ===
${GIT_ACTIVITY:-Aucune activite git}

=== FICHIERS MODIFIES ===
${MODIFIED:-Aucun}

=== NOTES OBSIDIAN RECENTES ===
${VAULT_RECENT:-Aucune}

=== REUNIONS (7 derniers jours) ===
${RECENT_MEETINGS:-Aucune reunion recente}

=== PRIMER ===
$(cat "$MEMORY_DIR/primer.md" 2>/dev/null)

=== MEMOIRE ===
$(cat "$MEMORY_DIR/MEMORY.md" 2>/dev/null)

=== INSTRUCTIONS ===

0. SNOOZE : Lis la section \"Snoozed\" du primer. Les taches snoozees sont EXCLUES du scoring jusqu'a leur date de fin. Ne les fais PAS apparaitre dans les priorites tant que la date de snooze n'est pas atteinte. Exemple : si le primer dit \"Robot Trading snoozed jusqu'au 17/04\", et qu'on est le 15/04, ne pas proposer Robot Trading. Le 17/04 et apres, elle redevient eligible au scoring.

1. SCORING : Lis le Priority Engine ci-dessus. Score chaque tache en attente (primer, logs, reunions) SAUF les snoozees. Utilise les criteres du modele.

2. TOP 3 : Produis EXACTEMENT 3 priorites, dans l'ordre de score decroissant. Pour chaque :
   - Numero et titre court
   - Score et justification en une ligne
   - Action concrete (pas vague, pas 'reflechir a')
   - Si c'est une tache COMMUNICATION (message a envoyer, email, relance), inclus le texte exact a copier-coller entre triple backticks

3. PATTERNS : Detecte les patterns comportementaux :
   - Taches ignorees depuis N jours (repetees dans les logs sans execution)
   - Ratio dev/communication (trop de code, pas assez de relationnel, ou l'inverse)
   - Deadlines qui approchent sans progression visible
   Si aucun pattern notable, ne mets rien.

4. DAILY NOTE : Ecris la daily note Obsidian dans $DAILY_NOTE avec le tool Write. FORMAT OBLIGATOIRE (respecte les headings EXACTEMENT) :
---
date: $TODAY
type: daily
---
# $TODAY

## Priorite #1 — [Titre court] ([effort estime])
[Action concrete / texte a copier-coller]
Score: X/40 | Revenue: X | Urgence: X | Effort: X | Dependency: X
[Contexte en une phrase]

## Priorite #2 — [Titre court] ([effort estime])
[Action concrete]
Score: X/40 | Revenue: X | Urgence: X | Effort: X | Dependency: X
[Contexte]

## Priorite #3 — [Titre court] ([effort estime])
[Action concrete]
Score: X/40 | Revenue: X | Urgence: X | Effort: X | Dependency: X
[Contexte]

---

## Patterns detectes
[si applicable, sinon ne mets pas cette section]

## Activite hier
[resume bref de ce qui s'est passe hier, par projet]

IMPORTANT : les headings de priorites DOIVENT commencer par '## Priorite #N' (avec le tiret cadratin). C'est le format que le bot Telegram parse. Ne change pas ce format.

5. MEMOIRE : Mets a jour les project_*.md dans $MEMORY_DIR si un statut a change. Utilise Edit.

6. TELEGRAM : Ta reponse finale sera envoyee sur Telegram. Elle doit etre COURTE et lisible sur telephone :
   Priorite 1: [titre] (score X)
   > [action]
   Priorite 2: [titre] (score X)
   > [action]
   Priorite 3: [titre] (score X)
   > [action]
   [patterns si applicable, une ligne max]

Reponds UNIQUEMENT avec le format Telegram ci-dessus. Les details vont dans la daily note."

RESULT=$(timeout 300 claude -p "$PROMPT" \
  --allowedTools "Read,Write,Edit" \
  --max-turns 12 \
  2>/dev/null || echo "ERREUR: timeout ou echec Claude")

# --- 3. Log (archive) ---

echo "" >> "$LOG_FILE"
echo "## $NOW [briefing] — Briefing matinal" >> "$LOG_FILE"
echo "$RESULT" >> "$LOG_FILE"

# --- 4. Sync et notification ---

/root/claude-heartbeat/sync-memory.sh

source /root/claude-heartbeat/telegram.sh
send_message "Briefing $TODAY

$RESULT"
