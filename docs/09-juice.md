# 9. Effets, Juice, Caméra, Son

> Règle d'or : **le juice ne ment jamais.** Tout effet cosmétique (punch, secousse, FOV,
> hit-stop, flashs) est séparé de la visée réelle et de l'état de jeu ; tout retour de
> *résultat* (hitmarker, dégâts, kill) attend la confirmation serveur.

## 9.1 Écrans de chargement

- **Démarrage** (`ReplicatedFirst/Boot.client.luau`) : l'écran du jeu remplace celui de
  Roblox **dès la première frame** — fond vide stellaire, grille discrète, logo « AETHER
  STRIKE » à dégradé blanc→cyan avec glitchs aléatoires, barre de progression par étapes
  (monde → synchronisation → prêt), **astuces de jeu** tournantes (counter-strafe,
  couvertures de 4 studs, marche silencieuse, +1 chambrée, wallbangs, désamorçage à 50 %…).
- **Téléportations** : la même interface est donnée à `TeleportService:SetTeleportGui`
  avant de partir (« CONNEXION AU SERVEUR DE MATCH · KESTREL YARD », « RETOUR AU QG ») et
  reprise à l'arrivée par `GetArrivingTeleportGui` → **aucune coupure visuelle** entre deux
  serveurs.
- Fin du chargement conditionnée au client **réellement prêt** (contrôleurs démarrés +
  profil reçu), délai de sécurité 45 s.

## 9.2 Cinématique d'intro de match

1. Phase `Intro` (7–8 s selon le mode) : caméra **Cinematic** sur le chemin de keyframes
   de la carte (exposé en attributs `Intro1..n` du modèle), interpolation smoothstep.
2. Carte de présentation : nom de la carte (64 px, dégradé, glitch), accroche (« Dépôt de
   fret sur toit — Secteur 7 »), mode + classé/non classé, **deux équipes face à face**
   (glyphe de rang, nom, niveau) séparées d'un « VS ».
3. Mouvements gelés, HUD masqué, son « whoosh ».
4. Phase `Prep` : flash noir 0.35 s, caméra 1re personne, bannière « MANCHE 1 ·
   ATTAQUE · ONYX · MANCHE PISTOLET ».

## 9.3 Caméra : punch, secousse, FOV

| Effet | Modèle | Sources |
|---|---|---|
| **Punch** | ressort vectoriel (24, 0.5) en degrés tangage/lacet/roulis | recul (punch + roulis par arme), atterrissage, dégâts reçus, mêlée |
| **Secousse** | « trauma » 0–1 qui décroît (1.8/s) ; intensité = trauma² × réglage ; bruit de Perlin 22 Hz ; max 3.2° (roulis ×0.6) | tirs (`recoil.shake`), dégâts, atterrissages durs, **détonation** (selon la distance) |
| **FOV** | ressort (16, 0.9) vers `Fov / zoom + kick` + ressort « pop » (14, 0.45) | visée, glissade (+6°), élimination (−1.4°), tir sniper/pompe (−1.2°) |
| **Roulis** | lean (= hitbox), glissade (5°), bob (0.35°) | déplacement |
| **Lissage vertical** | amortissement 22/s de la hauteur d'oeil au sol | marches, postures |

Toutes ces couches s'appliquent au **rendu** : `CameraController.getAim()` (origine et
direction des balles) ne les voit pas. La sensibilité tient compte du zoom.

## 9.4 Hit-stop (léger)

Le multijoueur interdit de ralentir le temps de jeu. Le hit-stop est donc **visuel** :
sur élimination confirmée, le viewmodel (ressorts + clip) avance à 5 % de sa vitesse
pendant **45 ms**, combiné à un FOV pop, un « pop » d'étalonnage (saturation +0.35,
luminosité +0.06), une aberration chromatique et un ducking audio. L'impact se *ressent*
sans jamais retarder l'input.

## 9.5 Killcam

- Pistes serveur (`KillcamPacket`) : poses et visées du **tueur** et de la **victime** sur
  ~3.2 s, échantillonnées depuis l'historique de compensation de latence.
