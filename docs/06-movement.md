# 6. Movement System — sensation et logique

> Code : `Client/Controllers/MovementController.luau` · paramètres :
> `Shared/Config/Movement.luau` · géométrie des postures : `Shared/Combat/Stances.luau` ·
> bornes serveur : `Server/Services/AntiCheatService.luau`.

## 6.1 Intention de feeling

**Nerveux, précis, lisible.** Démarrage franc, arrêt net, aucune glisse « savon ». Le
mouvement est une **compétence** (counter-strafe, peek, glissade, slide-jump) mais jamais
un facteur de chaos : il ne permet pas de « voler » ni de rendre la visée aléatoire. La
précision de tir **dépend** du mouvement (cône de dispersion, `Spread.ACCURATE_SPEED_RATIO
= 0.34`) : on tire juste à l'arrêt ou presque, et le counter-strafe est la porte d'entrée.

## 6.2 Modèle physique « Source-like » piloté sur un Humanoid

Le Humanoid reste le **corps** (collisions, sol, marches, pentes) mais **notre modèle
décide de la vitesse** à chaque frame (`RunService.PreSimulation`) :

```
v  = vitesse RÉELLE du HRP (murs et collisions déjà pris en compte), composante horizontale
si au sol et pas de bhop dans la fenêtre :  v -= v̂ · max(|v|, stopSpeed) · friction · dt
v  = accélérer(v, direction souhaitée, vitesse souhaitée, accel, dt, plafond)
      accélérer : ajout = min(accel · dt · vitesse_souhaitée, vitesse_souhaitée − v·dir)
Humanoid:Move(v̂) ; Humanoid.WalkSpeed = |v|
```

