#!/bin/bash
set -euo pipefail
export TZ=Europe/Paris
/root/claude-heartbeat/sync-memory.sh

MEMORY_DIR="/root/claude-memory"
LOG_DIR="$MEMORY_DIR/logs"
SUMMARY_DIR="$LOG_DIR/summaries"
ARCHIVES_DIR="$MEMORY_DIR/archives"
VAULT_DIR="/root/obsidian-vault"
TODAY=$(date +%Y-%m-%d)
WEEK=$(date +%Y-W%V)
SUMMARY_FILE="$SUMMARY_DIR/$WEEK.md"

mkdir -p "$SUMMARY_DIR" "$ARCHIVES_DIR"

# Ne pas regenerer si deja fait
[ -f "$SUMMARY_FILE" ] && exit 0

# --- Collecter les 7 daily notes du vault (scores et priorites) ---
DAILY_NOTES=""
for i in $(seq 0 6); do
  DAY=$(date -d "$i days ago" +%Y-%m-%d)
  NOTE="$VAULT_DIR/5 TOOLS/Notes quotidienne/$DAY.md"
  if [ -f "$NOTE" ]; then
    DAILY_NOTES="$DAILY_NOTES
=== DAILY NOTE $DAY ===
$(cat "$NOTE")"
  fi
done

# --- Collecter les 7 derniers logs ---
WEEK_LOGS=""
for i in $(seq 0 6); do
  DAY=$(date -d "$i days ago" +%Y-%m-%d)
  if [ -f "$LOG_DIR/$DAY.md" ]; then
    WEEK_LOGS="$WEEK_LOGS
=== LOG $DAY ===
$(cat "$LOG_DIR/$DAY.md")"
  fi
done

# --- Collecter les frontmatter de tous les fichiers memoire pour le decay scan ---
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

# --- Daily note du jour pour y appender la section weekly ---
DAILY_NOTE="$VAULT_DIR/5 TOOLS/Notes quotidienne/$TODAY.md"
DAILY_NOTE_EXISTS="non"
if [ -f "$DAILY_NOTE" ]; then
  DAILY_NOTE_EXISTS="oui"
fi

PROMPT="Tu es le Chief of Staff de Pierre. Resume hebdomadaire semaine $WEEK. Le $TODAY.

=== DAILY NOTES DE LA SEMAINE (priorites + scores) ===
$DAILY_NOTES

=== LOGS DE LA SEMAINE ===
$WEEK_LOGS

=== MEMOIRE (index) ===
$(cat "$MEMORY_DIR/MEMORY.md" 2>/dev/null)

=== ETAT DES FICHIERS MEMOIRE (frontmatter) ===
$MEMORY_STATUS

=== PROJETS ===
$(for f in "$MEMORY_DIR"/project_*.md; do [ -f "$f" ] && echo "--- $(basename "$f") ---" && cat "$f" 2>/dev/null && echo ""; done)

TU DOIS FAIRE 5 CHOSES :

1. METRIQUES COMPORTEMENTALES :
   - Lis les daily notes de la semaine. Pour chaque jour, releve les priorites planifiees et leur statut (FAIT / PAS FAIT / PARTIEL).
   - Calcule le taux de completion global : nombre de priorites FAIT / nombre total de priorites planifiees.
   - Ventilation par categorie (COMMUNICATION, DEV, ADMIN, CHECK) :
     * Combien de taches de chaque categorie etaient planifiees
     * Combien ont ete faites
     * Taux de completion par categorie
   - Detecte les patterns : 'Tu completes X% des taches DEV mais Y% des taches COMMUNICATION. Pattern constant depuis N semaines.'
   - Liste les taches chroniquement ignorees : taches apparues 3+ fois dans les briefings sans jamais etre faites. Pour chaque une : propose de l enlever ou de l escalader.

2. RESUME HEBDO — Ecris dans $SUMMARY_FILE avec Write :
# Resume semaine $WEEK

## Metriques
- Taux de completion global : X/Y (Z%)
- COMMUNICATION : X/Y (Z%)
- DEV : X/Y (Z%)
- ADMIN : X/Y (Z%)
- CHECK : X/Y (Z%)

