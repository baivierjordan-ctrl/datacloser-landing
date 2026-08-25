# =====================================================================
#  ETAPE 1 - Preparer l'outil et reperer les moments interessants
#
#  Ce script :
#    1. installe ffmpeg si besoin (via winget)
#    2. extrait une image toutes les 10 secondes, nommee avec son
#       timecode, pour t'aider a choisir les moments a garder
#
#  Utilisation : clic droit sur le fichier > "Executer avec PowerShell"
# =====================================================================

$source = "C:\Users\Baivi\Downloads\Enregistrement 1er partie datacloser .mp4"
$sortie = "$env:USERPROFILE\Downloads\datacloser-clips\reperage"

# Intervalle entre deux vignettes, en secondes
$intervalle = 10

function Pause-Et-Quitter($message, $couleur) {
    Write-Host $message -ForegroundColor $couleur
    Read-Host "Appuie sur Entree pour fermer"
    exit
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

# --- 2. Verifications --------------------------------------------------
if (-not (Test-Path -LiteralPath $source)) {
    Pause-Et-Quitter "Fichier introuvable : $source" "Red"
}

New-Item -ItemType Directory -Force -Path $sortie | Out-Null

# --- 3. Duree de la source --------------------------------------------
$secondes = 0
if (Get-Command ffprobe -ErrorAction SilentlyContinue) {
    $brut = & ffprobe -v error -show_entries format=duration -of csv=p=0 "$source"
    if ($LASTEXITCODE -eq 0 -and $brut) {
        $secondes = [double]($brut -replace ',', '.')
    }
}

if ($secondes -le 0) {
    Pause-Et-Quitter "Impossible de lire la duree de la video. Verifie le fichier source." "Red"
}

$lisible = [TimeSpan]::FromSeconds($secondes).ToString("hh\:mm\:ss")
Write-Host "Duree de l'enregistrement : $lisible" -ForegroundColor Cyan

# --- 4. Une image toutes les N secondes, nommee avec son timecode ------
Write-Host ""
Write-Host "Extraction des vignettes (une toutes les $intervalle s)..." -ForegroundColor Cyan

Get-ChildItem "$sortie\*.jpg" -ErrorAction SilentlyContinue | Remove-Item -Force

$position = 0
$nb       = 0

while ($position -lt $secondes) {
    $span     = [TimeSpan]::FromSeconds($position)
    $timecode = $span.ToString("hh\:mm\:ss")
    # Les deux-points sont interdits dans un nom de fichier Windows
    $fichier  = "$sortie\" + $span.ToString("hh\-mm\-ss") + ".jpg"

    & ffmpeg -hide_banner -loglevel error `
        -ss $timecode -i "$source" `
        -frames:v 1 -vf "scale=640:-2" -q:v 3 -y `
        "$fichier"

    if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $fichier)) {
        $nb++
    }

    $position += $intervalle
}

if ($nb -eq 0) {
    Pause-Et-Quitter "Aucune vignette generee. Verifie que le fichier source est bien une video lisible." "Red"
}

Write-Host ""
Write-Host "$nb vignettes generees." -ForegroundColor Green
Write-Host "Dossier : $sortie"
Write-Host ""
Write-Host "Chaque image porte son timecode : 00-01-30.jpg = 00:01:30."
Write-Host "Repere les moments qui te plaisent, note les timecodes,"
Write-Host "puis reporte-les dans 2-decouper-clips.ps1."
Write-Host ""

Start-Process explorer.exe $sortie
Read-Host "Appuie sur Entree pour fermer"
