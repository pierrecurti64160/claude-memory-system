# Claude Memory System Phase 1 — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Installer le systeme de memoire persistante OpenClaw-like sur Claude Code en local (Phase 1).

**Architecture:** Fichiers markdown dans `~/.claude/projects/-Users-pierrecurti/memory/`, regles comportementales dans `~/.claude/rules/`, hook Stop dans `~/.claude/settings.json`. Aucune dependance externe.

**Tech Stack:** Shell scripts, Markdown, Claude Code hooks system, Claude Code rules system.

**Spec:** `docs/specs/2026-03-25-claude-memory-system-design.md`

---

## File Map

| Action | Fichier | Responsabilite |
|--------|---------|----------------|
| Create | `~/.claude/projects/-Users-pierrecurti/memory/SOUL.md` | Persona + Standing Orders |
| Modify | `~/.claude/projects/-Users-pierrecurti/memory/user_pierre.md` | Profil enrichi |
| Modify | `~/.claude/projects/-Users-pierrecurti/memory/MEMORY.md` | Index mis a jour |
| Create | `~/.claude/rules/common/realtime-logging.md` | Regle logging temps reel |
| Create | `~/.claude/rules/common/soul-loading.md` | Regle chargement SOUL.md |
| Modify | `~/.claude/settings.json` | Hook Stop |
| Create | `~/.claude/projects/-Users-pierrecurti/memory/HEARTBEAT.md` | Prep Phase 2 |
| Create | `~/.claude/projects/-Users-pierrecurti/memory/logs/` | Dossier logs |
| Create | `~/.claude/projects/-Users-pierrecurti/memory/logs/summaries/` | Dossier resumes |

---

### Task 1: Creer SOUL.md

**Files:**
- Create: `~/.claude/projects/-Users-pierrecurti/memory/SOUL.md`

- [ ] **Step 1: Creer SOUL.md avec persona et standing orders**

```markdown
---
name: SOUL - Persona Claude
description: Definit le comportement, ton, et autorite de Claude pour Pierre. Lu au debut de chaque session.
type: user
---

# SOUL — Persona

## Ton
- Direct, concis, zero bavardage
- Pas de "bien sur !", "excellente question !", "je serais ravi de..."
- Lead avec l'action ou la reponse, pas le raisonnement
- Si c'est faisable en 1 phrase, pas 3

## Role
- Executant senior. Tranche les decisions evidentes sans demander.
- Dit quand une idee est mauvaise. Ne flatte pas.
- Approche avocat du diable quand c'est pertinent.

## Langue
- Francais. Termes techniques en anglais.
- Pas d'emojis. Majuscules minimales.

## Standing Orders

### Sans demander
- Mettre a jour memoire, logs, MEMORY.md, USER.md
- Corriger erreurs de syntaxe, typos, imports manquants dans du code ecrit dans la meme session (PAS de changement de logique)
- Formatter/nettoyer du code dans le scope du travail en cours
- Creer des fichiers necessaires a une tache demandee
- Alerter si quelque chose parait anormal

### Toujours demander avant
- Push sur un repo distant
- Modifier une strategie ou des parametres de trading
- Supprimer des fichiers existants
- Actions qui coutent de l'argent (API payantes, services)
- Actions irreversibles (reset git, drop de donnees)
```

- [ ] **Step 2: Verifier que le fichier existe**

Run: `cat ~/.claude/projects/-Users-pierrecurti/memory/SOUL.md | head -5`
Expected: les 5 premieres lignes du frontmatter

---

### Task 2: Enrichir user_pierre.md

**Files:**
- Modify: `~/.claude/projects/-Users-pierrecurti/memory/user_pierre.md`

- [ ] **Step 1: Ajouter les sections manquantes au profil**

Ajouter apres la section "Second cerveau" :

```markdown
## Outils
- **Dev** : Mac (macOS), VS Code, Claude Code CLI, Terminal zsh
- **Trading** : MetaTrader 5 (Wine), backtest Python custom, VPS OVH (Ubuntu)
- **Notes** : Obsidian (iCloud sync)
- **Projets** : Tous dans /Users/pierrecurti/_bmad/sites/

## Timezone
- Europe/Paris (CET/CEST)

## Projets actifs (mars 2026)
- Robot Trading EA MQL5 — strategie Liquidity Hunt sur Gold (v14 live, v15 en reserve)
- Claude Memory System — reproduire OpenClaw nativement sur Claude Code
- S.T.E.E.L. — formation trading high-ticket
- Carnet — app journal trading (Next.js + Supabase)
- Salons de coiffure — Everyone Speaks, en transition

## Style de travail
- Veut des decisions, pas des options
- Focus produit, pas business talk
- Pas de resume en fin de reponse (il sait lire le diff)
- Verification obligatoire : JAMAIS de chiffres sans output brut
- Sonnet pour dev courant, Opus pour architecture
```

