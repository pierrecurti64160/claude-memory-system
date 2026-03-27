#!/bin/bash
set -euo pipefail
/root/claude-heartbeat/sync-memory.sh

MEMORY_DIR="/root/claude-memory"
LOG_DIR="$MEMORY_DIR/logs"
SUMMARY_DIR="$LOG_DIR/summaries"
ARCHIVES_DIR="$MEMORY_DIR/archives"
WEEK=$(date +%Y-W%V)
SUMMARY_FILE="$SUMMARY_DIR/$WEEK.md"

mkdir -p "$SUMMARY_DIR" "$ARCHIVES_DIR"

# Ne pas regenerer si deja fait
[ -f "$SUMMARY_FILE" ] && exit 0

# Collecter les 7 derniers logs
WEEK_LOGS=""
for i in $(seq 0 6); do
  DAY=$(date -d "$i days ago" +%Y-%m-%d)
  if [ -f "$LOG_DIR/$DAY.md" ]; then
    WEEK_LOGS="$WEEK_LOGS
=== $DAY ===
$(cat "$LOG_DIR/$DAY.md")"
  fi
done

# Collecter les frontmatter de tous les fichiers memoire pour le decay scan
MEMORY_STATUS=""
for f in "$MEMORY_DIR"/*.md; do
  [ -f "$f" ] || continue
  FNAME=$(basename "$f")
  HEADER=$(head -10 "$f")
  MEMORY_STATUS="$MEMORY_STATUS
--- $FNAME ---
$HEADER
"
done

PROMPT="Tu es le cerveau autonome de Pierre. Resume hebdomadaire semaine $WEEK + CYCLE LMP.

=== LOGS DE LA SEMAINE ===
$WEEK_LOGS

=== MEMOIRE (index) ===
$(cat "$MEMORY_DIR/MEMORY.md" 2>/dev/null)

=== ETAT DES FICHIERS MEMOIRE (frontmatter) ===
$MEMORY_STATUS

=== PROJETS ===
$(for f in "$MEMORY_DIR"/project_*.md; do [ -f "$f" ] && echo "--- $(basename "$f") ---" && cat "$f" 2>/dev/null && echo ""; done)

TU DOIS FAIRE 3 CHOSES :

1. RESUME HEBDO — Ecris dans $SUMMARY_FILE :
# Resume semaine $WEEK
## Projets (par projet : avancement, decisions, blocages)
## Decisions cles
## Taches ouvertes
## Recommandations (1-3 pour la semaine prochaine)

2. CYCLE LMP — Scan/Validate/Commit :
Pour chaque fichier memoire, lis le frontmatter (certainty, source, last_confirmed) :

a) SCAN : identifie les fichiers ou last_confirmed date de plus de :
   - 90 jours pour certainty: volatile
   - 60 jours pour certainty: speculative
   Si c est le cas, le fichier a DECAY.

b) VALIDATE : pour les fichiers qui ont decay, verifie dans les logs de la semaine si l info a ete confirmee recemment.
   - Si confirmee → mets a jour last_confirmed avec la date d aujourd hui
   - Si pas confirmee et volatile → descends a speculative
   - Si pas confirmee et speculative → ARCHIVE : deplace le fichier dans $ARCHIVES_DIR avec Edit/Write

c) COMMIT : pour les fichiers encore valides, mets a jour last_confirmed si l info a ete mentionnee cette semaine dans les logs.

d) Pour toute info NOUVELLE trouvee dans les logs qui merite une memoire, cree le fichier avec le bon frontmatter :
   certainty: volatile ou stable
   source: declared (Pierre l a dit) ou inferred (deduit du contexte)
   last_confirmed: date du jour

e) Si tu archives ou crees un fichier, mets a jour MEMORY.md.

3. CONSOLIDATION — Mets a jour les project_*.md et user_pierre.md avec les infos de la semaine.

REGLES :
- Ne modifie JAMAIS les fichiers avec certainty: fixed (SOUL.md, feedbacks declared explicites)
- Les feedbacks declared ne subissent pas de decay (Pierre l a dit explicitement)
- Pour archiver, deplace le fichier dans $ARCHIVES_DIR (pas juste le marquer)
- Qualite > quantite — ne cree des memoires que pour des infos durables
- Utilise Read, Write, Edit, Bash"

RESULT=$(timeout 480 claude -p "$PROMPT" \
  --allowedTools "Read,Write,Edit,Bash" \
  --max-turns 20 \
  2>/dev/null) || RESULT="ERREUR: timeout"

# Log le resultat
TODAY=$(date +%Y-%m-%d)
LOG_FILE="$LOG_DIR/$TODAY.md"
if [ -f "$LOG_FILE" ]; then
  echo "" >> "$LOG_FILE"
  echo "## $(date +%H:%M) [weekly] — Resume + LMP cycle" >> "$LOG_FILE"
  echo "$RESULT" >> "$LOG_FILE"
fi

/root/claude-heartbeat/sync-memory.sh