- Lecture : caméra à l'oeil du tueur (`Stances.eyePosition` + yaw/pitch interpolés), temps
  réel puis **ralenti ×0.35 sur la dernière demi-seconde**, marqueur « ◆ VOUS » sur votre
  position, modèle du tueur masqué (pas d'obstruction), bandeau d'info (arme, tête, PV et
  bouclier restants du tueur).
- Désactivable (réglages). Enchaîne sur le **spectateur**.

## 9.6 Écrans de victoire / défaite

Phase `MatchEnd` : HUD masqué, caméra en **orbite lente** autour de la vue d'ensemble de
l'arène (7 keyframes sur 108°), voile sombre, titre géant **VICTOIRE** (or) / **DÉFAITE**
(rouge) / **ÉGALITÉ** avec glitch, score, carte **MVP** (K/D/A, dégâts), vos statistiques,
stinger musical (`UI.Victory` / `UI.Defeat`) avec ducking ; après 5 s le titre remonte et
le **tableau final** s'affiche. Puis volets « RETOUR AU QG » et, au hub, le résumé de
progression chorégraphié ([04-hub.md §4.7](04-hub.md#47-retour-au-hub-et-écran-de-statistiques)).

## 9.7 Transitions

`TransitionController` :
- **cover** : 7 lamelles (sombre/très sombre, liseré cyan) balaient l'écran en cascade
  (35 ms de décalage), fond noir, logo glitché + statut (+ progression optionnelle) ;
- **reveal** : l'inverse, lamelles qui sortent par la droite ;
- **blink** : flash noir 0.35 s (apparition, début de manche) ;
- **jeton de séquence** : une transition plus récente annule proprement la précédente.

Menus : glissement de caméra vers le cadrage « personnage à gauche », flou d'arrière-plan
(`Blur` 14 + profondeur de champ lointaine), sons « whoosh / back ».

## 9.8 Post-processing

| Couche | Paramètres |
|---|---|
| Profil de carte | `Lighting` (heure, luminosité, ambiances, exposition, shift), `Atmosphere`, `AS_Grade` (contraste, saturation, teinte), `AS_Bloom`, `AS_SunRays` — valeurs en [05-level-design.md](05-level-design.md) |
| Dégâts | teinte rouge transitoire + contraste +0.15 (réduite en mode flashs réduits) |
| Élimination | saturation +0.35, luminosité +0.06, retour amorti |
| Bas PV (< 35 %, seuil commun au HUD et à l'audio) | désaturation jusqu'à −0.55, teinte rouge, assombrissement |
| Menu | flou 14 + profondeur de champ lointaine |
| Lunette | profondeur de champ du premier plan |
| Aberration chromatique | **simulée** (pas d'effet natif Roblox) : franges cyan/rouge en bord d'écran, décalées de 6 px, 0.18 s, sur impact et élimination |
| Réglages | bloom, profondeur de champ, rayons de soleil activables ; flashs réduits |

## 9.9 Catalogue d'effets visuels (`EffectsController`, tout est poolé)

| Effet | Détail |
|---|---|
| Flash de bouche | sphère néon étirée, rotation aléatoire, lumière ponctuelle (portée selon la taille), étincelles, fumée ; 45 ms |
| Traceurs | segment néon parcourant la trajectoire réelle (vitesse/longueur par arme), couleur du skin ; masqués à distance pour l'arme suppressée |
| Impacts | étincelles (métal, verre), poussière (bois, minéral), énergie rouge (chair) / bleue (bouclier), sortie de pénétration |
| Trous de balle | 90 en pool, fondu à 10 s |
| Douilles | simulation manuelle (gravité, un rebond, rotation), 40 actives max |
| Chargeurs | copie physique du chargeur du viewmodel, groupe de collision `Effects` (ne gêne aucun joueur), 4 s |
| Explosion (uplink) | gerbe de 80 particules ambre + sphère de souffle qui s'étend à 56 studs en 0.6 s, secousse caméra selon la distance |
| Éliminations | flash `Highlight` de la cible + Voltage / Désintégration / Shatter / Rift |
| Skins | néons pulsants, dégradé cyan↔magenta animé, aura de particules |
| Objectif | lumière pulsante rouge sur l'uplink armé, étiquettes « SITE A/B » |

## 9.10 Son : architecture et sound design

**Mixage** : `Master ─┬─ Music ├─ SFX ─┬─ Weapons ├─ Footsteps ├─ Impacts ├─ Feedback
├─ Ambient └─ UI` ; volumes des réglages ; **ducking** (musique + ambiance) sur kill,
détonation, annonces, écran de fin.

**Spatialisation** : sons 3D portés par des Attachments placés dans le monde, rolloff
`InverseTapered` par famille : tirs proches 8–260 studs, armes légères 6–120, mécanique et
rechargements 4–60, pas 4–70, tirs lointains 30–900 studs (sniper).

**Couches d'un tir** : corps + mécanique (2D tireur) + tail 3D réverbérée en intérieur ;
**variante lointaine** au-delà de 120 studs (on entend *où* et *à quelle distance* on se
bat) ; occlusion (passe-bas + atténuation) si la ligne de vue est coupée.

**Lecture tactique** : pas par matériau et par allure (marche silencieuse, accroupi feutré),
**pas et atterrissages des autres joueurs** synthétisés et occlus, rampes métalliques
bruyantes, pose/désamorçage audibles en 3D, **bips de l'uplink qui s'accélèrent** (de 1 s
à 0.12 s d'intervalle selon la mèche restante).

**Feedback** : sons distincts touche corps / tête / bouclier / bouclier brisé / kill /
kill tête + basse ; alerte de fin de chargeur ; clic à vide ; battement de cœur et
étouffement à bas PV.

**Interface** : survol, clic, confirmation, retour, erreur, tic de compteur, match trouvé,
début / victoire / défaite de manche, victoire / défaite de match, niveau, rang, récompense,
whoosh, glitch.

> **Note honnête sur les assets.** La bibliothèque `Shared/Config/Sounds.luau` pointe
> aujourd'hui vers des **sons intégrés au client Roblox** (`rbxasset://sounds/…`),
> retravaillés par pitch, volume et couches : le jeu est jouable et lisible tel quel, sans
> upload. Le pack final (enregistrements d'armes, Foley, musique) se branche en
> remplaçant les `ids` de chaque clé — **aucune ligne de code à modifier**. Le groupe
> `Music` est câblé (volume, ducking) mais aucune piste n'est fournie.
