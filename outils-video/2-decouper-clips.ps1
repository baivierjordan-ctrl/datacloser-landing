# =====================================================================
#  ETAPE 2 - Decouper les moments choisis en clips verticaux
#
#  MODIFIE LA LISTE CI-DESSOUS avec les moments reperes a l'etape 1,
#  puis : clic droit > "Executer avec PowerShell"
#
#  Sortie : 1080x1350, le 4:5 natif de LinkedIn. C'est le format le plus
#  haut que LinkedIn affiche sans recadrer ; du 1080x1920 y serait de
#  toute facon rogne ou reduit.
#
#  LE POINT IMPORTANT : LE CADRAGE
#  L'enregistrement est tres large (1894x990, presque du 2:1). Colle tel
#  quel dans un cadre vertical, il ne remplit qu'une bande fine au
#  milieu de deux aplats de fond. Illisible sur un telephone.
#  La solution est de recadrer dans la source. Chaque moment a donc un
#  champ "cadre" :
#
#    "portrait" recadre en 4:5 (792x990) -> 1080x1350, plein cadre
#    "carre"    recadre en 1:1 (990x990) -> 1080x1080, 80 % du cadre
#    "large"    toute la largeur         -> 1080x564,  42 % du cadre
#
#  "portrait" est le reglage par defaut : c'est le seul qui remplit le
#  cadre sans aucune bande. Prends "carre" s'il faut un peu plus de
#  largeur, "large" seulement s'il faut vraiment montrer tout l'ecran.
#
#  Le champ "focusX" dit OU recadrer horizontalement :
#    0 = bord gauche, 0.5 = centre, 1 = bord droit.
#  C'est le reglage a ajuster si l'element interessant est sur un cote.
# =====================================================================

$source = "C:\Users\Baivi\Downloads\Enregistrement 1er partie datacloser .mp4"
$sortie = "$env:USERPROFILE\Downloads\datacloser-clips"

# Format de sortie. 1080x1350 = 4:5, le format LinkedIn.
# Passe a 1920 si tu veux du 9:16 pour des stories ou du Reels : le
# cadrage suit, les clips seront simplement plus hauts avec du fond.
$largeurSortie = 1080
$hauteurSortie = 1350

# Genere aussi une version horizontale 1280 ? (pas necessaire pour la
# video verticale, utile si tu veux le meme extrait pour YouTube)
$genererHorizontal = $false

# ---------------------------------------------------------------------
#  A MODIFIER : tes moments
#  debut  = ou commence le clip, format hh:mm:ss
#  duree  = combien de secondes garder
#  nom    = nom du fichier de sortie, sans espaces ni accents
#  cadre  = "portrait" | "carre" | "large"
#  focusX = 0 a 1, ou recadrer horizontalement (0.5 = centre)
# ---------------------------------------------------------------------
$moments = @(
    @{ debut = "00:00:20"; duree = 8; nom = "01-lancement-scan"; cadre = "portrait"; focusX = 0.5 },
    @{ debut = "00:01:30"; duree = 8; nom = "02-liste-leads";    cadre = "portrait"; focusX = 0.5 },
    @{ debut = "00:02:40"; duree = 8; nom = "03-email-genere";   cadre = "portrait"; focusX = 0.5 }
)
# ---------------------------------------------------------------------

$fond = "0x0A0D12"   # fond de la charte DataCloser

function Pause-Et-Quitter($message, $couleur) {
    Write-Host $message -ForegroundColor $couleur
    Read-Host "Appuie sur Entree pour fermer"
    exit
}

function Pair($n) {
    # x264 en yuv420p exige des dimensions paires
    $v = [int][Math]::Round($n)
    if ($v % 2 -ne 0) { $v-- }
    return [Math]::Max($v, 2)
}

