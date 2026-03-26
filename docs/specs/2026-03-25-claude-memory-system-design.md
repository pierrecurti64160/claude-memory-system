# Claude Memory System — Design Spec

## Objectif

Reproduire les capacites cle d'OpenClaw nativement sur Claude Code, sans dependance externe. Transformer Claude en assistant personnel persistant qui :
- Se souvient de tout entre les sessions
- Ecrit des logs en temps reel (pas en fin de session)
- A une personnalite definie et coherente
- Sait ce qu'il peut faire sans demander
- Prepare le terrain pour des heartbeats autonomes (Phase 2)

## Decision architecturale cle

**Logs en temps reel, pas en fin de session.**

OpenClaw utilise un hook de fin de session pour sauvegarder un resume. Probleme : Pierre ne termine jamais ses sessions explicitement. Solution : Claude ecrit dans les logs *pendant* la conversation, au fil de l'eau. Avantages :
- Rien n'est perdu si le contexte se compresse ou le terminal ferme
- Plus granulaire qu'un resume de fin de session
- Aucune dependance sur le comportement utilisateur

**Limitation connue :** Le logging temps reel repose sur Claude qui suit une instruction CLAUDE.md. C'est best-effort : sous charge (longues sessions de code), Claude peut oublier de logger. Le Hook Stop et les instructions de self-check attenuent ce risque, mais ne l'eliminent pas. C'est acceptable — mieux vaut 80% de logs que 0%.

## Composants Phase 1

### 1. SOUL.md — Persona

**Emplacement :** `~/.claude/projects/-Users-pierrecurti/memory/SOUL.md`

**Chargement :** Reference dans MEMORY.md + regle CLAUDE.md : "Au debut de chaque session, lire `memory/SOUL.md` pour charger la persona et les standing orders."

Definit comment Claude se comporte avec Pierre :
- **Ton :** Direct, concis, zero bavardage. Pas de "bien sur !", pas de "excellente question !"
- **Role :** Executant senior. Tranche les decisions evidentes sans demander.
- **Langue :** Francais. Termes techniques en anglais.
- **Limites :** Dit quand une idee est mauvaise. Ne flatte pas.
- **Style de reponse :** Court. Lead avec l'action ou la reponse, pas le raisonnement. Si c'est faisable en 1 phrase, pas 3.

#### Standing Orders (integres dans SOUL.md)

**Claude peut faire sans demander :**
- Mettre a jour memoire, logs, MEMORY.md, USER.md
- Corriger uniquement les erreurs de syntaxe, typos, et imports manquants dans du code ecrit dans la meme session. Tout changement de logique necessite confirmation.
- Formatter/nettoyer du code dans le scope de son travail en cours
- Creer des fichiers necessaires a une tache demandee
- Alerter si quelque chose parait anormal

**Claude doit TOUJOURS demander avant :**
- Push sur un repo distant
- Modifier une strategie ou des parametres de trading
- Supprimer des fichiers existants
- Actions qui coutent de l'argent (API payantes, services)
- Actions irreversibles (reset git, drop de donnees)

### 2. USER.md enrichi — Profil

**Emplacement :** `~/.claude/projects/-Users-pierrecurti/memory/user_pierre.md` (existant, a enrichir)

Profil complet et vivant de Pierre. Sections :
- **Identite** : prenom, langue, timezone
- **Projets actifs** : robot trading, claude memory system, etc.
- **Outils** : Mac, VS Code, Claude Code, MT5, Obsidian, VPS OVH
- **Style de travail** : veut des decisions, pas des options. Pas de business talk, focus produit.
- **Connaissances** : debutant trading, entrepreneur, tech-savvy
- **Preferences** : pas d'emojis, pas de resume en fin de reponse, verification obligatoire des chiffres

Mis a jour automatiquement par Claude quand il apprend quelque chose de nouveau.

### 3. Regles CLAUDE.md — Logging temps reel + memoire proactive

**Emplacement :** Instructions ajoutees dans les regles globales Claude

Trois mecanismes :

#### 3a. Logging temps reel
Regle : "A chaque action significative dans une session, append dans `memory/logs/YYYY-MM-DD.md`"

Declencheurs (quand ecrire) :
- Decision prise (choix technique, validation de design)
- Fichier cree ou modifie de maniere significative
- Bug identifie ou resolu
- Information nouvelle apprise sur Pierre
- Changement de plan ou pivot

Format du log :
```markdown
## HH:MM — [Titre court]
- Ce qui s'est passe
- Decision prise / resultat
- Fichiers concernes (si applicable)
```

Ce qui n'est PAS logge (trop bruyant) :
- Lecture de fichiers exploratoire
- Questions de clarification
- Recherches sans resultat
- Corrections mineures (typos, formatting)

#### 3b. Memoire proactive
Regle : "Quand tu apprends quelque chose de nouveau sur Pierre ou ses projets, mets a jour la memoire immediatement (MEMORY.md + fichier concerne)"

C'est deja partiellement en place via le systeme auto-memory existant. On renforce les instructions.

#### 3c. Self-check
Regle : "Avant de repondre a l'utilisateur apres une action significative, verifie que l'action a ete loggee. Si non, logge-la maintenant."

Ceci est un filet de securite comportemental pour rattraper les oublis de logging.

