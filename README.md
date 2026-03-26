# Claude Memory System

Systeme de memoire autonome pour Claude Code inspire d'OpenClaw + Recall Stack. Un VPS Linux fait tourner un cerveau permanent qui surveille les projets, apprend des notes Obsidian, et maintient une memoire persistante entre les sessions.

## Architecture

```
Mac (travail quotidien)          VPS Hetzner (24/7)              Telephone
───────────────────              ──────────────────              ─────────
Claude Code + rules              Heartbeats (cron)               Terminus SSH
Obsidian (second cerveau)  ←→    Librarian (Obsidian → memoire)  → Claude Code
Projets code               ←→    Briefings/Resumes               meme memoire
                                 Watchdog + Telegram alerts
         └──── Syncthing bidirectionnel ────┘
```

## Couches memoire

| Couche | Fichier | Role |
|--------|---------|------|
| 1 | SOUL.md | Persona, ton, regles. Intouchable par les scripts. |
| 2 | primer.md | "Ou j'en suis". Se reecrit apres chaque tache + chaque soir. |
| 3 | MEMORY.md + fichiers | Memoire long-terme : profil, projets, feedbacks, references. |
| 4 | Logs journaliers | memory/logs/YYYY-MM-DD.md — tout ce qui se passe. |
| 5 | Obsidian vault | Second cerveau, lu en lecture seule par le VPS. |

## Scripts VPS (`/root/claude-heartbeat/`)

| Script | Cron | Role |
|--------|------|------|
| heartbeat.sh | /30min lun-ven 9h-19h | Scan fichiers + git, log + maj memoire |
| briefing.sh | 8h chaque matin | Resume veille + plan du jour |
| summary.sh | 20h chaque soir | Bilan + librarian + reecrit primer |
| librarian.sh | 12h et 18h | Lit Obsidian, met a jour profil et projets |
| weekly.sh | Dimanche 21h | Consolidation profonde de la semaine |
| watchdog.sh | /15min lun-ven | Alerte Telegram si heartbeat down |
| notify.sh | Apres chaque script | Envoie sur Telegram (briefing/summary/alertes) |
| sync-memory.sh | Avant/apres chaque script | Rsync bidirectionnel entre dossier writable et Syncthing |
| telegram.sh | - | Fonctions utilitaires Telegram (send_message, get_updates) |
| telegram-bot.py | - | Bot Telegram (optionnel, desactive en faveur de Terminus) |

## Rules Claude Code (`~/.claude/rules/common/`)

| Rule | Role |
|------|------|
| soul-loading.md | Au lancement : charge SOUL + primer + contexte git |
| realtime-logging.md | Logge les actions significatives pendant la session |

## Syncthing

3 dossiers synces :

| Dossier | Direction | Contenu |
|---------|-----------|---------|
| claude-memory | Mac ↔ VPS (bidirectionnel) | Memoire Claude (SOUL, primer, logs, projets) |
| projects | Mac ↔ VPS (bidirectionnel) | Repos de code |
| obsidian-vault | Mac → VPS (Send Only) | Second cerveau Obsidian (lecture seule VPS) |

## Stack

| Composant | Outil |
|-----------|-------|
| Serveur | VPS Hetzner CX23 (Ubuntu 24.04, ~3.50 EUR/mois) |
| Assistant | Claude Code CLI |
| Sync | Syncthing |
| Acces mobile | Terminus (SSH) |
| Notifications | Telegram Bot API |
| Transcription vocale | Whisper (local sur VPS) |
| Monitoring | Watchdog + alertes Telegram |
| Second cerveau | Obsidian (iCloud) |

## Setup

### Pre-requis
- Claude Code CLI installe sur Mac et VPS
- Syncthing installe sur Mac et VPS
- Compte Telegram + bot cree via @BotFather

### 1. Memoire (Mac)
```bash
mkdir -p ~/.claude/projects/-Users-$USER/memory/logs
cp memory-templates/*.template ~/.claude/projects/-Users-$USER/memory/
# Renommer les .template en .md et personnaliser
```

### 2. Rules (Mac)
```bash
cp rules/*.md ~/.claude/rules/common/
```

### 3. VPS
```bash
# Copier les scripts
scp scripts/*.sh scripts/*.py root@VPS:/root/claude-heartbeat/
chmod +x /root/claude-heartbeat/*.sh

# Configurer le cron
crontab scripts/crontab.txt

# Configurer Syncthing (3 dossiers)
# Configurer le CLAUDE.md dans le dossier projets
```

### 4. Telegram
- Creer un bot via @BotFather
- Editer telegram.sh avec le token et le chat ID
- Editer le CLAUDE.md VPS avec les infos Telegram

## Inspire par
- [OpenClaw](https://github.com/TechNickAI/openclaw-config) — SOUL.md, memory system, heartbeats
- [Recall Stack](https://github.com/keshavsuki/recall-stack) — primer.md, couches memoire
- Adapte pour Claude Code CLI + Syncthing + cron