function PairDecalage($n) {
    # Meme regle pour les decalages de crop, mais 0 est une valeur valide
    # (cadrage colle au bord gauche ou en pleine largeur)
    $v = [int][Math]::Round($n)
    if ($v % 2 -ne 0) { $v-- }
    return [Math]::Max($v, 0)
}

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Pause-Et-Quitter "ffmpeg n'est pas installe. Lance d'abord le script 1." "Red"
}
if (-not (Test-Path -LiteralPath $source)) {
    Pause-Et-Quitter "Fichier introuvable : $source" "Red"
}

# --- Dimensions et duree reelles de la source -------------------------
$largeurSource = 0
$hauteurSource = 0
$dureeSource   = 0

if (Get-Command ffprobe -ErrorAction SilentlyContinue) {
    $dims = & ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$source"
    if ($LASTEXITCODE -eq 0 -and $dims -match '^(\d+),(\d+)') {
        $largeurSource = [int]$Matches[1]
        $hauteurSource = [int]$Matches[2]
    }
    $brut = & ffprobe -v error -show_entries format=duration -of csv=p=0 "$source"
    if ($LASTEXITCODE -eq 0 -and $brut) {
        $dureeSource = [double]($brut -replace ',', '.')
    }
}

if ($largeurSource -le 0 -or $hauteurSource -le 0) {
    Pause-Et-Quitter "Impossible de lire les dimensions de la video source." "Red"
}

Write-Host ("Source : {0}x{1}, duree {2}" -f $largeurSource, $hauteurSource,
            [TimeSpan]::FromSeconds($dureeSource).ToString("hh\:mm\:ss")) -ForegroundColor Cyan

