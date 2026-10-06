# rbxgrab

Récupère le code (Script, LocalScript, ModuleScript) d'un jeu Roblox à partir de son URL.

```bash
python3 rbxgrab.py https://www.roblox.com/games/<placeId>/<nom>
python3 rbxgrab.py <placeId> --out dossier
python3 rbxgrab.py --file MonJeu.rbxl            # .rbxl exporté depuis Studio
ROBLOSECURITY=<cookie> python3 rbxgrab.py <placeId>   # jeu dont vous êtes propriétaire
```

Sortie : `sorties/<jeu>/<jeu>.rbxl` + `sorties/<jeu>/src/` (arborescence type Rojo :
`.server.luau`, `.client.luau`, `.luau`).

Prérequis : Python 3.9+, [Lune](https://github.com/lune-org/lune) (extraction).

## Ce que ça peut et ne peut pas faire

- Fonctionne pour les jeux **copiables** (uncopylocked), vos propres jeux, ou un `.rbxl` que
  vous possédez.
- Ne fonctionne **pas** sur un jeu verrouillé : Roblox n'envoie jamais le code serveur aux
  clients, et l'outil ne cherche pas à le contourner (ni décompilation ni exploit).
- Respectez la licence/les conditions du créateur avant de réutiliser le code d'un autre.

Tests : `python3 -m unittest discover tests`