#### 3d. Chargement SOUL.md
Regle : "Au debut de chaque session, lire `memory/SOUL.md` pour charger la persona et les standing orders."

### 4. Hook Stop — Filet de securite

**Emplacement :** `~/.claude/settings.json` > hooks > Stop

**Comportement :** Le hook Stop de Claude Code se declenche a chaque fin de tour (quand Claude finit de repondre), PAS a la fermeture du terminal. Il ne peut pas capturer les fermetures brutales.

Script shell minimaliste qui cree le fichier log du jour s'il n'existe pas encore :

```bash
#!/bin/bash
LOG_DIR="$HOME/.claude/projects/-Users-pierrecurti/memory/logs"
TODAY=$(date +%Y-%m-%d)
LOG_FILE="$LOG_DIR/$TODAY.md"
mkdir -p "$LOG_DIR"
if [ ! -f "$LOG_FILE" ]; then
  echo "# $TODAY" > "$LOG_FILE"
  echo "" >> "$LOG_FILE"
  echo "_Log cree a $(date +%H:%M) (aucune entree de session enregistree)._" >> "$LOG_FILE"
fi
```

Le script ne fait RIEN si le fichier existe deja (evite de polluer avec des marqueurs repetitifs). C'est juste un filet pour garantir qu'un fichier log existe chaque jour ou Claude est utilise.

### 5. HEARTBEAT.md — Checklist autonome (preparation Phase 2)

**Emplacement :** `~/.claude/projects/-Users-pierrecurti/memory/HEARTBEAT.md`

Fichier de preparation. Definit ce que Claude verifiera quand il aura acces au VPS (Phase 2). Ne sera pas execute en Phase 1, mais ecrit maintenant pour etre pret.

Checklist :
- [ ] Verifier etat des repos Git (branches, commits recents)
- [ ] Verifier logs du robot trading (positions, erreurs)
- [ ] Lister les taches en attente mentionnees dans les logs recents
- [ ] Verifier les mises a jour de dependances critiques
- [ ] Si quelque chose est anormal → alerter Pierre

### 6. Gestion du cycle de vie des logs

**Probleme :** Les fichiers `logs/YYYY-MM-DD.md` s'accumulent indefiniment.

**Solution :** Politique de rotation :
- **Logs bruts** : conserves 30 jours dans `logs/`
- **Resumes hebdomadaires** : generes dans `logs/summaries/YYYY-Wxx.md` (resume automatique des 7 jours)
- **Regle de lecture** : Claude ne lit que les 7 derniers jours de logs bruts sauf si on lui demande explicitement d'aller plus loin
- **Archivage** : les logs de plus de 30 jours sont deplacables manuellement (pas automatise en Phase 1)

Note : la generation des resumes hebdomadaires sera automatisee en Phase 2 (heartbeat/cron). En Phase 1, Pierre peut le demander manuellement.

### 7. Sessions concurrentes

**Probleme :** Si Pierre ouvre plusieurs terminaux Claude en meme temps, les logs s'entrelacent dans le meme fichier.

**Solution :** Chaque entree de log inclut un identifiant de contexte :

```markdown
## HH:MM [projet-name] — Titre court
```

Le nom du projet (ou du dossier de travail) suffit a distinguer les sessions. Exemple :
```markdown
## 14:30 [robot-trading] — Fix du trailing stop
## 14:32 [claude-memory] — Spec v2 approuvee
```

## Structure de fichiers resultante

```
~/.claude/projects/-Users-pierrecurti/memory/
  MEMORY.md                    # Index (existant, enrichi)
  SOUL.md                      # NEW — Persona + Standing Orders
  user_pierre.md               # Existant, enrichi
  feedback_style.md            # Existant
  feedback_verification.md     # Existant
  feedback_zettel_*.md         # Existant
  project_*.md                 # Existant
  reference_*.md               # Existant
  HEARTBEAT.md                 # NEW — Preparation Phase 2
  logs/
    2026-03-25.md              # NEW — Log du jour
    2026-03-26.md              # Cree automatiquement chaque jour
    ...
    summaries/
      2026-W13.md              # Resume hebdomadaire (Phase 2 auto, Phase 1 manuel)
```

## Ce qui est hors scope Phase 1

- Recherche semantique (inutile avec le volume actuel)
- VPS / Syncthing / heartbeats actifs (Phase 2)
- Multi-canal (pas le meme usage que OpenClaw)
- IDENTITY.md / avatar (gadget)
- BOOT.md (utile seulement avec VPS)
- Rotation automatique des logs (Phase 2)

## Securite

- Les fichiers de logs et memoire contiennent des details de projets en clair. Acceptable en local.
- Phase 2 (sync VPS) : traiter les fichiers synces comme donnees sensibles (SSH only, pas de HTTP).
- Ne jamais logger de secrets (cles API, mots de passe) dans les logs ou la memoire.

## Metriques de succes

Phase 1 est reussie quand :
1. Claude ecrit dans les daily logs sans qu'on lui demande (verifiable : Pierre regarde le log en fin de journee)
2. Le SOUL.md donne un comportement coherent entre les sessions
3. USER.md se met a jour tout seul quand Claude apprend quelque chose
4. Le Hook Stop cree les fichiers log automatiquement
5. Pierre retrouve facilement ce qui s'est passe les jours precedents en lisant les logs
6. Les sessions concurrentes produisent des logs lisibles grace aux identifiants de contexte
