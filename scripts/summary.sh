#!/bin/bash
set -euo pipefail
/root/claude-heartbeat/sync-memory.sh

MEMORY_DIR="/root/claude-memory"
LOG_DIR="$MEMORY_DIR/logs"
PROJECTS_DIR="/root/projects"
TODAY=$(date +%Y-%m-%d)
YESTERDAY=$(date -d "yesterday" +%Y-%m-%d)
NOW=$(date +%H:%M)
LOG_FILE="$LOG_DIR/$TODAY.md"
YESTERDAY_LOG="$LOG_DIR/$YESTERDAY.md"

mkdir -p "$LOG_DIR"
if [ ! -f "$LOG_FILE" ]; then
  echo "# $TODAY" > "$LOG_FILE"
  echo "" >> "$LOG_FILE"
fi

GIT_TODAY=""
for dir in "$PROJECTS_DIR"/*/; do
  if [ -d "$dir/.git" ]; then
    PROJECT_NAME=$(basename "$dir")
    COMMITS=$(cd "$dir" && git log --since="$TODAY 00:00" --oneline --all 2>/dev/null || true)
    if [ -n "$COMMITS" ]; then
      GIT_TODAY="$GIT_TODAY
### $PROJECT_NAME
$COMMITS"
    fi
  fi
done

MODIFIED_FILES=$(find "$PROJECTS_DIR" -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.tsx" -o -name "*.mq5" -o -name "*.mqh" -o -name "*.md" \) -newer "$YESTERDAY_LOG" 2>/dev/null | sed "s|$PROJECTS_DIR/||" | head -30 || true)

# Activites post-resume d'hier (entre le summary d'hier et minuit)
LATE_ENTRIES=""
if [ -f "$YESTERDAY_LOG" ]; then
  SUMMARY_LINE=$(grep -n "\[summary\]" "$YESTERDAY_LOG" | tail -1 | cut -d: -f1 || true)
  if [ -n "$SUMMARY_LINE" ]; then
    LATE_ENTRIES=$(tail -n +"$((SUMMARY_LINE + 1))" "$YESTERDAY_LOG" | grep -E "^## [0-9]{2}:[0-9]{2} " -A 5 | head -50 || true)
  fi
fi

PROMPT="Tu es le cerveau autonome de Pierre. Il est $NOW (Europe/Paris). Resume de fin de journee + LIBRARIAN + PRIMER.

=== LOG DU JOUR ===
$(cat "$LOG_FILE")

=== ACTIVITES POST-RESUME HIER (non couvertes par le resume d hier) ===
${LATE_ENTRIES:-Aucune}

=== COMMITS DU JOUR ===
${GIT_TODAY:-Aucun commit}

=== FICHIERS MODIFIES AUJOURD HUI ===
${MODIFIED_FILES:-Aucun}

=== MEMOIRE ===
$(cat "$MEMORY_DIR/MEMORY.md" 2>/dev/null)

=== PROJETS ===
$(for f in "$MEMORY_DIR"/project_*.md; do cat "$f" 2>/dev/null; echo ""; done)

=== PRIMER ACTUEL ===
$(cat "$MEMORY_DIR/primer.md" 2>/dev/null)

Tu dois faire 4 choses (utilise les tools Edit et Write) :

1. RESUME : Ecris le resume du jour (par projet, decisions, en cours, demain). IMPORTANT : si des activites post-resume d hier sont listees ci-dessus, inclus-les dans le resume — elles ont ete ratees hier.

2. MAJ PROJETS : Edit les project_*.md dans $MEMORY_DIR dont le statut a change.

3. LIBRARIAN (avec regles LMP) : Si des infos durables (30+ jours) sont dans les logs :
   - Cree des fichiers feedback_*.md ou reference_*.md dans $MEMORY_DIR
   - Ajoute-les a $MEMORY_DIR/MEMORY.md
   - TOUT nouveau fichier DOIT avoir dans le frontmatter :
     certainty: stable | volatile | speculative
     source: declared (Pierre l a dit) | inferred (deduit du contexte)
     last_confirmed: la date du jour
   - Si Pierre a DIT quelque chose → source: declared. Si tu le deduis → source: inferred.
   - En cas de conflit declared vs inferred → declared gagne.
   - Quand tu mets a jour un fichier existant, mets aussi a jour last_confirmed dans le frontmatter.

4. PRIMER : Reecris ENTIEREMENT $MEMORY_DIR/primer.md avec Write. Format :
---
name: Primer - Etat courant
description: Snapshot de ou Pierre en est.
type: project
---
# Primer
## Derniere session (date, contexte, ce qui a ete fait)
## Projets actifs (par projet: statut, derniere action, prochaine etape)
## En cours (taches pas terminees)
## Prochaine action probable

Reponds UNIQUEMENT avec le resume du jour."

RESULT=$(timeout 300 claude -p "$PROMPT" \
  --allowedTools "Read,Write,Edit" \
  --max-turns 18 \
  2>/dev/null || echo "ERREUR: timeout")

echo "" >> "$LOG_FILE"
echo "## $NOW [summary] — Resume du jour" >> "$LOG_FILE"
echo "$RESULT" >> "$LOG_FILE"

/root/claude-heartbeat/sync-memory.sh
/root/claude-heartbeat/notify.sh "$LOG_FILE" summary
