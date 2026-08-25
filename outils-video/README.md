# Outils video DataCloser

Scripts PowerShell (Windows) qui transforment l'enregistrement d'ecran
de la demo en une video verticale courte pour LinkedIn et la landing.

La source de reference : 3 h 21 (12 050 s), 8,7 Go, **1894x990**, 30 fps,
**sans piste audio**. Les trois scripts sont regles pour ce format.

## Les trois etapes

| Script | Ce qu'il fait |
|---|---|
| `1-preparer-et-reperer.ps1` | installe ffmpeg si besoin, extrait des vignettes et ouvre une planche de contact pour trouver les timecodes |
| `2-decouper-clips.ps1` | decoupe les moments choisis en clips verticaux 1080x1920 |
| `3-monter-video.ps1` | enchaine les clips en une seule video, avec fondus |

Chacun se lance par clic droit > **Executer avec PowerShell**.

## Etape 1 - reperer, en deux passes

Sur 3 h 21, une vignette toutes les 10 s ferait 1 206 images a parcourir.
Le reperage se fait donc en deux temps :

- **Passe 1** (reglage par defaut) : `$intervalle = 120` sur toute la
  video, soit ~101 vignettes. Tu identifies les 3 ou 4 zones utiles.
- **Passe 2** : tu renseignes `$debutZone` / `$finZone` avec une de ces
  zones, tu mets `$intervalle = 5`, tu relances. Tu obtiens la seconde
  exacte.

Chaque passe ecrit dans son propre sous-dossier et genere une
`planche.html` : toutes les vignettes cote a cote avec leur timecode,
lisible dans le navigateur. Le script demande confirmation au-dela de
300 vignettes.

Le timecode est porte par le **nom du fichier** (`00-42-10.jpg` =
00:42:10) et non incruste dans l'image : le filtre `drawtext` de ffmpeg
a besoin de fontconfig et echoue sur la plupart des builds Windows.

## Etape 2 - decouper, et surtout cadrer

C'est le point qui compte pour du vertical. L'enregistrement fait
1894x990, presque du 2:1. Colle tel quel dans un cadre 1080x1920, il
n'occupe que **29 % de la hauteur** : une bande fine entre deux gros
aplats, illisible sur un telephone. Il faut recadrer *dans* la source.

Chaque moment a donc un champ `cadre` :

| `cadre` | recadrage source | resultat | occupation du cadre |
|---|---|---|---|
| `"large"` | toute la largeur | 1080x565 | 29 % |
| `"carre"` | 1:1 (990x990) | 1080x1080 | 56 % |
| `"portrait"` | 4:5 (792x990) | 1080x1350 | 70 % |

`"carre"` est le bon defaut. `"portrait"` quand l'action tient dans une
colonne (une liste, un formulaire). `"large"` seulement s'il faut
vraiment montrer toute la largeur de l'ecran.

`focusX` dit ou recadrer horizontalement : `0` = bord gauche, `0.5` =
centre, `1` = bord droit. C'est le reglage a ajuster si l'element
interessant est sur un cote.

```powershell
$moments = @(
    @{ debut = "00:42:10"; duree = 8; nom = "01-lancement-scan"; cadre = "carre";    focusX = 0.5 },
    @{ debut = "01:07:30"; duree = 8; nom = "02-liste-leads";    cadre = "portrait"; focusX = 0.6 },
    @{ debut = "02:14:05"; duree = 8; nom = "03-email-genere";   cadre = "carre";    focusX = 0.4 }
)
```

Les dimensions de recadrage sont calculees a partir des dimensions
reelles lues par `ffprobe` : si tu changes de source, les cadres
suivent. La version horizontale 1280 reste disponible via
`$genererHorizontal = $true` (inutile pour la video verticale).

## Etape 3 - monter

Assemble les clips dans l'ordre de `ordre.txt` (ecrit par l'etape 2),
avec un fondu enchaine de 0,5 s entre chacun, un fondu d'ouverture et
un fondu de fermeture sur le fond de la charte.

Sortie : `datacloser-demo-vertical.mp4`, 1080x1920, 30 fps, muet.

**Arithmetique de la duree** : 3 clips de 8 s avec deux fondus de 0,5 s
donnent **23 s**, pas 30. Pour 30 s pile il faut soit des clips de 11 s,
soit un titre d'ouverture et un ecran de fin — qui relevent du montage
Remotion, pas de ffmpeg (du texte incruste ramenerait le probleme de
police de l'etape 1). Le script affiche le calcul a la fin.

## Ce qui sort

`%USERPROFILE%\Downloads\datacloser-clips\`

- `reperage\pas-120s_00-00-00\` : vignettes + `planche.html` (une par passe)
- `vertical\` : les clips 1080x1920 + `ordre.txt`
- `horizontal\` : seulement si `$genererHorizontal = $true`
- `datacloser-demo-vertical.mp4` : la video montee

Encodage H.264 `yuv420p`, `+faststart` (lecture web immediate dans un
`<video>` de la landing), `-an` : la source n'ayant aucune piste audio,
aucun flux audio n'est fabrique.

## Garde-fous

- `-ss` est place **avant** `-i` : ffmpeg saute directement au bon
  endroit du fichier au lieu de decoder 8,7 Go depuis le debut.
- Les timecodes sont valides avant le premier encodage, et un moment qui
  depasserait la fin de la video est refuse en nommant la duree reelle.
- Le code de sortie de ffmpeg est teste a chaque clip ; les echecs sont
  resumes en fin de traitement plutot que signales « OK » en vert.
- La video de la landing actuellement en ligne est
  `media/datacloser-vsl-web.mp4`.
