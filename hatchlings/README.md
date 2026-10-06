# Hatchlings — base « Mochi Meadow »

Petit jeu de collection de pets façon *Adopt Me* : on apparaît sur une **île ronde flottante**,
un **œuf** couve dans un nid à côté de nous (minuteur), on le fait éclore et on obtient un pet
de **rareté** variable. Objectif long terme : remplir la collection.

Ce dossier est un projet Rojo **indépendant** de l'FPS « Aether Strike » du dépôt.

## Direction artistique — « Mochi Meadow »

Île pastel à l'heure dorée, formes rondes et douces façon mochi/toy, contours violet profond
(jamais de noir pur), brume rose, petits nuages. Les pets sont des créatures rondes à gros
yeux brillants, construites par code (aucun asset externe) ; les raretés hautes gagnent des
cornes/ailes néon et des étincelles.

| Rareté | Chance | Pets |
|---|---|---|
| Common | 60 % | Pebble Pup, Leaf Bun |
| Uncommon | 25 % | Peach Kit, Cloud Lamb |
| Rare | 10 % | Berry Fox, Moon Owl |
| Epic | 4 % | Sun Dragon |
| Legendary | 1 % | Aurora Unicorn |

## Boucle de jeu

1. Le joueur apparaît sur son plot pastel ; son œuf est posé dans le **nid juste à côté**.
2. Minuteur au-dessus de l'œuf : **8 s** pour le premier (récompense dans la 1re minute),
   **30 s** ensuite. L'œuf tremble quand il est prêt.
3. Maintenir **E** près de l'œuf (propriétaire uniquement) → écran de révélation avec le pet en
   3D, sa rareté, « NEW! » si c'est une découverte.
4. Les 3 pets les plus récents suivent le joueur ; la barre **Pets x / 8** montre la collection.
5. Un pet Epic/Legendary est annoncé aux autres joueurs du serveur. Un nouvel œuf arrive.

## Architecture

```
src/Shared   Config/ (Rarities, Pets, Egg, Theme) · Rules/ (Hatch, Incubation, SlotAllocator,
             IslandLayout : logique PURE testée) · PetFactory (modèle 3D) · Net
src/Server   Main · Environment (lumière) · IslandBuilder (carte) · EggService · PetService
src/Client   Main · EggTimers · Reveal · Collection · PetPreview · UIKit
```

* **Serveur autoritaire** : le tirage et les validations (propriétaire, œuf prêt, une seule
  éclosion) sont côté serveur ; le client n'envoie aucun remote (ProximityPrompt).
* Le minuteur est fait d'**attributs** (`StartedAt`/`ReadyAt` en temps serveur) lus par le client :
  pas de tick réseau.
* Les nombres de design vivent dans `Config/` ; ajouter un pet = une entrée dans `Pets.luau`.

## Lancer

```bash
rokit install                 # rojo, stylua, lune, luau-lsp (rokit.toml à la racine du dépôt)
cd hatchlings
./scripts/test.sh             # tests Lune
./scripts/analyze.sh          # luau-lsp strict
./scripts/build.sh            # build/Hatchlings.rbxl, ou : rojo serve
```

Studio : ouvrir `build/Hatchlings.rbxl` (ou `rojo serve` + plugin Rojo). *Test → Clients and
Servers* pour plusieurs joueurs (6 emplacements max ; au-delà, kick « île pleine » — régler
*Max Players = 6* dans les paramètres du jeu).

## Pas encore fait (volontairement)

Sauvegarde des pets (DataStore), monnaie / boutique, plusieurs types d'œufs, sons, fusion/
échange de pets, mobile (UI testée seulement en logique). Prochain pas conseillé : sauvegarde
puis 2ᵉ type d'œuf.
