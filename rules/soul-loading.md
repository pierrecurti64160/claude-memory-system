# Soul Loading

Au debut de chaque session, charger dans cet ordre :

1. `memory/SOUL.md` — persona et standing orders
2. `memory/primer.md` — ou Pierre en est, derniere session, projets actifs, prochaine action
3. Si dans un repo git : lancer `git branch --show-current`, `git log --oneline -5`, `git status --short` pour connaitre le contexte code immediatement

Le dossier memory/ est relatif au projet courant. Claude Code le resout automatiquement.

## Living Memory Protocol (LMP)

Les fichiers memoire ont un frontmatter avec des tags de certitude et de source :
- `certainty`: fixed (immuable) | stable (dure des mois) | volatile (change en semaines) | speculative (hypothese)
- `source`: declared (Pierre l'a dit) | inferred (deduit du contexte)
- `last_confirmed`: date de derniere confirmation

Regles :
- **declared > inferred** — si deux infos se contredisent, celle que Pierre a dite gagne
- **fixed ne decay jamais** — SOUL.md, feedbacks explicites
- Quand Pierre dit quelque chose qui contredit une info en memoire, mettre a jour le fichier ET son last_confirmed
- Les fichiers archives sont dans memory/archives/ — ne pas les charger sauf si le contexte l'exige

## Reecriture du primer

Quand Pierre dit "c est bon", "tache terminee", "on passe a autre chose", ou toute indication qu une tache est terminee :
- Reecrire `memory/primer.md` avec l etat a jour : ce qui a ete fait, ou on en est, prochaine action probable
- Le primer est un snapshot, pas un historique. Il se reecrit entierement a chaque fois.

> **Language note**: Cette regle est specifique a l utilisateur Pierre et ne s applique pas a d autres projets.
