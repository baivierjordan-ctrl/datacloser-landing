# =====================================================================
#  ETAPE 1 - Preparer l'outil et reperer les moments interessants
#
#  L'enregistrement fait plus de 3 heures : on ne parcourt pas ca image
#  par image. Le reperage se fait en deux passes.
#
#    PASSE 1 (reglage par defaut) : une vignette toutes les 2 minutes
#            sur toute la video -> une centaine d'images, tu reperes
#            les 3 ou 4 zones interessantes.
#
#    PASSE 2 : tu remplis $debutZone / $finZone avec une de ces zones,
#            tu mets $intervalle a 5, tu relances -> tu trouves la
#            seconde exacte.
#
#  A la fin, une planche s'ouvre dans le navigateur : toutes les
#  vignettes cote a cote avec leur timecode.
#
#  Utilisation : clic droit sur le fichier > "Executer avec PowerShell"
# =====================================================================

$source = "C:\Users\Baivi\Downloads\Enregistrement 1er partie datacloser .mp4"
$sortie = "$env:USERPROFILE\Downloads\datacloser-clips\reperage"

# ---------------------------------------------------------------------
#  A MODIFIER entre les deux passes
# ---------------------------------------------------------------------
$intervalle = 120          # secondes entre deux vignettes (120 = passe 1, 5 = passe 2)
$debutZone  = "00:00:00"   # debut de la zone a explorer
$finZone    = ""           # fin de la zone ; vide = jusqu'au bout de la video
# ---------------------------------------------------------------------

function Pause-Et-Quitter($message, $couleur) {
    Write-Host $message -ForegroundColor $couleur
    Read-Host "Appuie sur Entree pour fermer"
    exit
}

function En-Secondes($timecode) {
    if ([string]::IsNullOrWhiteSpace($timecode)) { return $null }
    if ($timecode -notmatch '^\d{1,3}:\d{2}:\d{2}(\.\d+)?$') {
        Pause-Et-Quitter "Timecode invalide : '$timecode'. Format attendu : 00:42:10" "Red"
    }
    return [TimeSpan]::Parse($timecode).TotalSeconds
}

# --- 1. ffmpeg ---------------------------------------------------------
if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Write-Host "ffmpeg n'est pas installe. Installation via winget..." -ForegroundColor Yellow

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Pause-Et-Quitter "winget est introuvable. Installe ffmpeg a la main : https://www.gyan.dev/ffmpeg/builds/" "Red"
    }

    winget install --id Gyan.FFmpeg -e --accept-package-agreements --accept-source-agreements

    # Recharge le PATH sans avoir a rouvrir une console
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path", "User")

    if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
        Pause-Et-Quitter "ffmpeg installe mais pas encore visible. Ferme cette fenetre, rouvre-la et relance ce script." "Yellow"
    }
}

Write-Host "ffmpeg est pret." -ForegroundColor Green

if (-not (Test-Path -LiteralPath $source)) {
    Pause-Et-Quitter "Fichier introuvable : $source" "Red"
}

# --- 2. Duree de la source --------------------------------------------
$dureeTotale = 0
if (Get-Command ffprobe -ErrorAction SilentlyContinue) {
    $brut = & ffprobe -v error -show_entries format=duration -of csv=p=0 "$source"
    if ($LASTEXITCODE -eq 0 -and $brut) {
        $dureeTotale = [double]($brut -replace ',', '.')
    }
}
if ($dureeTotale -le 0) {
    Pause-Et-Quitter "Impossible de lire la duree de la video. Verifie le fichier source." "Red"
}

Write-Host ("Duree de l'enregistrement : " + [TimeSpan]::FromSeconds($dureeTotale).ToString("hh\:mm\:ss")) -ForegroundColor Cyan

# --- 3. Zone a explorer ------------------------------------------------
$depart = En-Secondes $debutZone
if ($null -eq $depart) { $depart = 0 }

$fin = En-Secondes $finZone
if ($null -eq $fin -or $fin -gt $dureeTotale) { $fin = $dureeTotale }

if ($depart -ge $fin) {
    Pause-Et-Quitter "La zone est vide : $debutZone vient apres $finZone." "Red"
}
if ($intervalle -le 0) {
    Pause-Et-Quitter "L'intervalle doit etre superieur a 0." "Red"
}

$nbPrevu = [Math]::Ceiling(($fin - $depart) / $intervalle)

Write-Host ("Zone exploree : " + [TimeSpan]::FromSeconds($depart).ToString("hh\:mm\:ss") +
            " -> " + [TimeSpan]::FromSeconds($fin).ToString("hh\:mm\:ss") +
            ", une vignette toutes les $intervalle s") -ForegroundColor Cyan
