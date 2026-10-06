# 7. Weapon System & Gunplay — 14 armes et le feeling

> Code : `Shared/Config/Weapons.luau` (données), `Shared/Combat/*` (maths partagées),
> `Client/Controllers/WeaponController.luau` (prédiction), `ViewmodelController.luau`
> (rendu 1re personne), `Weapons/Animator.luau` (animations), `Weapons/WeaponModelBuilder.luau`
> (modèles), `Server/Services/CombatService.luau` (autorité).
> **Les tableaux ci-dessous sont générés depuis la config** (`lune run tools/weapon_table.luau`) :
> ce sont les valeurs réellement jouées.

## 7.1 Philosophie de l'arsenal

1. **Chaque arme a un rôle et une identité**, pas seulement des chiffres : le VK-12 one-tap
   à toute distance mais recule fort ; l'AR-9 est chirurgical et discret ; le BR-3 récompense
   le timing des rafales ; le KR-7 tient la mi-distance ; le HMG-40 tient un angle.
2. **Bandes de TTK lisibles** (bouclier plein, 15 studs) : 0.30 s (VK-12, DM-4) → 0.35–0.50 s
   (fusils, SMG, LMG) → 0.75–1.1 s (pistolets, revolver) ; le sniper et le pompe tuent en
   un temps de *décision*, pas de rafale.
3. **La tête paie toujours** : multiplicateurs ×2 à ×4.5 ; plusieurs armes one-tap selon le
   bouclier et la distance (tableau 1) — la visée prime sur le spray.
4. **Précision gagnée par la discipline** : 1re balle précise (cône ×0.1 à ×0.7 sur les
   armes concernées),
   counter-strafe, accroupi, rafales courtes ; le spray reste maîtrisable grâce à un
   pattern fixe et apprenable.
5. **Le bouclier change les calculs** (50 points, absorbe 66 % de chaque impact) :
   les manches pistolet (sans bouclier) rendent les secondaires létales.

## 7.2 Tableaux de référence

### Tableau 1 — Dégâts, cadence et TTK (bouclier plein, 15 studs)

| Arme | Catégorie | Mode | Cadence | Corps | Tête | Membre | Plombs | Chute de dégâts | Pénétration | Balles corps | TTK corps |
|---|---|---|---|---|---|---|---|---|---|---|---|
| **VK-12** VEKTOR | AssaultRifle | Auto | 600 | 39 | 156 | 29 | 1 | 200→×1.00 | 1.6 | 4 | 0.300 s |
| **AR-9** HALCYON | AssaultRifle | Auto | 690 | 34 | 153 | 26 | 1 | 20→×1.00 60→×0.91 120→×0.82 | 1.4 | 5 | 0.348 s |
| **BR-3** TRIBUNE | BurstRifle | Rafale | 3×1050 (0.28s) | 36 | 151 | 27 | 1 | 80→×1.00 160→×0.88 | 1.4 | 5 | 0.509 s |
| **SX-5** WASP | SMG | Auto | 900 | 24 | 60 | 19 | 1 | 18→×1.00 45→×0.83 90→×0.67 | 0.8 | 7 | 0.400 s |
| **KR-7** KESTREL | SMG | Auto | 750 | 27 | 76 | 22 | 1 | 25→×1.00 55→×0.89 100→×0.74 | 0.9 | 6 | 0.400 s |
| **HMG-40** BASTION | LMG | Auto | 560→800 | 30 | 96 | 24 | 1 | 60→×1.00 140→×0.92 | 2.4 | 5 | 0.406 s |
| **RS-1** LONGBOW | Sniper | Verrou | 40 | 150 | 300 | 128 | 1 | 1000→×1.00 | 3.0 | 1 | 0.000 s |
| **DM-4** MARSHAL | DMR | Semi | 200 | 76 | 175 | 61 | 1 | 500→×1.00 | 2.0 | 2 | 0.300 s |
| **SG-12** BREACHER | Shotgun | Pompe | 68 | 17 | 33 | 13 | 8 | 10→×1.00 20→×0.65 35→×0.35 | 0.4 | 2 | 0.882 s |
| **AS-8** TEMPEST | Shotgun | Auto | 300 | 10 | 19 | 8 | 7 | 8→×1.00 16→×0.70 28→×0.38 | 0.4 | 3 | 0.400 s |
| **P-10** SIDEWINDER | Pistol | Semi | 400 | 26 | 104 | 21 | 1 | 25→×1.00 70→×0.85 | 0.6 | 6 | 0.750 s |
| **R-44** JUDGE | Revolver | Semi | 110 | 55 | 165 | 47 | 1 | 40→×1.00 100→×0.87 | 1.4 | 3 | 1.091 s |
| **MP-6** HORNET | MachinePistol | Auto | 1000 | 17 | 45 | 14 | 1 | 12→×1.00 30→×0.80 60→×0.65 | 0.4 | 9 | 0.480 s |

