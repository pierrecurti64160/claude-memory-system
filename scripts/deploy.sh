#!/usr/bin/env bash
# Chief of Staff — Script de déploiement
# Synchronise les scripts locaux vers le VPS Hetzner et configure les services.
# Usage : ./deploy.sh

set -euo pipefail

VPS="root@91.99.19.182"
REMOTE_DIR="/root/claude-heartbeat"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Chief of Staff — Déploiement ==="
echo "Source  : $SCRIPT_DIR"
echo "Cible   : $VPS:$REMOTE_DIR"
echo ""

# --- 1. Rsync des scripts vers le VPS ---
echo "[1/3] Synchronisation des fichiers..."
rsync -avz --exclude '.git' --exclude '.DS_Store' "$SCRIPT_DIR/" "$VPS:$REMOTE_DIR/"
echo ""

# --- 2. Configuration sur le VPS ---
echo "[2/3] Configuration du VPS..."
ssh "$VPS" bash <<'REMOTE_SCRIPT'
set -euo pipefail

REMOTE_DIR="/root/claude-heartbeat"
DAILY_DIR="/root/obsidian-vault/5 TOOLS/Notes quotidienne"

# Rendre les scripts exécutables
echo "  - chmod +x sur les .sh et .py"
chmod +x "$REMOTE_DIR"/*.sh "$REMOTE_DIR"/*.py 2>/dev/null || true

# Créer le répertoire daily notes si manquant
echo "  - Création du répertoire daily notes si manquant"
mkdir -p "$DAILY_DIR"

# Installer inotify-tools si manquant
if ! command -v inotifywait &>/dev/null; then
    echo "  - Installation de inotify-tools..."
    apt-get update -qq && apt-get install -y -qq inotify-tools
else
    echo "  - inotify-tools déjà installé"
fi

# Installer le crontab
echo "  - Installation du crontab"
crontab "$REMOTE_DIR/crontab.txt"

# Copier et activer le service watcher
echo "  - Installation du service watcher"
cp "$REMOTE_DIR/watcher.service" /etc/systemd/system/watcher.service
systemctl daemon-reload
systemctl enable watcher.service
systemctl restart watcher.service

# Redémarrer le bot Telegram
echo "  - Redémarrage du bot Telegram"
pkill -f "python3.*telegram-bot.py" 2>/dev/null || true
sleep 1
nohup python3 "$REMOTE_DIR/telegram-bot.py" >> "$REMOTE_DIR/telegram-bot.log" 2>&1 &
echo "    Bot Telegram PID : $!"

echo ""
echo "Configuration terminée."
REMOTE_SCRIPT

echo ""

# --- 3. Vérification ---
echo "[3/3] Vérification..."
ssh "$VPS" bash <<'VERIFY_SCRIPT'
echo ""
echo "--- Statut du watcher ---"
systemctl status watcher.service --no-pager -l 2>/dev/null || echo "  Service non trouvé"

echo ""
echo "--- Crontab actuel ---"
crontab -l 2>/dev/null || echo "  Aucun crontab"

echo ""
echo "--- Processus actifs ---"
echo "  Watcher  : $(pgrep -f 'watcher.py' | head -1 || echo 'non trouvé')"
echo "  Telegram : $(pgrep -f 'telegram-bot.py' | head -1 || echo 'non trouvé')"

echo ""
echo "--- Dernières lignes du log watcher ---"
tail -5 /root/claude-heartbeat/watcher.log 2>/dev/null || echo "  Pas encore de log"
VERIFY_SCRIPT

echo ""
echo "=== Déploiement terminé ==="
