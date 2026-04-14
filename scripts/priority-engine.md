# Moteur de priorites — Chief of Staff

Ce fichier est une reference injectee dans les prompts Claude. Il definit comment calculer, classer et presenter les priorites quotidiennes de Pierre.

---

## 1. Modele de scoring

Chaque tache est evaluee sur 4 axes, chacun de 0 a 10.

### Revenue (potentiel argent direct)

Mesure l'impact financier immediat : MRR, deals, factures, relances clients.

| Situation | Score |
|-----------|-------|
| Deal > 2 000 EUR en jeu | 8-10 |
| Deal 500-2 000 EUR | 5-7 |
| Action qui debloque un paiement | 6-8 |
| Tache technique sans lien direct avec du cash | 0-2 |
| Maintenance, refactor, cleanup | 0-1 |

### Urgence (pression temporelle + jours d'attente)

Mesure la deadline et le temps ecoule depuis que la tache est apparue. Chaque jour ou une tache est ignoree, l'urgence monte de +1 (plafond a 10).

| Situation | Score de base |
|-----------|---------------|
| Deadline < 24h | 10 |
| Deadline < 48h | 8-9 |
| Deadline cette semaine | 5-7 |
| Pas de deadline explicite, mais en retard | 4-6 |
| "Un jour" / pas de pression | 1-2 |

Formule d'escalade : `urgence_effective = min(10, urgence_base + jours_ignores)`

### Inverse effort (rapidite d'execution)

Plus c'est rapide a faire, plus le score est eleve. Les micro-taches sont boostees.

| Effort estime | Score |
|---------------|-------|
| < 2 min (message, reponse, clic) | 10 |
| 2-10 min | 8 |
| 10-30 min | 6 |
| 30 min - 2h | 4 |
| 2h - 4h | 3 |
| 4h+ (session de dev complete) | 1-2 |

### Dependency (impact sur les autres taches)

Mesure combien de choses sont bloquees si cette tache n'est pas faite.

| Situation | Score |
|-----------|-------|
| 3+ taches/personnes bloquees par ceci | 8-10 |
| 2 taches bloquees | 6-7 |
| 1 tache bloquee | 4-5 |
| Bloque un client ou partenaire | 7-9 |
| Rien n'est bloque | 1-2 |

---

## 2. Formule

```
score = revenue + urgence + inverse_effort + dependency
```

Score maximum : 40. Score minimum : 4.

Pas de coefficients, pas de poids. La simplicite est deliberee — les boosters gerent les cas speciaux.

---

## 3. Boosters (multiplicateurs et escalades)

Les boosters s'appliquent apres le calcul du score de base.

### Quick money (micro-tache a fort revenu)

Si `inverse_effort >= 8` ET `revenue >= 5` :
```
score_final = score * 1.5
```
Raison : un message de 2 min qui debloque 2 000 EUR doit etre en tete. Toujours.

### Deadline critique

Si deadline < 48h :
```
score_final = score * 1.5
```
Les deux boosters sont cumulables. Un message urgent a fort revenu avec deadline demain peut depasser 40.

### Escalade par anciennete

- Tache ignoree 3+ jours consecutifs : ajouter une note d'escalade.
  Format : `[Jour N] Decide : tu fais ou on enleve.`
- Tache ignoree 5+ jours consecutifs : escalade maximale.
  Format : `BLOQUE (jour N) — Action requise ou suppression.`

L'escalade ne modifie pas le score numerique. Elle ajoute un signal visuel pour forcer une decision.

---

## 4. Categories de taches

Chaque tache appartient a une categorie. La categorie influence l'effort typique et le comportement de tri.

### COMMUNICATION
Messages, relances, appels, reponses.
- Effort typique : < 2 min a 10 min
- Revenue potentiel : souvent eleve (relance = argent)
- Exemples : repondre a un client, relancer un devis, confirmer un rdv

### DEV
Code, design, build, debug, deploy.
- Effort typique : 2h a 8h
- Revenue potentiel : moyen (indirect)
- Exemples : finir une feature, fixer un bug, deployer un site

### ADMIN
Commits, cleanup, docs, config, organisation.
- Effort typique : 10-30 min
- Revenue potentiel : faible
- Exemples : nettoyer un repo, mettre a jour des docs, configurer un service

### CHECK
Verifier des services, SSH robot, monitoring.
- Effort typique : < 5 min
- Revenue potentiel : variable (un robot down = urgence haute)
- Exemples : verifier que le robot tourne, checker les logs, verifier un deploy

