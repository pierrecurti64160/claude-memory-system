# Real-Time Session Logging

## Regle principale

A chaque action significative dans une session, append dans `memory/logs/YYYY-MM-DD.md` (chemin complet : `~/.claude/projects/-Users-pierrecurti/memory/logs/YYYY-MM-DD.md`).

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
