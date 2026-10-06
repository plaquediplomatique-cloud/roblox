# SMASH ASCENSION

Jeu Roblox de progression de frappe, style jouet / brique : **frapper → XP → niveau → arme →
frapper plus fort → zone suivante → Ascension**. Luau strict, Rojo, logique pure testée avec Lune.
Conception et choix : [`docs/DESIGN.md`](docs/DESIGN.md) · suite prévue : [`docs/ROADMAP.md`](docs/ROADMAP.md).

## Lancer

```bash
rokit install                  # rojo, stylua, luau-lsp, lune (voir rokit.toml)
./ascension/scripts/build.sh   # build/SmashAscension.rbxl -> ouvrir dans Studio
# ou, en synchro live :
rojo serve ascension.project.json      # puis Studio : Plugins → Rojo → Connect
```

*Test → Clients and Servers* pour tester plusieurs joueurs. Sans « Enable Studio Access to API
Services », les profils vivent en mémoire (non persistants) : le jeu reste jouable.

## Portes qualité

```bash
stylua ascension                       # formatage
./ascension/scripts/analyze.sh         # luau-lsp strict : 0 erreur, 0 avertissement
./ascension/scripts/test.sh            # tests Lune (règles, courbes, profil, réseau, recettes d'assets)
./ascension/scripts/build.sh           # build Rojo
```

## Ce qu'on peut changer sans toucher à la logique

| Je veux… | Je modifie |
| --- | --- |
| ajouter une arme | une ligne dans `src/Shared/Config/Weapons.luau` (stats dérivées automatiquement) |
| une nouvelle forme d'arme | une recette dans `Assets/WeaponRecipes.luau` + une ligne dans `Config/Archetypes.luau` |
| rééquilibrer la progression | `Config/Game.luau`, `Config/Upgrades.luau`, `Rules/Curves.luau` ; la **simulation de rythme** (`tests/specs/pacing.luau`) imprime le temps par niveau |
| un nouveau décor / prop | une recette dans `Assets/Props.luau` + une ligne dans `Config/Decor.luau` |
| une nouvelle zone | `Config/Zones.luau` (+ 6 armes dans `Config/Weapons.luau`, un accessoire de mannequin dans `Assets/Dummies.luau`) |
| une quête / un succès | `Config/Quests.luau` / `Config/Achievements.luau` |
| un son | `Config/Sounds.luau` (clés logiques, jamais d'ID dans le code) |
| une couleur / taille d'UI | `Config/Theme.luau` |

## Architecture en bref

- **Serveur autoritaire.** Le client envoie des *intentions* (`Swing`, `Equip`, `BuyUpgrade`…) ;
  chaque remote traverse limite de débit → schéma `Guard` → exécution protégée
  (`Server/Net/ServerNet.luau`). Dégâts, critiques, combo, XP, pièces, butin, achats : serveur seul.
- **Un seul écrivain par donnée** : `ProgressionService` (XP/niveau/pièces), `WeaponService`
  (armes), `ShopService` (achats), `DummyService` (PV). Les systèmes se parlent par
  `Server/GameEvents.luau`.
- **Règles pures** (`src/Shared/Rules`) : testées hors moteur ; le client en réutilise les mêmes
  fonctions pour afficher dégâts/puissance (aucun désaccord écran/serveur).
- **Assets par code** : recettes de pièces (`Assets/*`) → un seul builder. 17 archétypes d'armes,
  ~50 props modulaires, 10 mannequins, monde de 10 zones construit déterministement.
- **Sauvegarde** : verrou de session, `UpdateAsync`, retries, autosave étalé, `BindToClose`,
  migrations + assainissement (`Rules/Profile`, `Rules/SessionLock`).

## À configurer avant publication

1. **Game Passes / produits** : renseigner les IDs dans `Config/Products.luau` (0 = inactif).
2. **Musique et sons finaux** : `Config/Sounds.luau` utilise des sons intégrés au client ; coller des
   `rbxassetid://` de votre pack pour les remplacer. Aucune musique n'est livrée (rien d'inventé :
   des IDs inexistants seraient muets) — ajouter une clé `Music_*` par zone (cf. `Zones.Music`).
3. **Icône, vignettes, description** du jeu sur le Creator Hub.
4. **Test multi-clients** et sur mobile réel (voir `docs/ROADMAP.md`, section vérifications).