### Tableau 2 — Maniement, munitions, dispersion et recul

| Arme | Équiper | Visée (ADS) | Zoom | Viseur | Mobilité | Mob. ADS | Chargeur | Réserve | Recharg. | À vide | Disp. hanche | Disp. ADS | 1re balle | Bloom/tir | Recul 10 tirs (°) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **VK-12** | 0.75 s | 0.24 s | ×1.25 | Holo | 92 % | 55 % | 25 | 75 | 2.30 s | 2.70 s | 2.00° | 0.18° | ×0.25 | 0.32° | ↑8.1 ↔0.4 |
| **AR-9** | 0.72 s | 0.22 s | ×1.30 | RedDot | 93 % | 58 % | 30 | 90 | 2.20 s | 2.60 s | 1.80° | 0.15° | ×0.30 | 0.24° | ↑6.3 ↔0.6 |
| **BR-3** | 0.75 s | 0.25 s | ×1.60 | Scope2x | 93 % | 56 % | 24 | 72 | 2.40 s | 2.80 s | 2.20° | 0.10° | ×0.25 | 0.30° | ↑8.8 ↔0.0 |
| **SX-5** | 0.55 s | 0.17 s | ×1.15 | RedDot | 98 % | 71 % | 30 | 120 | 2.00 s | 2.40 s | 1.50° | 0.45° | ×0.60 | 0.20° | ↑3.8 ↔0.3 |
| **KR-7** | 0.58 s | 0.18 s | ×1.15 | Holo | 97 % | 68 % | 40 | 120 | 2.10 s | 2.50 s | 1.60° | 0.35° | ×0.50 | 0.18° | ↑4.3 ↔0.9 |
| **HMG-40** | 1.15 s | 0.36 s | ×1.20 | Holo | 84 % | 42 % | 100 | 200 | 4.80 s | 5.20 s | 2.60° | 0.40° | ×0.60 | 0.12° | ↑6.6 ↔0.2 |
| **RS-1** | 1.00 s | 0.36 s | ×3.50 | Scope4x | 86 % | 34 % | 5 | 20 | 3.00 s | 3.60 s | 7.50° | 0.00° | ×1.00 | 0.00° | ↑3.8 ↔0.0 |
| **DM-4** | 0.85 s | 0.28 s | ×2.00 | Scope2x | 90 % | 50 % | 10 | 40 | 2.60 s | 3.00 s | 4.00° | 0.08° | ×1.00 | 0.55° | ↑8.6 ↔0.3 |
| **SG-12** | 0.80 s | 0.20 s | ×1.10 | Iron | 95 % | 66 % | 6 | 24 | 0.00 s | 0.00 s | 1.00° | 0.50° | ×1.00 | 0.00° | ↑3.2 ↔0.0 |
| **AS-8** | 0.82 s | 0.22 s | ×1.10 | RedDot | 94 % | 64 % | 8 | 32 | 2.40 s | 2.80 s | 1.20° | 0.70° | ×1.00 | 0.40° | ↑18.0 ↔-0.4 |
| **P-10** | 0.40 s | 0.14 s | ×1.10 | Iron | 100 % | 80 % | 12 | 48 | 1.40 s | 1.70 s | 1.10° | 0.40° | ×0.20 | 0.55° | ↑7.3 ↔0.0 |
| **R-44** | 0.55 s | 0.17 s | ×1.15 | Iron | 98 % | 74 % | 6 | 24 | 2.60 s | 2.60 s | 1.60° | 0.20° | ×0.10 | 1.20° | ↑5.0 ↔0.4 |
| **MP-6** | 0.45 s | 0.15 s | ×1.10 | Iron | 100 % | 80 % | 20 | 80 | 1.60 s | 1.90 s | 1.80° | 0.90° | ×0.70 | 0.25° | ↑5.0 ↔-0.4 |

### Tableau 3 — Identité de chaque arme