## Patterns detectes
- [patterns comportementaux recurrents]

## Taches chroniquement ignorees
- [tache] — apparue N fois, jamais faite. Recommandation : [enlever / escalader / reformuler]

## Par projet
[par projet : avancement, decisions, blocages]

## Decisions cles de la semaine
[decisions prises]

## Taches ouvertes
[taches non terminees]

## Recommandations pour la semaine prochaine
1. [recommandation specifique basee sur les patterns]
2. [recommandation specifique]
3. [recommandation specifique]

3. CYCLE LMP — Scan/Validate/Commit :
Pour chaque fichier memoire, lis le frontmatter (certainty, source, last_confirmed) :

a) SCAN : identifie les fichiers ou last_confirmed date de plus de :
   - 90 jours pour certainty: volatile
   - 60 jours pour certainty: speculative
   Si c est le cas, le fichier a DECAY.

b) VALIDATE : pour les fichiers qui ont decay, verifie dans les logs de la semaine si l info a ete confirmee recemment.
   - Si confirmee -> mets a jour last_confirmed avec la date d aujourd hui
   - Si pas confirmee et volatile -> descends a speculative
   - Si pas confirmee et speculative -> ARCHIVE : deplace le fichier dans $ARCHIVES_DIR avec Edit/Write

c) COMMIT : pour les fichiers encore valides, mets a jour last_confirmed si l info a ete mentionnee cette semaine dans les logs.

d) Pour toute info NOUVELLE trouvee dans les logs qui merite une memoire, cree le fichier avec le bon frontmatter :
   certainty: volatile ou stable
   source: declared (Pierre l a dit) ou inferred (deduit du contexte)
   last_confirmed: date du jour

e) Si tu archives ou crees un fichier, mets a jour MEMORY.md.

4. CONSOLIDATION — Mets a jour les project_*.md et user_pierre.md avec les infos de la semaine.

5. DAILY NOTE — Si la daily note du jour existe ($DAILY_NOTE_EXISTS), appende une section weekly a la fin de $DAILY_NOTE avec Edit :

   ---
   ## Bilan hebdomadaire $WEEK
   - Taux de completion : X/Y (Z%)
   - Pattern principal : [pattern]
   - Recommandation #1 : [recommandation]
   - Taches a enlever ou escalader : [liste]

REGLES :
- Ne modifie JAMAIS les fichiers avec certainty: fixed (SOUL.md, feedbacks declared explicites)
- Les feedbacks declared ne subissent pas de decay (Pierre l a dit explicitement)
- Pour archiver, deplace le fichier dans $ARCHIVES_DIR (pas juste le marquer)
- Qualite > quantite — ne cree des memoires que pour des infos durables
- Utilise Read, Write, Edit, Bash

IMPORTANT pour ta reponse finale : produis un resume COURT pour Telegram. Format :
Semaine $WEEK : completion X/Y (Z%). Pattern : [pattern principal]. Top recommandation : [recommandation #1]. Taches a virer : [liste ou 'aucune']."

RESULT=$(timeout 480 claude -p "$PROMPT" \
  --allowedTools "Read,Write,Edit,Bash" \
  --max-turns 25 \
  2>/dev/null || echo "ERREUR: timeout")

# --- Logger le resultat ---
LOG_FILE="$LOG_DIR/$TODAY.md"
if [ -f "$LOG_FILE" ]; then
  echo "" >> "$LOG_FILE"
  echo "## $(date +%H:%M) [weekly] — Bilan hebdo + LMP cycle" >> "$LOG_FILE"
  echo "$RESULT" >> "$LOG_FILE"
fi

# --- Sync et notification ---
/root/claude-heartbeat/sync-memory.sh

# Envoyer le bilan hebdo via Telegram
source /root/claude-heartbeat/telegram.sh
WEEKLY_MSG=$(echo "$RESULT" | head -8)
send_message "Bilan hebdo $WEEK

$WEEKLY_MSG"