- [ ] **Step 2: Verifier la coherence du fichier**

Run: `wc -l ~/.claude/projects/-Users-pierrecurti/memory/user_pierre.md`
Expected: ~55-65 lignes

---

### Task 3: Creer la regle de logging temps reel

**Files:**
- Create: `~/.claude/rules/common/realtime-logging.md`

- [ ] **Step 1: Creer la regle**

```markdown
# Real-Time Session Logging

## Regle principale

A chaque action significative dans une session, append dans `memory/logs/YYYY-MM-DD.md` (chemin relatif a `~/.claude/projects/-Users-pierrecurti/`).

## Format

```
## HH:MM [contexte] — Titre court
- Ce qui s'est passe
- Decision prise / resultat
- Fichiers concernes (si applicable)
```

Le `[contexte]` est le nom du projet ou dossier de travail actuel (ex: `[robot-trading]`, `[claude-memory]`, `[general]`).

## Quand logger

- Decision prise (choix technique, validation de design)
- Fichier cree ou modifie de maniere significative
- Bug identifie ou resolu
- Information nouvelle apprise sur l'utilisateur
- Changement de plan ou pivot

## Quand NE PAS logger

- Lecture de fichiers exploratoire
- Questions de clarification
- Recherches sans resultat
- Corrections mineures (typos, formatting)

## Self-check

Avant de repondre a l'utilisateur apres une action significative, verifie que l'action a ete loggee. Si non, logge-la maintenant.

## Regle de lecture des logs

- Ne lire que les 7 derniers jours de logs bruts sauf demande explicite
- Les resumes hebdomadaires sont dans `memory/logs/summaries/YYYY-Wxx.md`

## Securite

- Ne JAMAIS logger de secrets (cles API, mots de passe, tokens)
```

- [ ] **Step 2: Verifier que le fichier existe**

Run: `ls -la ~/.claude/rules/common/realtime-logging.md`
Expected: fichier present

---

### Task 4: Creer la regle de chargement SOUL.md

**Files:**
- Create: `~/.claude/rules/common/soul-loading.md`

- [ ] **Step 1: Creer la regle**

```markdown
# Soul Loading

Au debut de chaque session, lire `memory/SOUL.md` (chemin relatif a `~/.claude/projects/-Users-pierrecurti/`) pour charger la persona et les standing orders.

Ce fichier definit :
- Le ton et le style de communication
- Ce que Claude peut faire sans demander (standing orders)
- Ce qui necessite toujours une confirmation

> **Language note**: Cette regle est specifique a l'utilisateur Pierre et ne s'applique pas a d'autres projets.
```

- [ ] **Step 2: Verifier que le fichier existe**

Run: `ls -la ~/.claude/rules/common/soul-loading.md`
Expected: fichier present

---

### Task 5: Configurer le Hook Stop

**Files:**
- Modify: `~/.claude/settings.json`

- [ ] **Step 1: Creer le dossier logs et summaries**

```bash
mkdir -p ~/.claude/projects/-Users-pierrecurti/memory/logs/summaries
```

- [ ] **Step 2: Ajouter le hook Stop dans settings.json**

Ajouter dans la section `hooks` de `~/.claude/settings.json` :

```json
"Stop": [
  {
    "matcher": "",
    "hooks": [
      {
        "type": "command",
        "command": "LOG_DIR=\"$HOME/.claude/projects/-Users-pierrecurti/memory/logs\" && TODAY=$(date +%Y-%m-%d) && LOG_FILE=\"$LOG_DIR/$TODAY.md\" && mkdir -p \"$LOG_DIR\" && [ ! -f \"$LOG_FILE\" ] && echo \"# $TODAY\" > \"$LOG_FILE\" && echo '' >> \"$LOG_FILE\" && echo '_Log cree a '$(date +%H:%M)' (aucune entree de session enregistree)._' >> \"$LOG_FILE\" || true"
      }
    ]
  }
]
```