---

## 5. Regles de tri

### Regle COMMUNICATION > DEV

Si une tache COMMUNICATION et une tache DEV sont a moins de 5 points d'ecart, la tache COMMUNICATION passe devant.

Raison : Pierre a tendance a coder et oublier les messages. Les messages sont rapides et souvent a fort impact financier. Cette regle corrige ce biais.

### Maximum 3 priorites par jour

Ne jamais presenter plus de 3 priorites. Si Pierre finit les 3, recalculer a partir des taches restantes et presenter 3 nouvelles.

### Pas de repetition textuelle

Ne jamais presenter la meme tache avec le meme texte 3 jours consecutifs. Au jour 2, reformuler. Au jour 3, escalader ou proposer la suppression.

### Texte zero-friction

Pour les taches COMMUNICATION, toujours inclure le texte a copier-coller. Pierre ne doit pas avoir a reflechir a la formulation — juste envoyer.

---

## 6. Format de sortie

Quand tu calcules les priorites, produis exactement ce format :

```
## Priorite #1 — [Titre] ([effort estime])
[Texte copy-paste si applicable]
-> Score: [N]/40 | Revenue: [N] | Urgence: [N] | Effort: [N] | Dependency: [N]
[Contexte: pourquoi c'est important maintenant]

## Priorite #2 — [Titre] ([effort estime])
[Texte copy-paste si applicable]
-> Score: [N]/40 | Revenue: [N] | Urgence: [N] | Effort: [N] | Dependency: [N]
[Contexte: pourquoi c'est important maintenant]

## Priorite #3 — [Titre] ([effort estime])
[Texte copy-paste si applicable]
-> Score: [N]/40 | Revenue: [N] | Urgence: [N] | Effort: [N] | Dependency: [N]
[Contexte: pourquoi c'est important maintenant]
```

Notes sur le format :
- Le score affiche peut depasser 40 si des boosters s'appliquent. Afficher le score reel, pas plafonner.
- L'effort estime est entre parentheses dans le titre : `(2 min)`, `(30 min)`, `(3h)`.
- Le contexte est une phrase, pas un paragraphe. Pourquoi maintenant, pas pourquoi en general.
- Si une escalade s'applique, l'ajouter avant le score sur sa propre ligne.

---

## 7. Sources de donnees

Pour calculer les priorites, consulter dans cet ordre :

1. `memory/primer.md` — etat courant, taches en cours, prochaine action
2. Vault Obsidian `1 PROJECT/` — projets actifs, deadlines, notes de reunion
3. Logs recents `memory/logs/` — ce qui a ete fait, ce qui traine
4. Messages Telegram recents — demandes de Pierre non traitees

Si une tache apparait dans plusieurs sources, c'est un signal de haute priorite.

---

## 8. Exemples concrets

### Exemple 1 : Message client rapide
- Tache : Relancer Nicolas pour le devis HousePark
- Categorie : COMMUNICATION
- Revenue : 7 (deal potentiel > 1 000 EUR)
- Urgence : 6 (devis envoye il y a 4 jours, pas de reponse)
- Inverse effort : 10 (message de 2 min)
- Dependency : 3 (rien de bloque directement)
- Score de base : 26
- Booster quick money : oui (effort >= 8 ET revenue >= 5) -> 26 * 1.5 = 39
- Score final : 39

### Exemple 2 : Session de dev
- Tache : Finir le dashboard Sam Barber v2
- Categorie : DEV
- Revenue : 5 (client actif, facturation mensuelle)
- Urgence : 4 (pas de deadline immediate)
- Inverse effort : 2 (session de 4h+)
- Dependency : 2 (Sam attend mais pas bloque)
- Score de base : 13
- Pas de booster
- Score final : 13

### Exemple 3 : Check robot
- Tache : Verifier que le robot FTMO tourne
- Categorie : CHECK
- Revenue : 3 (pas de revenu direct mais protege le capital)
- Urgence : 8 (pas verifie depuis 2 jours)
- Inverse effort : 9 (SSH + check en 3 min)
- Dependency : 1 (rien bloque)
- Score de base : 21
- Pas de booster
- Score final : 21

Dans cet exemple, la relance Nicolas (39) passe en #1, le check robot (21) en #2, et le dev Sam (13) en #3. Le message de 2 min passe avant la session de 4h. C'est le comportement voulu.
