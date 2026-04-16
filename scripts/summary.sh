#!/bin/bash
set -euo pipefail
export TZ=Europe/Paris
/root/claude-heartbeat/sync-memory.sh

MEMORY_DIR="/root/claude-memory"
LOG_DIR="$MEMORY_DIR/logs"
PROJECTS_DIR="/root/projects"
VAULT_DIR="/root/obsidian-vault"
TODAY=$(date +%Y-%m-%d)
YESTERDAY=$(date -d "yesterday" +%Y-%m-%d)
NOW=$(date +%H:%M)
LOG_FILE="$LOG_DIR/$TODAY.md"
YESTERDAY_LOG="$LOG_DIR/$YESTERDAY.md"
DAILY_NOTE="$VAULT_DIR/5 TOOLS/Notes quotidienne/$TODAY.md"

mkdir -p "$LOG_DIR"
if [ ! -f "$LOG_FILE" ]; then
  echo "# $TODAY" > "$LOG_FILE"
  echo "" >> "$LOG_FILE"
fi

# --- Collecter les commits du jour ---
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

# --- Fichiers modifies ---
MODIFIED_FILES=$(find "$PROJECTS_DIR" -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.tsx" -o -name "*.mq5" -o -name "*.mqh" -o -name "*.md" \) -newer "$YESTERDAY_LOG" 2>/dev/null | sed "s|$PROJECTS_DIR/||" | head -30 || true)
if [ -z "$MODIFIED_FILES" ] && [ ! -f "$YESTERDAY_LOG" ]; then
  MODIFIED_FILES=$(find "$PROJECTS_DIR" -type f \( -name "*.py" -o -name "*.js" -o -name "*.ts" -o -name "*.tsx" -o -name "*.mq5" -o -name "*.mqh" -o -name "*.md" \) -mtime -1 2>/dev/null | sed "s|$PROJECTS_DIR/||" | head -30 || true)
fi

# --- Activites post-resume d'hier ---
LATE_ENTRIES=""
if [ -f "$YESTERDAY_LOG" ]; then
  SUMMARY_LINE=$(grep -n "\[summary\]" "$YESTERDAY_LOG" | tail -1 | cut -d: -f1 || true)
  if [ -n "$SUMMARY_LINE" ]; then
    LATE_ENTRIES=$(tail -n +"$((SUMMARY_LINE + 1))" "$YESTERDAY_LOG" | grep -E "^## [0-9]{2}:[0-9]{2} " -A 5 | head -50 || true)
  fi
fi

# --- Daily note du matin (les 3 priorites) ---
DAILY_NOTE_CONTENT=""
if [ -f "$DAILY_NOTE" ]; then
  DAILY_NOTE_CONTENT=$(cat "$DAILY_NOTE")
fi

# --- Reponses au debrief (vocaux/textes de Pierre entre 18h et 21h) ---
DEBRIEF_FILE="/root/claude-heartbeat/debriefs/$TODAY.md"
DEBRIEF_CONTENT=""
if [ -f "$DEBRIEF_FILE" ]; then
  DEBRIEF_CONTENT=$(cat "$DEBRIEF_FILE")
  # Cloturer le debrief s'il etait encore ouvert
  if grep -q "^status: open" "$DEBRIEF_FILE"; then
    sed -i "s/^status: open/status: closed/" "$DEBRIEF_FILE"
    sed -i "/^started_at:/i closed_at: $NOW (auto)" "$DEBRIEF_FILE"
  fi
fi

# --- Chercher les taches ignorees depuis N jours dans les daily notes recentes ---
IGNORED_TASKS=""
for i in $(seq 1 7); do
  DAY=$(date -d "$i days ago" +%Y-%m-%d)
  NOTE="$VAULT_DIR/5 TOOLS/Notes quotidienne/$DAY.md"
  if [ -f "$NOTE" ]; then
    IGNORED_TASKS="$IGNORED_TASKS
=== $DAY ===
$(cat "$NOTE" | head -80)"
  fi
done

PROMPT="Tu es le Chief of Staff de Pierre. Bilan de fin de journee. Il est $NOW (Europe/Paris), le $TODAY.

=== DAILY NOTE DU MATIN (priorites planifiees) ===
${DAILY_NOTE_CONTENT:-Aucune daily note trouvee pour aujourd hui}

=== LOG DU JOUR ===
$(cat "$LOG_FILE")

=== ACTIVITES POST-RESUME HIER (non couvertes par le resume d hier) ===
${LATE_ENTRIES:-Aucune}

=== COMMITS DU JOUR ===
${GIT_TODAY:-Aucun commit}

=== FICHIERS MODIFIES AUJOURD HUI ===
${MODIFIED_FILES:-Aucun}

=== DAILY NOTES DES 7 DERNIERS JOURS (pour detecter les taches recurrentes ignorees) ===
${IGNORED_TASKS:-Aucune}

=== DEBRIEF DE PIERRE (questions posees a 18h + reponses vocales/textes) ===
${DEBRIEF_CONTENT:-Pas de debrief aujourd hui}

REGLES DEBRIEF :
1. Les reponses de Pierre sont la VERITE TERRAIN. Si tes deductions log/git/vault contredisent ce qu'il a dit, c'est Pierre qui a raison. Mets a jour memoire et projets en consequence.
2. Pour les questions du debrief que Pierre a IGNOREES (pas de reponse correspondante dans ses messages) : considere que Pierre n'avait PAS d'info nouvelle a donner. Ne spe cule PAS sur ces points. Garde l'etat connu de la memoire actuelle.
3. Si Pierre a repondu en bloc sans suivre la numerotation des questions, fais correspondre intelligemment ses propos aux sujets evoques. En cas de doute, marque le sujet comme \"non clarifie par le debrief\" plutot que de speculer.
4. Liste explicitement dans le resume du jour les sujets QUI NE SONT PAS CLARIFIES par le debrief, pour que demain le briefing les reprenne.

=== MEMOIRE ===
$(cat "$MEMORY_DIR/MEMORY.md" 2>/dev/null)

=== PROJETS ===
$(for f in "$MEMORY_DIR"/project_*.md; do cat "$f" 2>/dev/null; echo ""; done)

=== PRIMER ACTUEL ===
$(cat "$MEMORY_DIR/primer.md" 2>/dev/null)

TU DOIS FAIRE 6 CHOSES (utilise les tools Read, Edit, Write) :

1. SCORE DU JOUR :
   - Lis la daily note du matin pour voir les 3 priorites qui etaient planifiees.
   - Pour chaque priorite, score : FAIT / PAS FAIT / PARTIEL.
   - Calcule le score X/3.
   - Si une priorite n a pas ete faite, regarde dans les daily notes des 7 derniers jours si elle revenait deja. Compte le nombre de jours.

2. ANALYSE :
   - Qu est-ce que Pierre a fait aujourd hui a la place de ce qui etait planifie ? (regarde les commits, fichiers modifies, log entries)
   - Pattern : est-ce que c est recurrent ? (ex: toujours code au lieu de communiquer, toujours ignore les CHECK)
   - Pour chaque tache ignoree N jours : note-le. Si 5+ jours : 'Decide demain : tu fais ou on enleve.'

3. MISE A JOUR DAILY NOTE :
   METS A JOUR la daily note $DAILY_NOTE — ajoute les sections suivantes A LA FIN du fichier. Ne touche PAS aux priorites du matin ni au contenu existant. Utilise Edit pour appender :

   ---
   ## Completees
   - [liste des taches faites, planifiees ou non]

   ## Score du jour : X/3
   - Priorite 1 : [titre] — FAIT / PAS FAIT / PARTIEL
   - Priorite 2 : [titre] — FAIT / PAS FAIT / PARTIEL
   - Priorite 3 : [titre] — FAIT / PAS FAIT / PARTIEL

   ## Analyse
   - [ce que Pierre a fait a la place]
   - [pattern detecte si applicable]
   - [escalade si tache ignoree 3+ jours]

4. MAJ PROJETS : Edit les project_*.md dans $MEMORY_DIR dont le statut a change.

5. LIBRARIAN (avec regles LMP) : Si des infos durables (30+ jours) sont dans les logs :
   - Cree des fichiers feedback_*.md ou reference_*.md dans $MEMORY_DIR
   - Ajoute-les a $MEMORY_DIR/MEMORY.md
   - TOUT nouveau fichier DOIT avoir dans le frontmatter :
     certainty: fixed | stable | volatile | speculative
     source: declared (Pierre l a dit) | inferred (deduit du contexte)
     last_confirmed: la date du jour
   - Seuls les regles immuables declarees par Pierre meritent fixed — en cas de doute, utilise stable.
   - Si Pierre a DIT quelque chose -> source: declared. Si tu le deduis -> source: inferred.
   - En cas de conflit declared vs inferred -> declared gagne.
   - Quand tu mets a jour un fichier existant, mets aussi a jour last_confirmed dans le frontmatter.

6. PRIMER : Reecris ENTIEREMENT $MEMORY_DIR/primer.md avec Write. Format :
---
name: Primer - Etat courant
description: Snapshot de ou Pierre en est.
type: project
---
# Primer
## Derniere session (date, contexte, ce qui a ete fait)
## Projets actifs (par projet: statut, derniere action, prochaine etape)
## En cours (taches pas terminees)
## Score du jour ($TODAY) : X/3
## Prochaine action probable

IMPORTANT pour ta reponse finale (texte retourne) : produis un resume COURT pour le Telegram. Format :
Score du jour : X/3. [Priorite 1] [statut], [Priorite 2] [statut], [Priorite 3] [statut]. [Pattern ou escalade si applicable]."

RESULT=$(timeout 360 claude -p "$PROMPT" \
  --allowedTools "Read,Write,Edit" \
  --max-turns 20 \
  2>/dev/null || echo "ERREUR: timeout")

# --- Logger le resultat ---
echo "" >> "$LOG_FILE"
echo "## $NOW [summary] — Bilan du jour" >> "$LOG_FILE"
echo "$RESULT" >> "$LOG_FILE"

# --- Sync et notification ---
/root/claude-heartbeat/sync-memory.sh

# Envoyer le score via Telegram (le RESULT est deja formate court pour Telegram)
source /root/claude-heartbeat/telegram.sh
SCORE_MSG=$(echo "$RESULT" | head -5)
send_message "Bilan du jour ($TODAY)

$SCORE_MSG"
