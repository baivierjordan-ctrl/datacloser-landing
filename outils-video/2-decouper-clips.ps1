# =====================================================================
#  ETAPE 2 - Decouper les moments choisis en clips courts
#
#  MODIFIE LA LISTE CI-DESSOUS avec les moments reperes a l'etape 1,
#  puis : clic droit > "Executer avec PowerShell"
#
#  Chaque clip sort en deux versions :
#    - horizontale (pour la landing / YouTube)
#    - verticale 1080x1920 fond #0a0d12 (pour LinkedIn / mobile)
# =====================================================================

$source = "C:\Users\Baivi\Downloads\Enregistrement 1er partie datacloser .mp4"
$sortie = "$env:USERPROFILE\Downloads\datacloser-clips"

# ---------------------------------------------------------------------
#  A MODIFIER : tes moments
#  debut  = ou commence le clip, format heures:minutes:secondes
#  duree  = combien de secondes garder (vise 6 a 10 secondes)
#  nom    = le nom du fichier de sortie, sans espaces
# ---------------------------------------------------------------------
$moments = @(
    @{ debut = "00:00:20"; duree = 8;  nom = "01-lancement-scan" },
    @{ debut = "00:01:30"; duree = 8;  nom = "02-liste-leads" },
    @{ debut = "00:02:40"; duree = 8;  nom = "03-email-genere" }
)
# ---------------------------------------------------------------------

function Pause-Et-Quitter($message, $couleur) {
    Write-Host $message -ForegroundColor $couleur
    Read-Host "Appuie sur Entree pour fermer"
    exit
}

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    Pause-Et-Quitter "ffmpeg n'est pas installe. Lance d'abord le script 1." "Red"
}

if (-not (Test-Path -LiteralPath $source)) {
    Pause-Et-Quitter "Fichier introuvable : $source" "Red"
}

# --- Verification de la liste avant de lancer quoi que ce soit ---------
foreach ($m in $moments) {
    if ($m.debut -notmatch '^\d{1,2}:\d{2}:\d{2}(\.\d+)?$') {
        Pause-Et-Quitter "Timecode invalide pour '$($m.nom)' : '$($m.debut)'. Format attendu : 00:01:30" "Red"
    }
    if ([double]$m.duree -le 0) {
        Pause-Et-Quitter "Duree invalide pour '$($m.nom)' : $($m.duree)" "Red"
    }
}

New-Item -ItemType Directory -Force -Path "$sortie\horizontal" | Out-Null
New-Item -ItemType Directory -Force -Path "$sortie\vertical"   | Out-Null

# Le fond de la version verticale suit la charte DataCloser (#0a0d12)
$fond = "0x0A0D12"

$compteur = 0
$rates    = @()

foreach ($m in $moments) {
    $compteur++
    Write-Host ""
    Write-Host "[$compteur/$($moments.Count)] $($m.nom) - depuis $($m.debut), $($m.duree)s" -ForegroundColor Cyan

    # --- Version horizontale (1280 de large) ---
    & ffmpeg -hide_banner -loglevel error `
        -ss $m.debut -i "$source" -t $m.duree `
        -vf "scale=1280:-2,setsar=1" `
        -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p -movflags +faststart -an -y `
        "$sortie\horizontal\$($m.nom).mp4"

    $okHorizontal = ($LASTEXITCODE -eq 0)

    # --- Version verticale 1080x1920, fond charte DataCloser ---
    # force_original_aspect_ratio=decrease : l'image entre toujours dans le
    # cadre, quelle que soit la definition de l'enregistrement source.
    & ffmpeg -hide_banner -loglevel error `
        -ss $m.debut -i "$source" -t $m.duree `
        -vf "scale=1080:1920:force_original_aspect_ratio=decrease,pad=1080:1920:(ow-iw)/2:(oh-ih)/2:$fond,setsar=1" `
        -c:v libx264 -preset medium -crf 20 -pix_fmt yuv420p -movflags +faststart -an -y `
        "$sortie\vertical\$($m.nom).mp4"

    $okVertical = ($LASTEXITCODE -eq 0)

    if ($okHorizontal -and $okVertical) {
        Write-Host "   OK" -ForegroundColor Green
    } else {
        Write-Host "   ECHEC (verifie que le timecode tombe bien dans la video)" -ForegroundColor Red
        $rates += $m.nom
    }
}

Write-Host ""
if ($rates.Count -eq 0) {
    Write-Host "Termine. $compteur clips x 2 formats." -ForegroundColor Green
} else {
    Write-Host "Termine avec $($rates.Count) echec(s) : $($rates -join ', ')" -ForegroundColor Yellow
}
Write-Host "Dossier : $sortie"
Write-Host ""
Write-Host "Ces fichiers sont ceux a donner a Claude Code pour la video Remotion."
Write-Host ""

Start-Process explorer.exe $sortie
Read-Host "Appuie sur Entree pour fermer"
