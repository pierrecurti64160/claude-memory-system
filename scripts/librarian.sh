#!/bin/bash
set -euo pipefail
/root/claude-heartbeat/sync-memory.sh

MEMORY_DIR="/root/claude-memory"
LOG_DIR="$MEMORY_DIR/logs"
VAULT_DIR="/root/obsidian-vault"
TODAY=$(date +%Y-%m-%d)
NOW=$(date +%H:%M)
LOG_FILE="$LOG_DIR/$TODAY.md"
LAST_LIBRARIAN="/root/claude-heartbeat/last-librarian"

mkdir -p "$LOG_DIR"
if [ ! -f "$LOG_FILE" ]; then
  echo "# $TODAY" > "$LOG_FILE"
  echo "" >> "$LOG_FILE"
fi

# Trouver les notes Obsidian modifiees depuis le dernier passage
NEW_NOTES=""
if [ -d "$VAULT_DIR" ] && [ -f "$LAST_LIBRARIAN" ]; then
  NEW_NOTES=$(find "$VAULT_DIR" -name "*.md" ! -path "*/Modèles/*" ! -path "*/4 ARCHIVES/*" -newer "$LAST_LIBRARIAN" 2>/dev/null | sed "s|$VAULT_DIR/||" | head -20 || true)
elif [ -d "$VAULT_DIR" ]; then
  NEW_NOTES=$(find "$VAULT_DIR" -name "*.md" ! -path "*/Modèles/*" ! -path "*/4 ARCHIVES/*" -mtime -1 2>/dev/null | sed "s|$VAULT_DIR/||" | head -20 || true)
fi
touch "$LAST_LIBRARIAN"

# Si aucune note modifiee, rien a faire
if [ -z "$NEW_NOTES" ]; then
  echo "" >> "$LOG_FILE"
  echo "## $NOW [librarian] — Aucune nouvelle note Obsidian" >> "$LOG_FILE"
  /root/claude-heartbeat/sync-memory.sh
  exit 0
fi

# Lire le contenu des notes modifiees (max 5000 chars par note, max 10 notes)
NOTES_CONTENT=""
COUNT=0
while IFS= read -r note; do
  if [ "$COUNT" -ge 10 ]; then break; fi
  FULL_PATH="$VAULT_DIR/$note"
  if [ -f "$FULL_PATH" ]; then
    CONTENT=$(head -c 5000 "$FULL_PATH" 2>/dev/null || true)
    NOTES_CONTENT="$NOTES_CONTENT
=== $note ===
$CONTENT
"
    COUNT=$((COUNT + 1))
  fi
done <<< "$NEW_NOTES"

PROMPT="Tu es le librarian autonome de Pierre. Il est $NOW.

Pierre a modifie ou cree ces notes dans son second cerveau Obsidian :

$NOTES_CONTENT

=== PROFIL ACTUEL DE PIERRE ===
$(cat "$MEMORY_DIR/user_pierre.md" 2>/dev/null)

=== MEMOIRE INDEX ===
$(cat "$MEMORY_DIR/MEMORY.md" 2>/dev/null)

=== PROJETS CONNUS ===
$(for f in "$MEMORY_DIR"/project_*.md; do echo "--- $(basename "$f") ---"; head -5 "$f" 2>/dev/null; echo ""; done)

TU DOIS FAIRE EXACTEMENT CECI :

1. ANALYSER les notes et extraire :
   - Toute info nouvelle sur Pierre (preferences, habitudes, objectifs, relations, decisions)
   - Tout changement de statut d un projet
   - Toute nouvelle activite, reunion, reflexion importante
   - Tout feedback implicite sur comment Pierre veut travailler

2. METTRE A JOUR user_pierre.md avec Edit si tu trouves des infos nouvelles sur Pierre. Ne supprime rien, ajoute ou mets a jour les sections existantes.

3. METTRE A JOUR les project_*.md si un projet a change de statut. Cree un nouveau project_*.md si un nouveau projet apparait et ajoute-le a MEMORY.md.

4. CREER des feedback_*.md si tu detectes des preferences ou corrections implicites de Pierre. Ajoute-les a MEMORY.md.

5. RESUME : Ecris en une phrase ce que tu as appris et mis a jour.

REGLES :
- SOUL.md intouchable
- Ne cree des memoires que pour des infos durables (30+ jours)
- Qualite > quantite
- Si les notes ne contiennent rien de nouveau sur Pierre, ne modifie rien

Reponds avec le resume."

RESULT=$(timeout 300 claude -p "$PROMPT" \
  --allowedTools "Read,Write,Edit" \
  --max-turns 15 \
  2>/dev/null || echo "ERREUR: timeout")

echo "" >> "$LOG_FILE"
echo "## $NOW [librarian] — $RESULT" >> "$LOG_FILE"

/root/claude-heartbeat/sync-memory.sh
