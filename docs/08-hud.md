# 8. HUD ultra-premium — description précise et logique

> Code : `Client/Controllers/HUDController.luau` (combat), `MatchController.luau`
> (intro, killcam, spectateur, fin), `Lobby/*` (hub), `UI/UI.luau` (kit), `UI/SettingsPanel.luau`.
> Principe : **lisible en une fraction de seconde**, aucune logique de jeu dans le HUD — il
> ne fait que lire l'état (`WeaponController.hudState()` sans allocation, replicas, attributs)
> et réagir aux événements confirmés par le serveur.

## 8.1 Disposition (référence 1080p)

```
┌──────────────────────────────────────────────────────────────────────────────────────┐
│ 120 FPS · 38 ms        ┌────────┐ ┌──────┐ ┌────────┐                 KILLFEED ▸     │
│                        │ ONYX 5 │ │ 1:24 │ │ 3 HALO │                 Nom [VK-12 ⌖]  │
│                        │ ▮▮▮▯▯  │ │MANCHE│ │ ▮▮▯▯▯  │                 Nom [AR-9 ⟂]   │
│                        └────────┘ └──────┘ └────────┘                                │
│                     O · 300 · 315 · NO · 330 · 345 · N · 15 · ◆ · 30 · 45 · NE      │
│                                                                                       │
│                         ▔▔▔▔▔ MANCHE 7 ▔▔▔▔▔   (bannière)                     TOASTS │
│                          ATTAQUE · ONYX · BALLE DE MATCH                              │
│                                                                                       │
│      ◢ indicateur de dégâts                ┼  réticule dynamique                     │
│                                             ✕  hitmarker                              │
│                             ┌──────────────────────────────┐                          │
│                             │ Maintenir [F] — ARMER L'UPLINK│ (interaction)          │
│                             └──────────────────────────────┘                          │
│                          ◆ ÉLIMINÉ · NOM · TÊTE      ◆ ◆ ◆ (kills de la manche)      │
│ ┌──────────────────────┐                                  ┌──────────────────────┐   │
│ │ 100 PV      50       │                                  │ VK-12 VEKTOR    AUTO │   │
│ │ ███████████ BOUCLIER │                                  │        25  / 75      │   │
│ │ ▬▬▬▬▬▬▬▬▬▬▬          │                                  │ ▬▬▬ VK-12 P-10 LAME  │   │
│ └──────────────────────┘                                  └──────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────────────────┘
```

Deux calques : **Combat** (armé, 1re personne : réticule, vitals, munitions, boussole…) et
**Overlay** (toujours visible pendant un match : bannières, killfeed) — un joueur mort ou
spectateur voit toujours les annonces et le fil des éliminations.

## 8.2 Réticule dynamique et personnalisable

| Réglage | Plage | Défaut |
|---|---|---|
| Style | CLASSIQUE (4 branches), POINT, CERCLE, EN T | Classique |
| Couleur | Cyan, Vert, Blanc, Or, Rouge, Violet, Rose | Cyan `#3DE1FF` |
| Opacité | 10–100 % | 100 % |
| Épaisseur / Longueur / Écart | 1–6 / 0–20 / 0–20 px | 2 / 6 / 4 |
| Contour + épaisseur + opacité | on/off, 0–3 px, 0–100 % | oui, 1, 60 % |
| Point central + taille | on/off, 1–8 px | non, 2 |
| **Dynamique** | on/off | oui |

**Le réticule dynamique représente le VRAI cône** : `écart = Gap + tan(cône) / tan(FOV/2) ×
(hauteur/2) / échelle_UI`. Quand il s'ouvre (mouvement, saut, bloom), les balles s'ouvrent
**exactement** autant. Un ressort ajoute un « kick » visuel à chaque tir. Il **s'efface
pendant la visée** (fondu entre 30 % et 70 % d'ADS — les viseurs prennent le relais),
disparaît en lunette, se réduit à un point avec la lame. Éditeur avec **aperçu en direct**
(×2) dans les réglages.

## 8.3 Munitions et arme (bas-droite)

- Nom de l'arme (glitch bref au changement), **mode de tir** (AUTO / SEMI / RAFALE / VERROU /
  POMPE / LAME).
- **Chargeur** en grand (52 px, chiffres à chasse fixe) : « pop » d'échelle à chaque tir ;
  **ambre** sous 30 %, **rouge** à vide. Réserve « / 75 » (∞ au stand de tir).