| Arme | Rôle | Sensation recherchée |
|---|---|---|
| **VK-12 Vektor** (Primary) | Fusil d'assaut 7.2mm. Un tir à la tête suffit, à n'importe quelle distance. | Lourd, punchy, chaque balle 'claque'. Montée verticale franche puis balayage en S. |
| **AR-9 Halcyon** (Primary) | Fusil d'assaut 5.5mm suppressé. One-tap tête à courte portée, recul très maîtrisable. | Feutré et chirurgical : rafales contrôlées, pas de traceur visible pour l'ennemi au-delà de 60 studs. |
| **BR-3 Tribune** (Primary) | Rafales de 3 coups ultra-rapides. Une rafale bien placée = un kill. | Rythmé, 'tac-tac-tac' sec. Récompense le timing et les peeks courts. |
| **SX-5 Wasp** (Primary) | Pistolet-mitrailleur 900 cpm. Le roi du close-range et du run-and-gun. | Bourdonnement nerveux, recul faible mais 'vibrant'. Se manie comme un pistolet. |
| **KR-7 Kestrel** (Primary) | SMG stable à chargeur tambour de 40. Tient la mi-distance mieux que tout autre SMG. | Rond, régulier, recul en dérive douce vers la droite : facile à apprendre, dur à maîtriser. |
| **HMG-40 Bastion** (Primary) | Mitrailleuse 100 coups. La cadence monte de 560 à 800 cpm en 1.2 s de tir continu. | Massif. Démarre lent et lourd, puis devient un mur de plomb. Idéale pour tenir un angle. |
| **RS-1 Longbow** (Primary) | Fusil de précision à verrou. 150 au corps : un tir, un kill (sauf jambes). | Silence, respiration, puis le tonnerre. Le verrou qui claque après chaque tir est une promesse. |
| **DM-4 Marshal** (Primary) | Fusil de tireur d'élite semi-automatique. 2 balles au corps, 1 à la tête. | Chaque pression de détente est une décision. Recul vertical net qui revient presque seul. |
| **SG-12 Breacher** (Primary) | Fusil à pompe 8 plombs. Dévastateur sous 12 studs, rechargement cartouche par cartouche. | BOOM, puis le 'shk-shk' de la pompe. Le motif fixe récompense le placement du réticule. |
| **AS-8 Tempest** (Primary) | Fusil automatique à chargeur. Moins de dégâts par tir, mais 5 coups/s pour nettoyer une salle. | Une tempête de plombs. Recul qui grimpe vite : 3-4 tirs puis on repositionne. |
| **P-10 Sidewinder** (Secondary) | Pistolet semi-auto fiable. Sans bouclier, un tir à la tête suffit à courte portée. | Vif et précis au premier tir ; le spam est puni par le bloom. Rechargement éclair. |
| **R-44 Judge** (Secondary) | Revolver .50 à 6 coups. One-tap tête même contre un bouclier plein. | Lent, théâtral, définitif. Le recul relève l'arme haut : chaque tir doit être le bon. |
| **MP-6 Hornet** (Secondary) | Pistolet automatique 1000 cpm. Le meilleur ami des manches pistolet à courte portée. | Hystérique : une rafale qui arrache tout sous 15 studs, inutile au-delà. |
| **Ion Blade** (Melee) | Lame à fil ionisé. Coup rapide 50, coup lourd 75, coup lourd dans le dos : élimination. | Vitesse de déplacement maximale, frappes nettes avec un sifflement électrique. |

**Lame ION BLADE** (mêlée) : coup rapide 50 (cadence 0.45 s), coup lourd 75 (1.0 s,
armé 0.25 s), **coup lourd dans le dos 150 = élimination** (cône dorsal de 70°), portée
6.5 studs, cône 38°, **mobilité 108 %** (la plus rapide du jeu).

## 7.3 Modèle de tir

