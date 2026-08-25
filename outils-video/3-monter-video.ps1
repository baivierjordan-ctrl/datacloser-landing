# =====================================================================
#  ETAPE 3 - Assembler les clips en une seule video verticale
#
#  Enchaine les clips de l'etape 2 dans l'ordre, avec un fondu entre
#  chacun, un fondu d'ouverture et un fondu de fermeture sur le fond
#  de la charte.
#
#  Utilisation : clic droit > "Executer avec PowerShell"
# =====================================================================

$sortie     = "$env:USERPROFILE\Downloads\datacloser-clips"
$dossier    = "$sortie\vertical"
$fichierFin = "$sortie\datacloser-demo-vertical.mp4"

$dureeCible = 30     # duree visee pour la video finale, cartons Remotion compris
$transition = 0.5    # duree du fondu entre deux clips, en secondes
$ouverture  = 0.4    # fondu d'ouverture
$fermeture  = 0.8    # fondu de fermeture
$fond       = "0x0A0D12"

function Pause-Et-Quitter($message, $couleur) {
    Write-Host $message -ForegroundColor $couleur
    Read-Host "Appuie sur Entree pour fermer"
    exit
}

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Pause-Et-Quitter "ffmpeg n'est pas installe. Lance d'abord le script 1." "Red"
}

# --- Ordre des clips ---------------------------------------------------
# ordre.txt est ecrit par l'etape 2 ; sinon on prend les mp4 par nom.
$listeOrdre = Join-Path $dossier "ordre.txt"
if (Test-Path -LiteralPath $listeOrdre) {
    $noms = Get-Content $listeOrdre | Where-Object { $_.Trim() -ne "" }
} else {
    $noms = Get-ChildItem "$dossier\*.mp4" -ErrorAction SilentlyContinue |
            Sort-Object Name | ForEach-Object { $_.Name }
}

$clips = @()
foreach ($nom in $noms) {
    $chemin = Join-Path $dossier $nom.Trim()
    if (-not (Test-Path -LiteralPath $chemin)) {
        Pause-Et-Quitter "Clip introuvable : $chemin. Relance l'etape 2." "Red"
    }
    $clips += $chemin
}

if ($clips.Count -lt 1) {
    Pause-Et-Quitter "Aucun clip dans $dossier. Lance d'abord l'etape 2." "Red"
}

Write-Host "$($clips.Count) clips a assembler :" -ForegroundColor Cyan
$clips | ForEach-Object { Write-Host "  - $(Split-Path $_ -Leaf)" }

# --- Duree reelle de chaque clip --------------------------------------
$durees = @()
foreach ($clip in $clips) {
    $brut = & ffprobe -v error -show_entries format=duration -of csv=p=0 "$clip"
    if ($LASTEXITCODE -ne 0 -or -not $brut) {
        Pause-Et-Quitter "Impossible de lire la duree de $clip." "Red"
    }
    $durees += [double]($brut -replace ',', '.')
}

# Chaque fondu enchaine mange $transition secondes au total
$dureeFinale = ($durees | Measure-Object -Sum).Sum - ($clips.Count - 1) * $transition

if ($clips.Count -gt 1 -and ($durees | Measure-Object -Minimum).Minimum -le $transition) {
    Pause-Et-Quitter "Un clip est plus court que la transition ($transition s). Reduis `$transition." "Red"
}

# --- Construction du filtre -------------------------------------------
$entrees = @()
foreach ($clip in $clips) { $entrees += @("-i", $clip) }

$ci      = [System.Globalization.CultureInfo]::InvariantCulture   # decimales avec un point, pas une virgule
$etapes  = @()
$courant = "[0:v]"
$cumul   = $durees[0]

for ($i = 1; $i -lt $clips.Count; $i++) {
    $decalage = [Math]::Round($cumul - $transition, 3)
    $etiquette = "[x$i]"
    # Attention : "$variable:" est la syntaxe de portee PowerShell ($global:x).
    # Dans une chaine, "duration=$transition:offset=..." s'evalue donc en vide.
    # L'operateur -f evite completement le probleme.
    $etapes += ("{0}[{1}:v]xfade=transition=fade:duration={2}:offset={3}{4}" -f `
        $courant, $i,
        $transition.ToString($ci),
        $decalage.ToString($ci),
        $etiquette)
    $courant = $etiquette
    $cumul   = $cumul + $durees[$i] - $transition
}

$debutFermeture = [Math]::Round($dureeFinale - $fermeture, 3)
if ($debutFermeture -lt 0) { $debutFermeture = 0 }

$etapes += ("{0}fade=t=in:st=0:d={1}:color={2},fade=t=out:st={3}:d={4}:color={2},format=yuv420p[final]" -f `
    $courant, $ouverture.ToString($ci), $fond, $debutFermeture.ToString($ci), $fermeture.ToString($ci))

$filtre = $etapes -join ";"

Write-Host ""
Write-Host ("Duree finale : {0:N1} s" -f $dureeFinale) -ForegroundColor Cyan
Write-Host "Encodage..." -ForegroundColor Cyan

& ffmpeg -hide_banner -loglevel error `
    @entrees `
    -filter_complex $filtre -map "[final]" `
    -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p -movflags +faststart -an -y `
    "$fichierFin"

if ($LASTEXITCODE -ne 0) {
    Pause-Et-Quitter "ffmpeg a echoue pendant le montage." "Red"
}

Write-Host ""
Write-Host "Video montee : $fichierFin" -ForegroundColor Green
Write-Host ""

# Rappel de l'arithmetique : chaque fondu enchaine fait perdre
# $transition secondes, donc n clips de d secondes donnent
# n*d - (n-1)*$transition, et pas n*d.
if ($dureeFinale -lt $dureeCible) {
    $reste = [Math]::Round($dureeCible - $dureeFinale, 1)
    Write-Host ("Il reste {0} s a remplir pour atteindre {1} s : c'est la place du titre" -f $reste, $dureeCible) -ForegroundColor Yellow
    Write-Host "d'ouverture et de l'ecran de fin, a faire au montage Remotion." -ForegroundColor Yellow
    Write-Host ""

    # Variante : atteindre la cible avec les seuls clips.
    $totalClips = $dureeCible + ($clips.Count - 1) * $transition
    $base       = [Math]::Floor($totalClips / $clips.Count)
    $repartition = @()
    $restant = $totalClips
    for ($i = 0; $i -lt $clips.Count; $i++) {
        if ($i -eq $clips.Count - 1) { $repartition += [Math]::Round($restant, 1) }
        else { $repartition += $base; $restant -= $base }
    }
    Write-Host ("Sans cartons, il faudrait {0} s de clips au total (les {1} fondus en mangent {2} s)," -f `
        $totalClips, ($clips.Count - 1), (($clips.Count - 1) * $transition)) -ForegroundColor DarkGray
    Write-Host ("soit par exemple {0} s. A regler dans le champ 'duree' de 2-decouper-clips.ps1." -f `
        ($repartition -join " + ")) -ForegroundColor DarkGray
    Write-Host ""
}

Start-Process explorer.exe $sortie
Read-Host "Appuie sur Entree pour fermer"