- [ ] **Step 3: Verifier que le JSON est valide**

Run: `python3 -c "import json; json.load(open('$HOME/.claude/settings.json'))"`
Expected: pas d'erreur

---

### Task 6: Mettre a jour MEMORY.md

**Files:**
- Modify: `~/.claude/projects/-Users-pierrecurti/memory/MEMORY.md`

- [ ] **Step 1: Ajouter SOUL.md et HEARTBEAT.md a l'index**

Ajouter une section "System" en haut, apres le titre :

```markdown
## System
- [SOUL - Persona](SOUL.md) — Ton, role, standing orders. Lu au debut de chaque session.
- [HEARTBEAT - Checklist](HEARTBEAT.md) — Ce que Claude verifie en mode autonome (Phase 2)
```

- [ ] **Step 2: Verifier l'index**

Run: `head -10 ~/.claude/projects/-Users-pierrecurti/memory/MEMORY.md`
Expected: sections System et User visibles

---

### Task 7: Creer HEARTBEAT.md

**Files:**
- Create: `~/.claude/projects/-Users-pierrecurti/memory/HEARTBEAT.md`

- [ ] **Step 1: Creer le fichier**

```markdown
---
name: HEARTBEAT - Checklist autonome
description: Ce que Claude verifie en mode autonome (heartbeat). Preparation Phase 2, pas actif en Phase 1.
type: reference
---

# Heartbeat Checklist

> Ce fichier sera utilise en Phase 2 quand Claude tournera sur le VPS. En Phase 1, il sert de reference.

## Verifications periodiques

- [ ] **Repos Git** : branches ouvertes, commits recents, PRs en attente
- [ ] **Robot trading** : logs MT5, positions ouvertes, erreurs recentes
- [ ] **Taches en attente** : scanner les logs des 7 derniers jours pour les TODOs non resolus
- [ ] **Dependances** : mises a jour critiques de securite dans les projets actifs
- [ ] **Anomalies** : si quelque chose est anormal → alerter Pierre immediatement

## Frequence prevue
- Toutes les 30 minutes (configurable)
- Briefing matinal a 8h
- Resume quotidien a 20h

## Regles
- Si rien a signaler : ne rien envoyer (pas de bruit)
- Si anomalie : alerter avec contexte et suggestion d'action
```

- [ ] **Step 2: Verifier que le fichier existe**

Run: `ls -la ~/.claude/projects/-Users-pierrecurti/memory/HEARTBEAT.md`
Expected: fichier present

---

### Task 8: Test d'integration — Premier log

- [ ] **Step 1: Creer manuellement le premier log du jour pour valider le format**

Creer `~/.claude/projects/-Users-pierrecurti/memory/logs/2026-03-25.md` :

```markdown
# 2026-03-25

## 16:30 [claude-memory] — Phase 1 implementee
- SOUL.md cree avec persona + standing orders
- USER.md enrichi avec outils, timezone, projets actifs
- Regles de logging temps reel ajoutees dans rules/common/
- Hook Stop configure dans settings.json
- HEARTBEAT.md cree (prep Phase 2)
- MEMORY.md mis a jour avec index System
```

- [ ] **Step 2: Verifier la structure complete**

```bash
echo "=== SOUL ===" && head -3 ~/.claude/projects/-Users-pierrecurti/memory/SOUL.md && echo "" && echo "=== HEARTBEAT ===" && head -3 ~/.claude/projects/-Users-pierrecurti/memory/HEARTBEAT.md && echo "" && echo "=== LOG ===" && cat ~/.claude/projects/-Users-pierrecurti/memory/logs/2026-03-25.md && echo "" && echo "=== RULES ===" && ls ~/.claude/rules/common/realtime-logging.md ~/.claude/rules/common/soul-loading.md && echo "" && echo "=== HOOK ===" && python3 -c "import json; d=json.load(open('$HOME/.claude/settings.json')); print('Stop hook:', 'present' if 'Stop' in d.get('hooks',{}) else 'MISSING')"
```

Expected: tous les fichiers presents, hook Stop confirme

---

### Task 9: Mettre a jour la memoire projet

- [ ] **Step 1: Mettre a jour project_claude_memory_system.md**

Changer le statut de "En phase de planification" a "Phase 1 implementee" et documenter ce qui a ete fait.
