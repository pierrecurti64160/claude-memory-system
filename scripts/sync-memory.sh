#!/bin/bash
set -euo pipefail
# Sync bidirectionnel entre claude-memory (writable) et le dossier Syncthing
WORK="/root/claude-memory"
SYNC="/root/.claude/projects/-Users-pierrecurti/memory"

# Du dossier writable vers Syncthing (les ecritures de Claude)
rsync -a --update "$WORK/" "$SYNC/"

# De Syncthing vers le dossier writable (les ecritures de Pierre via Mac)
rsync -a --update "$SYNC/" "$WORK/"