Write-Host "$nbPrevu vignettes a generer."

if ($nbPrevu -gt 300) {
    Write-Host ""
    Write-Host "C'est beaucoup d'images a parcourir a l'oeil." -ForegroundColor Yellow
    Write-Host "Conseil : garde l'intervalle a 120 pour la premiere passe," -ForegroundColor Yellow
    Write-Host "puis descends a 5 sur une zone de quelques minutes." -ForegroundColor Yellow
    $reponse = Read-Host "Continuer quand meme ? (o/n)"
    if ($reponse -ne "o") { exit }
}

# Un sous-dossier par passe : les deux passes ne se marchent pas dessus
$nomPasse = "pas-{0}s_{1}" -f $intervalle, [TimeSpan]::FromSeconds($depart).ToString("hh\-mm\-ss")
$dossier  = Join-Path $sortie $nomPasse
New-Item -ItemType Directory -Force -Path $dossier | Out-Null
Get-ChildItem "$dossier\*.jpg" -ErrorAction SilentlyContinue | Remove-Item -Force

# --- 4. Extraction -----------------------------------------------------
Write-Host ""

$position  = $depart
$nb        = 0
$timecodes = @()

while ($position -lt $fin) {
    $span     = [TimeSpan]::FromSeconds($position)
    $timecode = $span.ToString("hh\:mm\:ss")
    # Les deux-points sont interdits dans un nom de fichier Windows
    $nomImage = $span.ToString("hh\-mm\-ss") + ".jpg"

    # -ss avant -i : ffmpeg saute directement au bon endroit du fichier
    # au lieu de decoder les 8,7 Go depuis le debut.
    & ffmpeg -hide_banner -loglevel error `
        -ss $timecode -i "$source" `
        -frames:v 1 -vf "scale=640:-2" -q:v 3 -y `
        (Join-Path $dossier $nomImage)

    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath (Join-Path $dossier $nomImage))) {
        $nb++
        $timecodes += [PSCustomObject]@{ Image = $nomImage; Timecode = $timecode }
        Write-Host "`r  $nb / $nbPrevu vignettes..." -NoNewline
    }

    $position += $intervalle
}

Write-Host ""

if ($nb -eq 0) {
    Pause-Et-Quitter "Aucune vignette generee. Verifie que le fichier source est bien une video lisible." "Red"
}

# --- 5. Planche de contact HTML ---------------------------------------
$cellules = ($timecodes | ForEach-Object {
    "<figure><img src=""$($_.Image)"" alt=""$($_.Timecode)"" loading=""lazy""><figcaption>$($_.Timecode)</figcaption></figure>"
}) -join "`n"

$planche = @"
<!doctype html>
<html lang="fr">
<meta charset="utf-8">
<title>Reperage - $nomPasse</title>
<style>
  body { background:#0a0d12; color:#e6edf5; font-family:system-ui,sans-serif; margin:0; padding:24px; }
  h1 { font-size:18px; font-weight:600; margin:0 0 4px; }
  p  { color:#8b98a9; font-size:14px; margin:0 0 24px; }
  .grille { display:grid; grid-template-columns:repeat(auto-fill,minmax(260px,1fr)); gap:16px; }
  figure { margin:0; background:#11161f; border-radius:8px; overflow:hidden; }
  img { width:100%; display:block; }
  figcaption { padding:8px 10px; font-size:13px; font-variant-numeric:tabular-nums; color:#9fb0c4; }
</style>
<h1>Reperage - $nomPasse</h1>
<p>$nb vignettes, une toutes les $intervalle s. Note les timecodes qui t'interessent, puis reporte-les dans 2-decouper-clips.ps1.</p>
<div class="grille">
$cellules
</div>
</html>
"@

$fichierPlanche = Join-Path $dossier "planche.html"
$planche | Out-File -FilePath $fichierPlanche -Encoding UTF8

Write-Host ""
Write-Host "$nb vignettes generees." -ForegroundColor Green
Write-Host "Dossier : $dossier"
Write-Host ""
Write-Host "La planche s'ouvre dans ton navigateur : chaque image porte son timecode."
Write-Host "Passe 1 terminee ? Remets $intervalle a 5, renseigne la zone reperee"
Write-Host "dans `$debutZone / `$finZone, et relance ce script."
Write-Host ""

Start-Process $fichierPlanche
Read-Host "Appuie sur Entree pour fermer"