| Paramètre | Valeur | Effet |
|---|---|---|
| `runSpeed` | 17.5 studs/s | allure normale, on peut tirer (× mobilité de l'arme, 84 % → 108 %) |
| `sprintSpeed` | 23.5 | **sprint (Maj)** : vers l'avant, arme baissée, ni tir ni visée, pas plus forts |
| `walkSpeed` | 9.5 | marche (Alt) — **silencieuse** |
| `crouchSpeed` | 7.5 | accroupi — pas feutrés (volume 0.25) |
| `groundAccelerate` | 11 | ≈ 0.2 s pour atteindre la vitesse de course |
| `friction` / `stopSpeed` | 7.5 / 7 | décroissance exponentielle puis arrêt net sous 7 studs/s |
| `airAccelerate` / `airWishCap` | 2.2 / 4.5 | on **courbe** sa trajectoire en l'air, on n'y accélère pas |
| `maxAirSpeedRatio` | 1.12 | vitesse aérienne plafonnée à 112 % de la course |
| `jumpHeight` | 4.4 studs | franchit une couverture de 3.2, pas une caisse de 4 sans élan |
| `jumpBuffer` / `coyoteTime` | 0.12 s / 0.08 s | un saut pressé trop tôt ou juste après le bord **n'est jamais perdu** |
| `bhopWindow` / `bhopDecay` | 0.12 s / 0.94 | bunny-hop léger : l'excédent au-dessus de la course s'érode (× 0.94ⁿ) |

### Counter-strafe (chiffré)

Relâcher les touches : seule la friction agit → de 16.1 studs/s (VK-12) à 34 % de la
vitesse ≈ **140 ms**. Appuyer la direction **opposée** : friction **et** accélération
inverse se cumulent (≈ 230–300 studs/s²) → **≈ 40–50 ms** (≈ 3 frames à 60 FPS). Le joueur
qui maîtrise le geste tire précis 3 fois plus vite : c'est la compétence de base, comme dans
les références du genre.

## 6.3 Postures

| Posture | HipHeight | Oeil (au-dessus du sol) | Hitbox | Vitesse |
|---|---|---|---|---|
| Debout | référence (2) | 4.7 | tête 4.07–5.17, torse 2.5–4.08, jambes 0–2.5 | course / marche |
| Accroupi | −1.4 | 3.3 (crâne 3.77) | compacte, jambes repliées | 7.5 |
| Glissade | −1.7 | ≈ 2.6 | torse incliné 30°, jambes en avant | élan de glissade |

- Le changement de posture modifie **physiquement** `Humanoid.HipHeight` (collision réelle)
  et est répliqué au serveur (`Stance` : posture, lean, ADS, marche, sprint — throttle 80 ms) qui
  en déduit les hitboxes (`Hitbox.compose`) et le cône minimal plausible.
- Se relever exige de la **place** (`Spherecast` au-dessus de la tête) : impossible de
  « clipper » sous un plafond bas.
- `ToggleCrouch` / `ToggleWalk` disponibles (réglages).

## 6.4 Glissade

| Paramètre | Valeur |
|---|---|
| Condition d'entrée | au sol, vitesse ≥ 82 % de la course, hors marche, hors recharge (0.75 s) |
| Élan initial | max(vitesse actuelle, 27) plafonné à 30 studs/s |
| Décélération | 14 + 30 × t (la glissade « meurt » de plus en plus vite) |
| Pente | + gravité × pente × 0.55 (on accélère en descente) |
| Steering | 0.35 (légère correction de trajectoire) |
| Durée max | 1.0 s ; fin si vitesse < 8 studs/s ou en l'air > 0.15 s |
| Slide-jump | conserve **85 %** de l'élan, plafonné à la vitesse de glissade |
| Caméra | roulis 5°, FOV +6°, glissade du viewmodel (arme inclinée) |
| Sortie | debout si la place le permet, sinon accroupi |

Usage tactique : traverser une ligne de tir (la hitbox est basse et inclinée), surprendre
un angle, enchaîner sur un slide-jump pour franchir une ouverture. Le **tir en glissade**
reste possible mais le cône augmente avec la vitesse : c'est un outil de déplacement, pas
de duel.

## 6.5 Lean (Q / E)

- Ressort de vitesse 14 vers −1 / 0 / +1 ; translation latérale 0.55 stud, roulis 12°.
- **Bloqué par les murs** : si une sphère de 0.45 stud à hauteur d'oeil touche un obstacle
  à moins de 1.2 stud sur le côté, le lean est réduit à 25 % (pas de tête à travers un mur).
- La transformation est **identique** pour la caméra et pour la hitbox serveur
  (`Stances.leanTransform`) : on ne peut pas voir sans être visible.
- Désactivable (réglages), interdit en glissade.

## 6.6 Atterrissages, impacts, ralentissements

- **Atterrissage dur** (chute > 45 studs/s) : vitesse × 0.6 pendant 0.25 s, punch caméra
  (0.035 °/stud/s, max 0.9°), dip du viewmodel, son d'impact, légère secousse.
- **Tagging** : être touché ralentit à 72 % pendant 0.22 s (attribut `TaggedUntil` posé par
  le serveur) — les duels restent lisibles, on ne fuit pas en sprintant sous le feu.
- **Mobilité par arme** : `handling.moveMultiplier` (HMG-40 84 %, P-10/MP-6 100 %, lame
  108 %) et `adsMoveMultiplier` en visée (sniper 34 % de la course).

### Sprint (Maj)

- Conditions : debout, déplacement **vers l'avant** (au moins 45 % de la direction), ni
  marche ni visée ; maintien ou bascule (réglage « Sprint en bascule ») ; manette : L3 ;
  mobile : stick poussé à fond vers l'avant.
- **Arme baissée** pendant le sprint (même pose que l'abaissement contre un mur) et champ
  de vision élargi de 4°. Tirer ou viser **interrompt** le sprint ; l'arme met
  `sprint.fireDelay` = 0,12 s à se relever et le clic est mémorisé jusque-là (jamais perdu).
  Le sprint reprend 0,25 s après avoir lâché la gâchette ou la visée.
- Coût tactique : pas plus forts (`Rules/Footsteps` : course 0,81, sprint 1,0) et foulée
  plus longue ; les autres voient l'arme portée en travers (attribut `Sprinting`).
- Glisser depuis un sprint fonctionne naturellement (vitesse d'entrée atteinte).
- Anti-triche : la vitesse soutenue maximale suit `max(sprint, course × 1.12)` × marges.

## 6.7 Couplage caméra et sensations

- **Oeil = géométrie de posture** lissée verticalement (marches, changements de posture
  sans saut d'image).
- **Bob de tête** (réglable 0–150 %) : vertical 0.055, roulis 0.35°, phase liée à la
  **distance parcourue** (cadence de pas réelle, pas une sinusoïde au temps).
- **Pas** : un pas tous les 6.2 studs en course (7.6 en sprint, 4.4 accroupi), son par
  matériau, volume selon l'allure (`Shared/Rules/Footsteps`) ; **marche silencieuse**, y
  compris à mi-course du stick.
- Les **autres** joueurs émettent eux aussi des pas 3D occlus (synthétisés côté client
  avec la même règle, à partir de leur vitesse, posture et attribut `Walking`) :
  l'information sonore est symétrique et fiable.

## 6.8 Orientation du corps et réplication

- `AlignOrientation` (une pièce d'attache, réactivité 200) aligne le HRP sur le **yaw de
  visée** en 1re personne ; au hub (3e personne), le corps se tourne vers la direction de
  déplacement (lissage 12/s).
- Visée envoyée en **binaire** à 30 Hz (`LookUpdate`, 4 octets), rediffusée à 20 Hz par
  arène (`LookBatch`) : sert aux poses 3e personne, au spectateur, à la killcam et à
  l'anti-cheat (vitesse angulaire).

## 6.9 Garde-fous serveur

Le mouvement est **client-autoritaire pour la réactivité**, **serveur-surveillé pour
l'intégrité** (`AntiCheatService`, échantillonnage 10 Hz, historique 3 s) :

| Contrôle | Seuil |
|---|---|
| Vitesse en rafale (1 s) | > plafond de glissade × 1.15 = **34.5 studs/s** |
| Vitesse soutenue (3 s) | > max(sprint, course × 1.12) × 1.08 × 1.15 ≈ **29.2 studs/s** |
| Téléportation | déplacement horizontal > 18 studs + vitesse de rafale × dt entre deux échantillons (sauf téléportations serveur autorisées) |
| Noclip | raycast entre deux positions successives traversant la géométrie |
| Vol | montée > 55 studs/s, ou > 3 s en l'air sans retomber (vitesse verticale > −4) |
| Réaction | correction de position (rubber-band) + points de suspicion pondérés, décroissance 1 pt / 15 s, avertissement 25, expulsion 60 |

Toutes les vitesses légitimes (glissade, slide-jump, bhop érodé) restent **sous** les
seuils avec marge : aucun faux positif sur un joueur rapide.
