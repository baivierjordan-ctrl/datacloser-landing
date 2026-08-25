# Outils video DataCloser

Scripts PowerShell (Windows) pour transformer un enregistrement d'ecran
en clips courts reutilisables sur la landing, LinkedIn et YouTube.

## Utilisation

1. Ouvre `1-preparer-et-reperer.ps1`, verifie la ligne `$source`
   (le chemin de ton enregistrement), enregistre, puis clic droit >
   **Executer avec PowerShell**.
   Le script installe `ffmpeg` si besoin et extrait une image toutes
   les 10 secondes, nommee avec son timecode (`00-01-30.jpg` = 00:01:30).
   Note les moments qui te plaisent.

2. Ouvre `2-decouper-clips.ps1`, reporte tes timecodes dans le bloc
   `$moments`, puis clic droit > **Executer avec PowerShell**.

```powershell
$moments = @(
    @{ debut = "00:00:20"; duree = 8;  nom = "01-lancement-scan" },
    @{ debut = "00:01:30"; duree = 8;  nom = "02-liste-leads" }
)
```

- `debut` : `hh:mm:ss` (le script refuse un format different)
- `duree` : en secondes, vise 6 a 10
- `nom`   : nom du fichier de sortie, sans espaces ni accents

## Ce qui sort

`%USERPROFILE%\Downloads\datacloser-clips\`

- `reperage\` : les vignettes de l'etape 1
- `horizontal\` : 1280 de large, pour la landing et YouTube
- `vertical\` : 1080x1920, image centree sur fond `#0a0d12` (charte
  DataCloser), pour LinkedIn et mobile

Les clips sont muets (`-an`) et encodes en H.264 `yuv420p` avec
`+faststart`, donc lisibles directement dans un `<video>` de la landing.

## Notes

- Les deux scripts s'arretent avec un message clair si `ffmpeg` manque,
  si le fichier source est introuvable ou si un timecode est mal ecrit.
- Un clip dont le timecode depasse la duree de la video est signale en
  fin de traitement plutot que de passer inapercu.
- La video de la landing actuellement en ligne est
  `media/datacloser-vsl-web.mp4`.
