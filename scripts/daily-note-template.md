# Template Daily Note — Chief of Staff

Ce fichier est la reference de format pour les daily notes generees par `briefing.sh`.
La note du jour est creee dans le vault Obsidian a l'emplacement :
`5 TOOLS/Notes quotidienne/YYYY-MM-DD.md`

Les placeholders entre `{{...}}` sont remplaces par le script de briefing.

---

## Template

```markdown
# {{DATE}}

## Priorite #1 — {{TITRE_1}} ({{EFFORT_1}})
{{COPYPASTE_1}}
{{ESCALADE_1}}
-> Score: {{SCORE_1}}/40 | Revenue: {{REVENUE_1}} | Urgence: {{URGENCE_1}} | Effort: {{EFFORT_INV_1}} | Dependency: {{DEPENDENCY_1}}
{{CONTEXTE_1}}

## Priorite #2 — {{TITRE_2}} ({{EFFORT_2}})
{{COPYPASTE_2}}
{{ESCALADE_2}}
-> Score: {{SCORE_2}}/40 | Revenue: {{REVENUE_2}} | Urgence: {{URGENCE_2}} | Effort: {{EFFORT_INV_2}} | Dependency: {{DEPENDENCY_2}}
{{CONTEXTE_2}}

## Priorite #3 — {{TITRE_3}} ({{EFFORT_3}})
{{COPYPASTE_3}}
{{ESCALADE_3}}
-> Score: {{SCORE_3}}/40 | Revenue: {{REVENUE_3}} | Urgence: {{URGENCE_3}} | Effort: {{EFFORT_INV_3}} | Dependency: {{DEPENDENCY_3}}
{{CONTEXTE_3}}

---

## Completees
{{COMPLETEES}}

## Score du jour
{{SCORE_JOUR}}

## Contexte
{{CONTEXTE_GENERAL}}
```

---

## Description des placeholders

### Bloc priorites (repete 3 fois : _1, _2, _3)

| Placeholder | Description | Exemple |
|-------------|-------------|---------|
| `{{DATE}}` | Date du jour au format YYYY-MM-DD | 2026-04-14 |
| `{{TITRE_N}}` | Titre court de la tache | Relancer Nicolas devis HousePark |
| `{{EFFORT_N}}` | Effort estime entre parentheses | 2 min |
| `{{COPYPASTE_N}}` | Texte a copier-coller (taches COMMUNICATION). Vide si non applicable. | Salut Nicolas, je reviens... |
| `{{ESCALADE_N}}` | Note d'escalade si la tache est ignoree 3+ jours. Vide sinon. | [Jour 4] Decide : tu fais ou on enleve. |
| `{{SCORE_N}}` | Score final (apres boosters) | 39 |
| `{{REVENUE_N}}` | Score revenue (0-10) | 7 |
| `{{URGENCE_N}}` | Score urgence (0-10) | 6 |
| `{{EFFORT_INV_N}}` | Score inverse effort (0-10) | 10 |
| `{{DEPENDENCY_N}}` | Score dependency (0-10) | 3 |
| `{{CONTEXTE_N}}` | Une phrase : pourquoi cette tache maintenant | Devis envoye il y a 4 jours, pas de reponse. |

### Bloc completees

| Placeholder | Description | Rempli par |
|-------------|-------------|------------|
| `{{COMPLETEES}}` | Liste des taches terminees dans la journee. Format : `- [x] Titre (HH:MM)` par tache. Vide le matin. | `summary.sh` ou `watcher.py` quand Pierre marque une tache comme faite |

### Bloc score du jour

| Placeholder | Description | Rempli par |
|-------------|-------------|------------|
| `{{SCORE_JOUR}}` | Bilan de fin de journee. Nombre de taches completees / presentees. Commentaire sur la journee. | `summary.sh` a 20h |

Format du score du jour :
```
Completees : N/3
Score total realise : X points
[Commentaire optionnel sur les patterns observes]
```

### Bloc contexte general

| Placeholder | Description | Rempli par |
|-------------|-------------|------------|
| `{{CONTEXTE_GENERAL}}` | Deadlines a venir, patterns observes, notes du briefing. Liste a puces. | `briefing.sh` le matin |

Format du contexte :
```
- [deadline] Description
- [pattern] Observation
- [note] Information pertinente
```

---

## Regles de generation

1. Le briefing du matin cree la note avec les 3 priorites et le contexte. Les sections Completees et Score du jour sont vides.
2. Quand Pierre complete une tache (via Telegram ou detection automatique), `watcher.py` ajoute une ligne dans la section Completees.
3. Le summary du soir (`summary.sh` a 20h) remplit le Score du jour et ajoute un bilan.
4. Si Pierre finit ses 3 priorites avant le soir, le systeme recalcule et ajoute de nouvelles priorites sous les precedentes (qui restent visibles comme completees).
5. La note ne doit jamais etre ecrasee — les ajouts sont en append dans les sections appropriees.
6. Si aucune tache n'est completee dans la journee, le summary du soir le note sans jugement : `Completees : 0/3. Pas de taches terminees aujourd'hui.`