- **Barre de rechargement** sous les chiffres (progression réelle du clip).
- **Emplacements** 1 / 2 / 3 avec le nom court de chaque arme ; l'arme active en cyan gras.
- Invite clignotante « RECHARGER [R] » (touche réelle des réglages) quand le chargeur est vide.

## 8.4 Santé et bouclier (bas-gauche)

- PV en grand (44 px) + libellé, bouclier en cyan + libellé.
- **Barres à traînée fantôme** : la partie perdue reste blanche 0.35 s puis se résorbe en
  0.45 s — on lit l'ampleur d'un impact d'un coup d'œil.
- **Bas PV** (< 35 %) : chiffres et barre en rouge, **vignette rouge pulsée** (fréquence
  croissante), battement de cœur, passe-bas sur les SFX, désaturation de l'image.
- Impact reçu : flash de vignette 0.18 s, flash d'éclairage, **aberration chromatique
  simulée** (franges cyan/rouge en bord d'écran), punch et secousse caméra, son « Hurt »,
  son spécifique si tête.

## 8.5 Indicateurs de dégâts directionnels

Arc rouge autour du centre (rayon 150 px) orienté vers **la position du tireur au moment
du tir**, **recalculé chaque frame** selon votre orientation (si vous vous tournez, l'arc
tourne). Intensité selon les dégâts, durée 1.6 s (fondu après 0.6 s), 6 simultanés max.

## 8.6 Hitmarkers, chiffres, confirmation

- Hitmarker en X (4 traits avec contour) : **blanc** corps, **or** tête, **cyan** bouclier
  brisé, **rouge agrandi** élimination ; « pop » d'échelle ; désactivable.
- Chiffres de dégâts **dans le monde** (ScreenGui sans mise à l'échelle → pixels exacts),
  **cumulés par victime** (0.75 s), montent et s'effacent en 1.1 s ; or = tête, ambre =
  à travers un mur ; désactivables.
- Confirmation d'élimination sous le réticule + séries (DOUBLÉ, TRIPLÉ, QUADRUPLÉ, ACE) +
  **pastilles** losanges des kills de la manche (or à 5).

## 8.7 Killfeed (haut-droite)

Jusqu'à 5 lignes (la plus récente en haut), 6 s puis fondu. Format :
`Tueur [ARME ⌖ ⟂ ◎] Victime` — ⌖ tête, ⟂ à travers un mur, ◎ no-scope. Couleurs d'équipe
**relatives** (vos alliés en cyan, ennemis en rouge). Vos lignes sont **encadrées** (cyan si
vous avez tué, rouge si vous êtes mort). Chute hors carte = « CHUTE ».

## 8.8 Boussole

Bande de 420 px montrant 120° (lettres cardinales + graduations tous les 15°), dégradé aux
bords, repère central. **Marqueur d'objectif** : position de l'uplink (ambre ; **rouge** une
fois armé), borné aux bords quand il est hors champ. Désactivable. (Choix de design :
**boussole plutôt que minimap** — une minimap révélerait trop d'information sur les cartes
compactes ; les appels vocaux/callouts restent la source d'info d'équipe.)

## 8.9 Barre de match (haut-centre)

- Votre équipe **toujours à gauche** (cyan), l'adversaire à droite (rouge), noms de camp
  (ONYX = attaque, HALO = défense), scores.
- **Survivants** : une pastille par joueur, pleine si vivant.
- **Timer** : `m:ss` ; **ambre** sous 10 s en phase de combat ; uplink armé → timer de mèche
  en **rouge**, au dixième, pulsant sous 10 s.
- Ligne d'état : « MANCHE 7 · PROLONGATION · PRÉPARATION / FIN DE MANCHE / … ».

## 8.10 Tableau des scores [Tab]

Plein écran translucide : carte · mode · manche ; par équipe (la vôtre d'abord) : nom de
camp + score, colonnes **K, D, A, DÉGÂTS, SCORE**, glyphe et couleur de rang, ★ MVP,
« (déconnecté) », votre ligne surlignée, morts grisés ; tri par score ; rafraîchi 2 fois/s.
Forcé à l'écran en fin de match.

## 8.11 Notifications

- **Bannières** centrales (police display, ligne d'accent qui s'étend, sous-titre, glitch) :
  MANCHE n (+ PISTOLET / PROLONGATION / BALLE DE MATCH), ENGAGEZ, UPLINK ARMÉ (défendez /
  neutralisez + site), UPLINK NEUTRALISÉ, UPLINK LÂCHÉ, MANCHE REMPORTÉE / PERDUE / NULLE +
  raison, CHANGEMENT DE CAMP, CLUTCH, ACE.
- **Toasts** (coin droit, partout y compris au hub) : récompense (couleur de rareté),
  niveau, rang, mission terminée, palier de Pass, achat, erreur, info — avec son.
- **Modales** (hub) : invitation de party, reprise de match.

## 8.12 Interaction et objectif

Panneau contextuel sous le réticule : « Maintenir [F] — ARMER L'UPLINK · SITE A »,
« NEUTRALISER · 50 % CONSERVÉS » ; **la barre de progression suit l'horloge serveur**
(`plantEndsAt` / `defuseEndsAt`) : ce que vous voyez est exactement ce qui compte. Badge
« ◆ UPLINK EN VOTRE POSSESSION » pour le porteur ; étiquettes « SITE A/B » dans le monde.

## 8.13 Lunette

Lentille circulaire calée sur la **hauteur** de l'écran (identique en 16:9, 21:9, 4:3),
masque noir autour, anneau intérieur, réticule fin et point rouge ; le modèle d'arme est
masqué ; profondeur de champ dédiée côté éclairage (premier plan flouté, cible nette).

## 8.14 Spectateur, killcam, fin de match

- **Killcam** : bandeau « KILLCAM · TUEUR · ARME · TÊTE · PV n BOUCLIER n » + marqueur
  « ◆ VOUS » sur votre position dans le replay.
- **Spectateur** : bandeau « SPECTATEUR · NOM · [CLIC G] SUIVANT » ; à défaut de coéquipier
  vivant, vue d'ensemble de l'arène.
- **Fin de match** : VICTOIRE (or) / DÉFAITE (rouge) / ÉGALITÉ, score, carte MVP, vos stats,
  puis tableau final.

## 8.15 Responsive : desktop, tablette, mobile

- Chaque ScreenGui a un `UIScale` = clamp(hauteur / 1080, 0.55, 1.25) (mobile :
  hauteur / 820, 0.5–1.1) × **échelle HUD** des réglages (70–130 %) ; recalculé au
  redimensionnement.
- Ancres aux coins (marges 24–32 px) : rien ne passe sous les encoches ; les éléments
  centrés utilisent des positions relatives.
- **Mobile** : joystick flottant (moitié gauche), visée par glissement (moitié droite),
  boutons TIR (×2, dont un à gauche pour la prise « griffe »), VISER, RECH., ARME, F,
  TAB, SAUT, ACCR., MENU ; le bouton TIR est **aussi une zone de visée** ; friction de visée
  légère sur cible (jamais de verrouillage).
- Manette : gâchettes (tir/visée), A saut, B accroupi, X recharger, Y arme suivante, croix
  (lean, inspecter, interagir), Select (tableau), Start (menu).

## 8.16 Réglages (lobby et menu de match)

6 onglets, application **en direct**, sauvegarde serveur regroupée (1.5 s) et validée :
- **Contrôles** : sensibilité (0.05–5), multiplicateurs visée/lunette, inverser Y, bascules
  (visée, accroupi, marche), lean, rechargement automatique.
- **Réticule** : voir 8.2 (aperçu en direct).
- **Vidéo** : FOV 60–95°, secousses, balancement tête/arme (0–150 %), bloom, profondeur de
  champ, rayons de soleil, **flashs réduits** (photosensibilité), FPS.
- **Audio** : général, musique, effets, interface ; sons de touche / d'élimination.
- **HUD** : échelle, chiffres de dégâts, hitmarkers, boussole, stats réseau, killcam,
  **couleur des ennemis** (rouge / jaune « deutéranopie » / violet « tritanopie »).
- **Touches** : rebinding de 16 actions (clavier + souris), conflits résolus par échange,
  Échap pour annuler, réinitialisation.

## 8.17 Transitions de HUD

HUD masqué pendant l'intro de carte, la killcam et l'écran de fin ; réapparition au
spawn (flash noir 0.35 s) ; bannières et killfeed persistants ; aucun élément ne « saute »
(tweens `Theme.tween.fast/medium/slow/bounce`).
