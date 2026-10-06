# SMASH ASCENSION — état et suite

## Livré (v1)

| Phase | Contenu | Où |
| --- | --- | --- |
| 1-2 | Audit du concept, architecture | `docs/DESIGN.md` |
| 3 | Progression : XP → niveau → puissance, 6 améliorations, Ascension | `Rules/Curves, Progress, Upgrades, Ascension` |
| 4 | 60 armes (10 zones × 6) + 23 armes de chasse, 10 raretés, capacités spéciales, 17 formes 3D | `Config/Weapons`, `Assets/WeaponRecipes` |
| 5 | Combat serveur (cadence, portée, combo, critiques, méga-critiques), mannequins, boss | `CombatService`, `DummyService`, `BossService` |
| 6 | Base du joueur : parcelle, mannequin, présentoir d'armes, 24 objets de décor, bonus de pièces | `BaseService`, `Config/Decor` |
| 7 | Monde : village + 9 royaumes thématiques (lumière, brouillard, décor, portails) | `WorldService`, `ZoneController` |
| 8 | UI : HUD, 8 menus, popups LEVEL UP / NEW WEAPON / coffres, toasts | `src/Client` |
| 9 | Feeling : animation procédurale, VFX poolés bornés par rareté, sons par clés, secousses, nombres de dégâts | `Core/Vfx`, `SwingAnimator`, `HitFeedback` |
| 10 | Sauvegarde robuste | `DataService`, `Rules/SessionLock`, `Rules/Profile` |
| 11 | Rétention : récompense quotidienne (série 7 j), quêtes jour/semaine, 33 succès, collection, coffres, boss, classements | `QuestService`, `LeaderboardService` |
| 12 | Sécurité & perf : schémas stricts, limites de débit, kick sur abus, pools | `ServerNet`, `Schemas` |
| 13 | 109 tests Lune + analyse stricte | `tests/specs` |

## Limites connues (honnêteté)

- **Jamais lancé dans Studio** : développé et vérifié par analyse stricte, tests purs et build Rojo.
  Les modèles 3D et animations (assemblés par code) doivent être jugés à l'œil ; les constantes de
  pose (`Rules/SwingPose`) et de prise en main (`Builder.attach`) sont les premiers réglages à affiner.
- Game Pass « Aura Pack » : l'attribut `Aura` est posé sur le personnage, mais le rendu client de l'aura reste à écrire.
- Pas de musique livrée (voir README). Les sons sont ceux du client Roblox, variés en hauteur.
- Les modèles sont des assemblages de pièces (style brique) ; des MeshParts importés pourront remplacer
  les recettes des armes « héros » sans changer les données ni le code de jeu.

## Vérifications à faire en jeu (checklist)

- [ ] 2-6 clients : chaque joueur a sa base, ne peut frapper que son mannequin de base.
- [ ] Frapper : numéros, combo, particules, secousse ; critique ; kill → pièces.
- [ ] Monter de niveau : popup, nouvelle arme équipée, présentoir mis à jour.
- [ ] Débloquer une zone au portail, se téléporter, boss (apparition après ~1 min si joueur présent).
- [ ] Quitter / revenir : profil conservé ; relancer plusieurs fois rapidement (verrou de session).
- [ ] Mobile : bouton HIT, lisibilité du HUD, zones sûres, perfs (SceneAudit).
- [ ] Armes : chaque archétype tenu en main (lame vers l'avant/haut), traînée, aura des hautes raretés.

## Idées pour la suite (par impact attendu)

1. **Événements temporaires** (saisonniers) : arme d'événement (`Source = "Event"` existe), zone décorée,
   quêtes dédiées — tout est data-driven.
2. **Familiers / compagnons** : multiplicateurs légers + collection (nouvelle couche de rétention).
3. **Mode coopératif de boss mondial** (MessagingService) : un boss partagé entre serveurs.
4. **Échanges d'objets cosmétiques** (pas de dégâts) avec sessions de trade serveur.
5. **Skins d'armes et auras** achetables (cosmétiques purs), prévisualisés dans le menu Armes.
6. **Analytique** : entonnoirs (première minute, premier coup → premier niveau → première arme), sources et
   puits d'économie, pour rééquilibrer sur des mesures réelles.

## Aperçus hors Studio

```bash
lune run ascension/tools/export_preview.luau        # armes, poses, props, mannequins -> build/maps/asc_*.json
python3 tools/render_view.py asc_pose_ready --eye=22,6,0 --target=0,5.5,0 --name side
```
Utilise le rasteriseur du dépôt (`tools/render_view.py`) ; les poses de frappe y sont vérifiées visuellement.
