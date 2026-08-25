# Outils video DataCloser

Scripts PowerShell (Windows) qui transforment l'enregistrement d'ecran
de la demo en clips verticaux **1080x1350 (4:5)**, le format natif de
LinkedIn, prets a etre montes dans Remotion.

La source de reference : 3 h 21 (12 050 s), 8,7 Go, **1894x990**, 30 fps,
**sans piste audio**. Les trois scripts sont regles pour ce format.

## Les trois etapes

| Script | Ce qu'il fait |
|---|---|
| `1-preparer-et-reperer.ps1` | installe ffmpeg si besoin, extrait des vignettes toutes les 5 s et ouvre une planche de contact pour trouver les timecodes |
| `2-decouper-clips.ps1` | decoupe les moments choisis en clips verticaux 1080x1350 |
| `3-monter-video.ps1` | enchaine les clips en une seule video, avec fondus |

Chacun se lance par clic droit > **Executer avec PowerShell**.

## Etape 1 - reperer

Regle par defaut sur une **passe fine** : une vignette toutes les 5 s
entre `$debutZone` et `$finZone`, pre-remplis sur `00:00:00` ->
`00:04:00`, soit 48 vignettes.

Si tu dois explorer toute la video, mets `$intervalle = 120` et vide
`$finZone` : ~101 vignettes sur les 3 h 21 (a 5 s ce serait 2 410, et
1 206 a 10 s). Tu reperes les zones interessantes, puis tu reviens au
reglage fin sur la zone retenue. Chaque zone ecrit dans son propre
sous-dossier, les passes ne s'ecrasent pas. Le script demande
confirmation au-dela de 300 vignettes.

Chaque passe genere une `planche.html` : toutes les vignettes cote a
cote avec leur timecode, lisible dans le navigateur.

Le timecode est porte par le **nom du fichier** (`00-02-35.jpg` =
00:02:35) et non incruste dans l'image : le filtre `drawtext` de ffmpeg
a besoin de fontconfig et echoue sur la plupart des builds Windows.

## Etape 2 - decouper, et surtout cadrer

C'est le point qui compte. L'enregistrement fait 1894x990, presque du
2:1. Colle tel quel dans un cadre vertical, il ne remplit qu'une bande
fine entre deux aplats de fond : illisible sur un telephone. Il faut
recadrer *dans* la source.

Chaque moment a donc un champ `cadre`, et la sortie fait 1080x1350 :

| `cadre` | recadrage source | image obtenue | occupation du cadre |
|---|---|---|---|
| `"portrait"` | 4:5 (792x990) | 1080x1350 | **100 %**, plein cadre |
| `"carre"` | 1:1 (990x990) | 1080x1080 | 80 % |
| `"large"` | pleine largeur | 1080x564 | 42 % |

`"portrait"` est le defaut : c'est le seul qui remplit le cadre sans
aucune bande, puisque le recadrage 4:5 et la sortie 4:5 coincident.
`"carre"` donne un peu plus de largeur au prix de deux bandes,
`"large"` montre tout l'ecran mais reduit fortement l'image.

`focusX` dit ou recadrer horizontalement : `0` = bord gauche, `0.5` =
centre, `1` = bord droit. C'est le reglage a ajuster si l'element
interessant est sur un cote.

```powershell
$moments = @(
    @{ debut = "00:00:35"; duree = 8; nom = "01-lancement-scan"; cadre = "portrait"; focusX = 0.5 },
    @{ debut = "00:01:50"; duree = 8; nom = "02-liste-leads";    cadre = "portrait"; focusX = 0.6 },
    @{ debut = "00:03:20"; duree = 8; nom = "03-email-genere";   cadre = "portrait"; focusX = 0.4 }
)
```

Le format de sortie se change en haut du script via `$largeurSortie` /
`$hauteurSortie` : `1080x1920` donne du 9:16 pour des stories, avec les
memes cadrages (le `"portrait"` y occupe alors 70 % du cadre). Les
dimensions de recadrage sont calculees a partir des dimensions reelles
lues par `ffprobe` : si tu changes de source, les cadres suivent.

La version horizontale 1280 reste disponible via
`$genererHorizontal = $true`.

## Etape 3 - monter

Assemble les clips dans l'ordre de `ordre.txt` (ecrit par l'etape 2),
avec un fondu enchaine de 0,5 s entre chacun, un fondu d'ouverture et
un fondu de fermeture sur le fond de la charte.

Sortie : `datacloser-demo-vertical.mp4`, 1080x1350, 30 fps, muet. C'est
la base a passer dans Remotion pour le titre et l'ecran de fin.

**Arithmetique de la duree.** Chaque fondu enchaine fait perdre 0,5 s,
donc n clips de d secondes donnent `n*d - (n-1)*0,5`, pas `n*d` :

- 3 clips de 8 s -> **23 s**, ce qui laisse 7 s de cartons Remotion
  pour tomber sur 30 s.
- pour 30 s avec les seuls clips il faut **31 s** de clips au total,
  soit 10 + 10 + 11 s (3 x 11 s donnerait 32 s, pas 30).

Le script affiche les deux chiffres a la fin.

## Ce qui sort

`%USERPROFILE%\Downloads\datacloser-clips\`

- `reperage\pas-5s_00-00-00\` : vignettes + `planche.html` (une par zone)
- `vertical\` : les clips 1080x1350 + `ordre.txt`
- `horizontal\` : seulement si `$genererHorizontal = $true`
- `datacloser-demo-vertical.mp4` : les clips assembles, base du montage Remotion

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
