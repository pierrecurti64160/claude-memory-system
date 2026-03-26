#!/bin/bash
set -euo pipefail
/root/claude-heartbeat/sync-memory.sh

MEMORY_DIR="/root/claude-memory"
LOG_DIR="$MEMORY_DIR/logs"
SUMMARY_DIR="$LOG_DIR/summaries"
WEEK=$(date +%Y-W%V)
SUMMARY_FILE="$SUMMARY_DIR/$WEEK.md"

mkdir -p "$SUMMARY_DIR"

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

PROMPT="Tu es le cerveau autonome de Pierre. Resume hebdomadaire semaine $WEEK.

=== LOGS DE LA SEMAINE ===
$WEEK_LOGS

=== MEMOIRE ===
$(cat "$MEMORY_DIR/MEMORY.md" 2>/dev/null)

=== PROJETS ===
$(for f in "$MEMORY_DIR"/project_*.md; do echo "--- $(basename "$f") ---"; cat "$f" 2>/dev/null; echo ""; done)

TU DOIS FAIRE 2 CHOSES :

1. ECRIRE LE RESUME HEBDO dans $SUMMARY_FILE :
# Resume semaine $WEEK

## Projets
- Par projet : ce qui a avance, decisions, blocages

## Decisions cles
- Choix techniques ou strategiques de la semaine

## Patterns observes
- Habitudes de travail, horaires, focus

## Taches ouvertes
- Ce qui reste a faire

## Recommandations
- 1-3 suggestions pour la semaine prochaine

2. CONSOLIDER LA MEMOIRE (role librarian profond) :
   - Relis tous les logs de la semaine
   - Identifie les infos durables qui ne sont PAS encore dans la memoire
   - Mets a jour les project_*.md avec les progres de la semaine
   - Mets a jour user_pierre.md si de nouveaux patterns emergent
   - Cree de nouveaux fichiers memoire si necessaire
   - Mets a jour MEMORY.md index si nouveaux fichiers crees
   - Nettoie les infos obsoletes dans les fichiers existants (sans supprimer, marquer comme obsolete)

REGLES :
- Ne modifie JAMAIS SOUL.md
- Qualite > quantite
- Utilise les outils Read, Write, Edit"

timeout 300 claude -p "$PROMPT" \
  --allowedTools "Read,Write,Edit" \
  --max-turns 15 \
  2>/dev/null || echo "# $WEEK — ERREUR generation resume" > "$SUMMARY_FILE"

# Sync back to Syncthing
/root/claude-heartbeat/sync-memory.sh