# --- Verification de la liste avant le premier encodage ---------------
foreach ($m in $moments) {
    if ($m.debut -notmatch '^\d{1,3}:\d{2}:\d{2}(\.\d+)?$') {
        Pause-Et-Quitter "Timecode invalide pour '$($m.nom)' : '$($m.debut)'. Format attendu : 00:42:10" "Red"
    }
    if ([double]$m.duree -le 0) {
        Pause-Et-Quitter "Duree invalide pour '$($m.nom)' : $($m.duree)" "Red"
    }
    if ($m.cadre -and $m.cadre -notin @("portrait", "carre", "large")) {
        Pause-Et-Quitter "Cadre inconnu pour '$($m.nom)' : '$($m.cadre)'. Attendu : portrait, carre ou large." "Red"
    }
    $depart = [TimeSpan]::Parse($m.debut).TotalSeconds
    if ($dureeSource -gt 0 -and ($depart + [double]$m.duree) -gt $dureeSource) {
        Pause-Et-Quitter ("'{0}' depasse la fin de la video : {1} + {2}s alors que la video dure {3}." -f `
            $m.nom, $m.debut, $m.duree, [TimeSpan]::FromSeconds($dureeSource).ToString("hh\:mm\:ss")) "Red"
    }
}

New-Item -ItemType Directory -Force -Path "$sortie\vertical" | Out-Null
if ($genererHorizontal) {
    New-Item -ItemType Directory -Force -Path "$sortie\horizontal" | Out-Null
}

$compteur = 0
$rates    = @()
$reussis  = @()

foreach ($m in $moments) {
    $compteur++

    # --- Calcul du recadrage dans la source ---------------------------
    $cadre = if ($m.cadre) { $m.cadre } else { "portrait" }
    $ratio = switch ($cadre) {
        "carre"    { 1.0 }      # 1:1
        "portrait" { 0.8 }      # 4:5
        default    { [double]$largeurSource / $hauteurSource }   # large
    }

    $cropH = Pair $hauteurSource
    $cropW = Pair ([Math]::Min($hauteurSource * $ratio, $largeurSource))

    $focusX = if ($null -ne $m.focusX) { [double]$m.focusX } else { 0.5 }
    $focusX = [Math]::Min([Math]::Max($focusX, 0.0), 1.0)

    # Le crop doit rester dans la source : en cadre "large", cropW vaut
    # deja toute la largeur et le decalage doit donc tomber a 0.
    $cropX = PairDecalage (($largeurSource - $cropW) * $focusX)
    $cropY = PairDecalage (($hauteurSource - $cropH) / 2)
    if ($cropX + $cropW -gt $largeurSource) { $cropX = PairDecalage ($largeurSource - $cropW) }
    if ($cropY + $cropH -gt $hauteurSource) { $cropY = PairDecalage ($hauteurSource - $cropH) }

    # Taille reellement occupee dans le cadre de sortie, une fois l'image
    # mise a l'echelle pour y entrer. Le reste, s'il y en a, est du fond.
    $echelle       = [Math]::Min($largeurSortie / $cropW, $hauteurSortie / $cropH)
    $largeurImage  = Pair ($cropW * $echelle)
    $hauteurImage  = Pair ($cropH * $echelle)
    $occupation    = [Math]::Round(100.0 * $hauteurImage / $hauteurSortie)

    Write-Host ""
    Write-Host ("[{0}/{1}] {2} - depuis {3}, {4}s - cadre {5} -> image {6}x{7} dans {8}x{9} ({10} % du cadre)" -f `
        $compteur, $moments.Count, $m.nom, $m.debut, $m.duree, $cadre,
        $largeurImage, $hauteurImage, $largeurSortie, $hauteurSortie, $occupation) -ForegroundColor Cyan

    # force_original_aspect_ratio=decrease : l'image entre toujours dans le
    # cadre. force_divisible_by=2 : dimensions paires, exigees par yuv420p.
    # En cadre "portrait" la source recadree fait deja du 4:5 : la mise a
    # l'echelle tombe pile sur 1080x1350 et le pad ne fait rien.
    $filtreVertical = "crop=${cropW}:${cropH}:${cropX}:${cropY}," +
                      "scale=${largeurSortie}:${hauteurSortie}:force_original_aspect_ratio=decrease:force_divisible_by=2," +
                      "pad=${largeurSortie}:${hauteurSortie}:(ow-iw)/2:(oh-ih)/2:$fond," +
                      "setsar=1"

    # -ss avant -i : saut direct dans le fichier, sans decoder 3h21.
    # -an : la source n'a aucune piste audio, on n'en fabrique pas.
    & ffmpeg -hide_banner -loglevel error `
        -ss $m.debut -i "$source" -t $m.duree `
        -vf $filtreVertical `
        -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p -movflags +faststart -an -y `
        "$sortie\vertical\$($m.nom).mp4"

    $ok = ($LASTEXITCODE -eq 0)

    if ($genererHorizontal) {
        & ffmpeg -hide_banner -loglevel error `
            -ss $m.debut -i "$source" -t $m.duree `
            -vf "scale=1280:-2,setsar=1" `
            -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p -movflags +faststart -an -y `
            "$sortie\horizontal\$($m.nom).mp4"

        $ok = $ok -and ($LASTEXITCODE -eq 0)
    }

    if ($ok) {
        Write-Host "   OK" -ForegroundColor Green
        $reussis += $m.nom
    } else {
        Write-Host "   ECHEC" -ForegroundColor Red
        $rates += $m.nom
    }
}

# L'ordre des clips pour le montage de l'etape 3
$reussis | ForEach-Object { "$_.mp4" } | Out-File -FilePath "$sortie\vertical\ordre.txt" -Encoding ASCII

Write-Host ""
if ($rates.Count -eq 0) {
    $total = ($moments | ForEach-Object { [double]$_.duree } | Measure-Object -Sum).Sum
    Write-Host "Termine. $compteur clips en ${largeurSortie}x${hauteurSortie}, $total s au total." -ForegroundColor Green
} else {
    Write-Host "Termine avec $($rates.Count) echec(s) : $($rates -join ', ')" -ForegroundColor Yellow
}
Write-Host "Dossier : $sortie\vertical"
Write-Host ""
Write-Host "Regarde les clips avant d'aller plus loin : si l'element interessant"
Write-Host "est coupe, ajuste focusX (0 = gauche, 1 = droite) et relance."
Write-Host "Ensuite : 3-monter-video.ps1 assemble les clips en une seule video."
Write-Host ""

Start-Process explorer.exe "$sortie\vertical"
Read-Host "Appuie sur Entree pour fermer"