| Mode | Armes | Logique client (`WeaponController.step`) |
|---|---|---|
| Auto | VK-12, AR-9, SX-5, KR-7, AS-8, MP-6 | planning exact au RPM (accumulateur, jusqu'à 3 tirs rattrapés par frame avec horodatage du **tir planifié**) |
| Montée en cadence | HMG-40 | 560 → 800 coups/min en 1.2 s de tir continu (`Weapons.currentRpm`), redescend gâchette relâchée |
| Rafale | BR-3 | 3 coups à 1050 coups/min puis 0.28 s de récupération ; tir dès la frame du clic |
| Semi | DM-4, P-10, R-44 | un tir par pression, **clic mémorisé 0.12 s** (jamais de clic perdu) |
| Verrou | RS-1 | un tir, culasse animée, **la lunette retombe** pendant le réarmement puis revient si [Visée] est maintenu |
| Pompe | SG-12 | un tir, pompe animée (la visée reste en place) |
| Mêlée | Ion Blade | [Tir] = rapide, [Visée] = lourd ; la frappe part au moment de l'impact du clip (« Strike ») |

Rechargements :
- **Chargeur** : tactique (chargeur non vide, **+1 cartouche chambrée** pour les armes à
  culasse fermée — règle partagée `Weapons.reloadCapacity`, appliquée par le serveur) ou
  **à vide** (plus long, avec manœuvre de culasse).
- **Cartouche par cartouche** (SG-12) : début / insertion × n / fin ; **un tir interrompt**
  le rechargement en gardant les cartouches insérées (miroir exact du serveur).
- **Bande** (HMG-40) : capot, bande, fermeture, armement.
- **Barillet** (R-44) : ouverture, éjection des 6 étuis, rechargement, fermeture.
- **Auto-reload** (réglage) : déclenché juste après la dernière cartouche, ou au clic à vide.

## 7.4 Modèle de dégâts

```
dégâts = base × multiplicateur de zone × chute(distance) × perte de pénétration   (arrondi)
zones : tête (×headMultiplier) · corps (×1) · membres (×limbMultiplier)
chute : interpolation linéaire entre points (portée → multiplicateur)
bouclier : absorbe 66 % de chaque impact tant qu'il en reste (PV + bouclier = 150 effectifs)
pénétration : coût = épaisseur × résistance du matériau ; dégâts × (1 − 0.6 × coût / budget)
              2 surfaces max ; « Impenetrable » = jamais
```

Résistances : verre 0.15 · tissu 0.3 · aluminium 0.4 · bois 0.6 · planches 0.7 · néon 0.8 ·
plastique 0.9 · brique/pavé 1.5 · béton 1.6 · granit 1.8 · roche 2.0 · métal rouillé 2.2 ·
métal 2.4 · tôle diamant 3.0. Budgets : RS-1 3.0, HMG-40 2.4, DM-4 2.0, VK-12 1.6,
AR-9/BR-3/R-44 1.4 … pompe 0.4. Exemple : le VK-12 traverse 1 stud de bois (×0.775), pas
2 studs de métal.

## 7.5 Dispersion (spread) et bloom

```
cône = lerp(hanche, ADS, alpha_visée)
       × (1re balle ? firstShotMultiplier : 1) × (accroupi ? crouchMultiplier : 1)
       + mouvement × clamp((vitesse/course − 0.34) / 0.66)        ← counter-strafe récompensé
       + air (si en l'air) + bloom (sauf 1re balle)
bloom : + bloomPerShot par tir (≤ bloomMax), décroît de bloomRecovery °/s après bloomRecoveryDelay
1re balle : retrouvée après firstShotReset secondes sans tirer
directions : graine = hash(graine serveur, n° de tir) → décalage dans le cône, densité
             centrale (rayon ∝ u) ; plombs : motif en tournesol (angle d'or) + légère gigue
```

Le serveur recalcule **les mêmes** directions et impose un **cône minimal plausible**
(état observé : vitesse, posture, ADS confirmé, en l'air > 0.25 s, bloom × 0.5, × 0.85 de
tolérance) : un « no-spread » ne gagne rien.

## 7.6 Recul : pattern, aléa, récupération

- **Pattern fixe** construit par segments (`RecoilPatterns.build`). Exemple VK-12 :
  3 tirs verticaux (0.55 → 0.9°), 7 tirs verticaux forts (0.85°), 6 tirs qui partent à
  gauche (−0.55° de lacet), 6 à droite (+0.65°), 3 à gauche ; boucle à partir du 11e tir.
  Le joueur apprend une forme (montée puis « S »), comme dans les références du genre.
- **Aléa** léger par tir (lacet ±0.18°, tangage ±0.1° pour le VK-12) : la forme est stable,
  la mémoire musculaire fonctionne, mais le spray n'est pas un laser.
- **Multiplicateurs** : visée (×0.75 à ×1 selon l'arme), accroupi (×0.7 à ×1).
- **Récupération intelligente** : après `recoveryDelay`, la visée revient à `recoverySpeed`
  °/s vers le point de départ, à hauteur de `recoveryRatio` (75 % pour le VK-12) **moins
  ce que le joueur a déjà compensé** — tirer vers le bas pendant le spray ne fait pas
  plonger la visée ensuite.
- **L'index du pattern redescend** pendant les pauses (×1.6 la cadence) : un tap après une
  courte pause repart plus bas dans le motif.
- **Recul visuel séparé** (n'affecte pas la visée) : punch caméra (tangage, lacet, roulis),
  trauma de secousse, recul du viewmodel (position + rotation à ressorts calibrés),
  FOV « pop » pour le sniper et les pompes.

## 7.7 Visée (ADS)

| Élément | Comportement |
|---|---|
| Transition | durée = `adsTime` (0.14 s P-10 → 0.36 s RS-1/HMG-40), courbe smoothstep, arc vertical et léger roulis pendant la montée |
| Alignement | le **point de visée** du modèle (`AimPoint`) est amené sur l'axe optique à `adsDistance` : le réticule du viseur est exactement au centre de l'écran |
| FOV | `Fov / zoom` à ressort (×1.1 à ×3.5) ; sensibilité multipliée par `1/zoom × AdsMultiplier` (ou `ScopeMultiplier` au-delà de ×2.5) |
| Viseurs | Iron, RedDot, Holo, Scope2x, Scope4x — modélisés (lentille, réticule néon) |
| Lunette plein écran | RS-1 : au-delà de 85 % de visée, le modèle disparaît et l'**overlay** de lunette (cercle, réticule, masque) s'affiche ; profondeur de champ côté éclairage |
| Sway | retard rotationnel sur la vitesse de visée × `swayMultiplier`, réduit de 80 % en visée |
| Respiration | oscillation lente au repos (position + tangage), réduite de 75 % en visée |
| Mouvement | mobilité × `adsMoveMultiplier` (34 % → 80 %) |

## 7.8 Animations (procédurales, aucun asset)

`Weapons/Animator.luau` génère des **clips** (pistes de keyframes normalisées pour l'arme
entière, le chargeur, la culasse et la main gauche, + événements) **calés sur les stats** :
un rechargement de 2.3 s dure 2.3 s, l'animation EST le timing de gameplay.

| Clip | Détails |
|---|---|
| Équipement | sortie de l'arme depuis le bas ; **premier équipement** de la vie = manœuvre de culasse + son |
| Tir | ressorts de recul (position, rotation) + flash + douille + culasse de pistolet bloquée **à vide** |
| Rechargement tactique | inclinaison, chargeur qui sort, **chargeur physique qui tombe** (copie avec collisions), nouveau chargeur, claque |
| Rechargement à vide | idem + manœuvre de culasse (« rack ») |
| Cartouches (SG-12) | début, insertions une par une (main gauche), fin avec pompe |
| Bande (HMG-40) / Barillet (R-44) | séquences dédiées, étuis éjectés vers le sol pour le revolver |
| Culasse / pompe | après chaque tir (RS-1 / SG-12), étui éjecté au bon moment |
| Inspection [Y] | rotation sur deux faces ; **animation exclusive** (tour complet) pour les skins Specter et Aether |
| Mêlée | rapide (0.42 s) et lourde (0.75 s), la frappe réseau part à l'impact du clip |

Les **bras** sont résolus par IK analytique à 2 os (épaules hors champ → mains sur les
attachments `RightHand` / `LeftHand` de l'arme, ou cible de main gauche animée) : toute
nouvelle arme est tenue correctement sans animation dédiée. Un clip interrompu se fond en
0.14 s ; le **hit-stop** (élimination) fige l'arme 45 ms.

## 7.9 Sons (en couches)

| Couche | Exemple VK-12 | Règle |
|---|---|---|
| Corps du tir | `Weapon.Rifle.Fire` | 2D pour le tireur, 3D occlus pour les autres |
| Mécanique | `Weapon.Mech.Rifle` | 2D tireur |
| Queue (tail) | `Weapon.Tail.Rifle` | 3D, **réverbérée en intérieur** (plafond détecté) |
| Lointain | `Weapon.Distant.Rifle` | remplace corps + tail au-delà de 120 studs |
| Rechargement | `Reload.MagOut/MagIn/Rack` | déclenchés par les événements du clip |
| Équipement / à vide | `Equip.Rifle` / `Weapon.Dry` | + **cliquetis d'alerte** sur les 20 % derniers du chargeur |
| Impacts | béton, métal, bois, verre, chair, bouclier | 2 sons max par tir (pompe : pas de mur de son) |

L'AR-9 utilise une signature **suppressée** (`Weapon.Rifle.Suppressed`), et ses traceurs
et flashs sont **invisibles pour les autres joueurs au-delà de 60 studs**
(`tracer.concealRange`).

## 7.10 Effets visuels

- **Flash de bouche** à l'attachment `Muzzle`, taille par catégorie (pistolet 0.3 → sniper
  et pompe 0.6), couleur du skin, fumée (sauf pistolets), lumière ponctuelle, étincelles ;
  mode « flashs réduits » (photosensibilité).
- **Douilles** éjectées à l'attachment `Ejection` (vitesse du joueur héritée), taille par
  calibre, rebond simulé ; **chargeurs** physiques au rechargement.
- **Traceurs** : segment néon qui parcourt la trajectoire (950 studs/s, longueur 9), largeur
  et fréquence par arme (1 sur 2 pour AR-9, SX-5, KR-7…), couleur du skin.
- **Impacts** par matériau : étincelles (métal ×12, verre bleuté), poussière (bois brun,
  minéral gris), **trous de balle** (90 en pool, fondu après 10 s), impacts « chair » rouges
  ou « bouclier » bleus sur les personnages ; impacts de **sortie** après une pénétration.

## 7.11 Retours de touche et d'élimination

| Événement | Retour |
|---|---|
| Touche confirmée (corps / membre) | hitmarker blanc, son `Hit.Body` |
| Tête | hitmarker **or**, son `Hit.Head`, chiffre or |
| Bouclier brisé | hitmarker **cyan**, son `Hit.ArmorBreak` |
| Wallbang | chiffre de dégâts **ambre** |
| Élimination | hitmarker **rouge** agrandi, `Hit.Kill`/`Hit.KillHead` + basse, « pop » d'éclairage, FOV pop, **hit-stop** 45 ms, aberration chromatique, ducking |
| Confirmation | « ◆ ÉLIMINÉ · NOM · TÊTE · À TRAVERS · NO-SCOPE · PREMIER SANG », séries (DOUBLÉ → ACE), pastilles de kills de la manche |
| Killfeed | tueur [arme ⌖ ⟂ ◎] victime, couleurs d'équipe, vos lignes encadrées |
| Effet d'élimination | Voltage (arcs), Désintégration (particules), Shatter (cubes néon), Rift (implosion) — du tueur, ou celui du skin Mythique |
| Killcam | 3 dernières secondes vues par le tueur, ralenti final, position de la victime marquée |

**Chiffres de dégâts** projetés dans le monde, **cumulés par victime** sur 0.75 s (on lit
« 156 » et non « 39 39 39 39 »). Tous ces retours sont **confirmés serveur** : aucun faux
hitmarker.

## 7.12 Hit detection autoritaire (résumé)

Le serveur reçoit `{arme, n° de tir, origine, direction, cône, horodatage, ADS}`, valide
(contexte, séquence, munitions, cadence de la même arme, fenêtre 1 s, origine, cône minimal,
vitesse angulaire, horloge), **recalcule** les directions avec la graine, rembobine les
cibles à l'instant du tir (≤ 0.35 s) et résout monde + hitboxes + pénétration. Détails et
code : [10-code.md](10-code.md).

## 7.13 Skins et rareté

8 lignes × 14 armes (112 skins) + opérateurs, effets d'élimination, emotes, bannières,
titres. Rareté **Commun → Rare → Épique → Légendaire → Mythique** (couleur, prix en Flux
300 / 800 / 1800 / 3600, Mythique non achetable).

| Ligne | Rareté | Effets |
|---|---|---|
| Standard | Commun | finition d'usine (offerte) |
| Obsidian | Commun | noir mat, accents blancs |
| Arctic Circuit | Rare | céramique blanche, pistes cyan |
| Ember Forge | Rare | acier brûlé, braises orange |
| Solar Flare | Épique | **néon pulsant** (1.2 Hz) |
| Crimson Protocol | Épique | pulsation d'alerte (2 Hz), **traceurs rouges** |
| Specter | Légendaire | pulsation lente, **aura de particules**, traceurs violets, **inspection exclusive** |
| Aether Prime | Mythique | **néon vivant cyan↔magenta**, aura, traceurs cyan, **flash violet**, inspection exclusive, **effet d'élimination Rift intégré** |

Les skins sont des **palettes + matériaux + FX** appliqués aux rôles de couleur du modèle
procédural (Base, Secondary, Accent, Neon, Metal, Glass, Grip) : un même modèle porte toutes
les collections, et le skin est visible partout (viewmodel, 3e personne, vitrines, aperçu).
