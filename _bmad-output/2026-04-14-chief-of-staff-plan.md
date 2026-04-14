# Chief of Staff — Plan d'implementation

> **For agentic workers:** Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Transformer le systeme de monitoring passif en Chief of Staff actif avec priorisation dynamique, coaching, et boucle reactive Telegram ↔ Obsidian.

**Architecture:** Priority Engine (fichier memoire) → Briefing v2 (3 priorites scorees → daily note + Telegram) → Heartbeat silence → Summary v2 (score + patterns) → Bot Telegram v2 (commandes interactives) → Watcher (boucle reactive) → Weekly v2 (analyse comportementale).

**Tech Stack:** Bash, Python 3, Claude CLI, inotifywait, systemd, Telegram Bot API, Obsidian markdown

**Emplacement code:** `/Users/pierrecurti/_bmad/sites/claude-memory-system/scripts/`
**Deploy cible:** `/root/claude-heartbeat/` sur VPS Hetzner (91.99.19.182)
**Vault VPS:** `/root/obsidian-vault/`
**Daily notes:** `/root/obsidian-vault/5 TOOLS/Daily/YYYY-MM-DD.md`

---

### Task 1: Priority Engine

**Files:**
- Create: `scripts/priority-engine.md` (fichier memoire lu par tous les prompts)

Le modele de scoring que Claude lit a chaque calcul de priorites.

---

### Task 2: Daily Note Template

**Files:**
- Create: `scripts/daily-note-template.md` (template utilise par briefing.sh)

Format de la daily note Obsidian que le briefing ecrit chaque matin.

---

### Task 3: Heartbeat v2 — Silence sauf alerte

**Files:**
- Modify: `scripts/heartbeat.sh` (rewrite complet)

Ajouter check bash avant appel Claude. Si aucun fichier modifie ET aucune deadline proche → exit 0 silencieux.

---

### Task 4: Briefing v2 — 3 priorites scorees

**Files:**
- Modify: `scripts/briefing.sh` (rewrite complet)
- Modify: `scripts/notify.sh` (adapter pour daily note)

Nouveau prompt qui produit 3 priorites scorees, ecrit la daily note Obsidian, detecte les patterns.

---

### Task 5: Summary v2 — Score + patterns

**Files:**
- Modify: `scripts/summary.sh` (rewrite complet)

Score X/3 vs plan du matin, analyse comportementale, mise a jour daily note.

---

### Task 6: Bot Telegram v2 — Commandes interactives

**Files:**
- Modify: `scripts/telegram-bot.py` (ajout commandes + vault search)

Commandes: fait, quoi, status. Conversation enrichie avec recherche vault.

---

### Task 7: Watcher — Boucle reactive

**Files:**
- Create: `scripts/watcher.py` (nouveau daemon)
- Create: `scripts/watcher.service` (systemd unit)

Detecte changements vault → recalcule → Telegram + daily note.

---

### Task 8: Weekly v2 — Analyse comportementale

**Files:**
- Modify: `scripts/weekly.sh` (prompt enrichi)

Patterns hebdo, ratio dev/communication, taux completion.

---

### Task 9: Deploy

**Files:**
- Modify: `scripts/crontab.txt`
- Create: `scripts/deploy.sh` (rsync + crontab + systemd)

Deployer tout sur le VPS, activer watcher, redemarrer bot.
