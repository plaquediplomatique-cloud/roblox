# SMASH ASCENSION — conception

Jeu de progression de frappe, style jouet / brique. Boucle : **frapper → XP → niveau → arme
→ frapper plus fort → zone suivante**. Projet Rojo indépendant (`ascension.project.json`),
il réutilise seulement les utilitaires génériques de `src/Shared/Util`.

## 1. Audit du concept et améliorations retenues

| Constat sur le concept initial | Risque | Amélioration |
| --- | --- | --- |
| « Taper → attendre → niveau » seul | Lassitude en ~15 min | **Trois boucles imbriquées** : 3 s (coup/combo), 5 min (niveau/arme), session (zone/boss/quête), jour (série, quêtes) |
| Arme débloquée uniquement par le niveau | Pas de choix, pas de rareté « chassée » | **Voie principale** (une arme par palier de niveau, gratuite) + **voie chasse** (boss, coffres, succès, événements) pour Secret/Godly |
| Dégâts exponentiels | Inflation, nombres illisibles | Courbe **pilotée par données**, formatage `1.2K…Qa`, et test de **simulation d'économie** (temps par niveau borné) |
| XP seulement | Pas de choix de build | **Pièces** = monnaie de sink (5 améliorations permanentes) ; **Ascension** (prestige) pour le long terme |
| Combo « qui monte » | Triche d'auto-clic, spam | Combo **côté serveur**, fenêtre de temps, plafond ; cadence **imposée par le serveur** (jeton) |
| Beaucoup de VFX | Mobile, FPS | **Budget VFX par palier de rareté**, émetteurs poolés, aucun émetteur créé à l'exécution en boucle |
| Base « personnalisable » | Coût de contenu énorme | Base = **parcelle modulaire** à emplacements ; catalogue de décor **piloté par données** (recettes de pièces) |
| Assets 3D « énormes » | Pas d'import de meshes possible ici | **Recettes de pièces** (données pures, testées) + un seul builder → centaines d'armes/props sans scripts par objet |

## 2. Les couches de progression

```text
Frappe ──► XP ──► Niveau ──► Arme (palier) ──► Dégâts ──► Zone (niveau + pièces)
   │                              ▲
   └─► Pièces ──► Améliorations (Power, Speed, XP, Crit%, Crit dmg) ──┘
Niveau max (120) ──► ASCENSION : reset niveau/armes, +étoiles = multiplicateur permanent
Quêtes · Série quotidienne · Succès · Collection d'armes · Boss · Classements
```

- **Armes** : 60 au lancement (10 zones × 6), l'ajout d'une arme = une ligne dans
  `Config/Weapons.luau` ; dégâts/niveau requis dérivés de l'index (voir `Rules/Curves`).
- **Zones** (10) : Village d'entraînement, Forêt, Désert, Royaume de glace, Volcan, Royaume
  céleste, Cyber-cité, Néant, Royaume divin, Royaume secret. Chacune : palette, éclairage,
  musique, mannequins, boss, récompenses.
- **Rétention** : récompense quotidienne (série 7 jours), 3 quêtes quotidiennes + 1 hebdo,
  succès, collection d'armes, boss de zone, classements (Power, Niveau, Dégâts, Temps de jeu,
  Meilleur combo, hebdo).
- **Monétisation** (non pay-to-win) : Game Passes (x2 XP *limité* à 2x total, auto-frappe
  désactivée en classement, skins/auras, parcelle étendue), produits développeur (boost XP
  15 min, pack de pièces). Aucun pass ne vend de dégâts bruts.

## 3. Architecture

```text
ascension/src
├─ Shared/            (répliqué)
│  ├─ Config/         données : Rarities, Weapons, Zones, Upgrades, Quests, Achievements,
│  │                  Daily, Products, Decor, Theme, Sounds
│  ├─ Rules/          logique PURE testée avec Lune : Curves, Combat, Upgrades, Ascension,
│  │                  Quests, Daily, Profile (schéma + migrations), NumberFormat, Leaderboards
│  ├─ Assets/         recettes de pièces (pures) + Builder (Instance) : armes, mannequins,
│  │                  architecture, mobilier, décor, nature
│  └─ Net/            registre de remotes + schémas Guard
├─ Server/            services autoritaires
│  ├─ Services/       Data, Player (état), Combat, Dummy, Base, Weapon, Upgrade, Quest,
│  │                  Daily, Achievement, Boss, Leaderboard, Monetization, World
│  └─ GameEvents      bus d'événements entre services (pas d'appels croisés)
└─ Client/            contrôleurs : Input, Combat feel, HUD, Menus, VFX pool, Audio, Camera
```

### Autorité serveur (rien de précieux ne vient du client)

| Action client | Le serveur décide |
| --- | --- |
| `Swing` (aucun chiffre) | cadence (jeton selon la vitesse réelle), portée depuis la position du personnage, cible la plus proche valide, dégâts, critique, combo, XP, pièces |
| `Equip(id)` | possession de l'arme |
| `BuyUpgrade(id)` | coût recalculé, solde, plafond |
| `Ascend`, `ClaimDaily`, `ClaimQuest(id)`, `UnlockZone(id)`, `PlaceDecor` | éligibilité et idempotence |

Chaque remote : limite de débit → schéma `Guard` → exécution protégée (`pcall`).

### Sauvegarde

Profil versionné (`Version`), verrou de session (`UpdateAsync`), réconciliation avec les
valeurs par défaut, assainissement des nombres (NaN/inf/négatifs), autosave 60 s avec
file de nouvelles tentatives, sauvegarde au départ et à `BindToClose`. Repli mémoire en
Studio sans accès API.

### Performance

Mannequins et boss gérés côté serveur sans boucle par mannequin (un seul `Heartbeat`
partagé pour la régénération) ; VFX d'impact via pool d'émetteurs (`Emit(n)` borné par
le palier de rareté) ; nombres de dégâts poolés ; diffusion `HitFx` en `UnreliableRemoteEvent`
limitée aux joueurs proches ; pièces d'asset sans collision, ancrées, ombres coupées pour
les petites pièces.

## 4. Ordre de réalisation (phases)

1. Données et règles pures + tests (progression, armes, combat, économie, quêtes, profil)
2. Recettes d'assets + builder (armes, mannequins, base, zones)
3. Services serveur (données, combat, mannequins, base, quêtes, boss, classements)
4. Client (entrées, feeling de frappe, VFX, HUD, menus, audio)
5. Vérifications : stylua, analyse stricte, tests Lune, build Rojo, revue
