#Requires -Version 5.1
<#
===============================================================================
  DIAGNOSTIC PRE-DUAL-BOOT  --  100% LECTURE SEULE
===============================================================================
  Ce script NE MODIFIE RIEN sur la machine.
  Il ne fait que LIRE la configuration et ecrire un rapport texte sur le Bureau.

  Aucune commande de ce script n'ecrit sur un disque, ne cree/supprime/
  redimensionne une partition, ne touche au BIOS/UEFI ni au bootloader.

  Usage :
    1. Clic droit sur PowerShell  ->  "Executer en tant qu'administrateur"
    2. Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
    3. .\Diagnostic-DualBoot.ps1

  Resultat : Rapport-DualBoot.txt sur le Bureau. A relire puis partager.
===============================================================================
#>

$ErrorActionPreference = 'Continue'
$ProgressPreference    = 'SilentlyContinue'

$Report = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Rapport-DualBoot.txt'
$script:Lines = New-Object System.Collections.Generic.List[string]

function Add-Line  { param([string]$t='') ; $script:Lines.Add($t) ; Write-Host $t }
function Add-Header  { param([string]$t)    ; Add-Line '' ; Add-Line ('=' * 74) ; Add-Line "  $t" ; Add-Line ('=' * 74) }
function Add-KV { param($k,$v)         ; Add-Line ("  {0,-34}: {1}" -f $k, $v) }
function ConvertTo-GB { param($b) ; if ($null -eq $b) { 'n/a' } else { '{0:N1} Go' -f ($b / 1GB) } }

Add-Line "RAPPORT DIAGNOSTIC PRE-DUAL-BOOT"
Add-Line ("Genere le {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
Add-Line "Mode : LECTURE SEULE - aucune modification effectuee"

# --- Droits administrateur --------------------------------------------------
$IsAdmin = $false
try {
    $IsAdmin = ([Security.Principal.WindowsPrincipal] `
                [Security.Principal.WindowsIdentity]::GetCurrent()
               ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
} catch { $IsAdmin = $false }

if (-not $IsAdmin) {
    Add-Line ''
    Add-Line '!!! ATTENTION : script lance SANS droits administrateur.'
    Add-Line '!!! BitLocker, TPM et les entrees de demarrage seront INCOMPLETS.'
    Add-Line '!!! Relance PowerShell en tant qu administrateur pour un rapport complet.'
}
Add-KV 'Droits administrateur' $(if ($IsAdmin) { 'OUI' } else { 'NON - rapport partiel' })

# --- 1. Systeme -------------------------------------------------------------
Add-Header '1. SYSTEME'
try {
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $cp = Get-CimInstance Win32_Processor | Select-Object -First 1
    $rk = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'

    Add-KV 'Windows'          $os.Caption
    Add-KV 'Version'          ((Get-ItemProperty $rk -EA SilentlyContinue).DisplayVersion)
    Add-KV 'Build'            ("{0}.{1}" -f $os.BuildNumber, (Get-ItemProperty $rk -EA SilentlyContinue).UBR)
    Add-KV 'Architecture'     $os.OSArchitecture
    Add-KV 'Fabricant'        $cs.Manufacturer
    Add-KV 'Modele'           $cs.Model
    Add-KV 'Type de chassis'  $(if ($cs.PCSystemType -eq 2) { 'Portable' } else { 'Fixe / autre' })
    Add-KV 'Processeur'       $cp.Name
    Add-KV 'Coeurs / threads' ("{0} / {1}" -f $cp.NumberOfCores, $cp.NumberOfLogicalProcessors)
    Add-KV 'RAM totale'       (ConvertTo-GB $cs.TotalPhysicalMemory)
} catch { Add-Line "  [erreur] $_" }

# --- 2. Firmware / Secure Boot / TPM ----------------------------------------
Add-Header '2. FIRMWARE  (le point le plus important)'
$FirmwareMode = 'INCONNU'
try {
    $bcd = & bcdedit /enum '{current}' 2>&1 | Out-String
    if     ($bcd -match 'winload\.efi') { $FirmwareMode = 'UEFI' }
    elseif ($bcd -match 'winload\.exe') { $FirmwareMode = 'LEGACY / BIOS (CSM)' }
} catch { }
if ($FirmwareMode -eq 'INCONNU' -and $env:firmware_type) { $FirmwareMode = $env:firmware_type }
Add-KV 'Mode de demarrage Windows' $FirmwareMode

try {
    $sb = Confirm-SecureBootUEFI -ErrorAction Stop
    Add-KV 'Secure Boot' $(if ($sb) { 'ACTIVE' } else { 'Desactive' })
} catch {
    Add-KV 'Secure Boot' 'Non disponible (machine en Legacy/BIOS, ou droits insuffisants)'
}

try {
    $bios = Get-CimInstance Win32_BIOS
    Add-KV 'BIOS / UEFI version' ("{0} {1}" -f $bios.SMBIOSBIOSVersion, $bios.ReleaseDate.ToString('yyyy-MM-dd'))
} catch { }

try {
    $tpm = Get-Tpm -ErrorAction Stop
    Add-KV 'TPM present / actif' ("{0} / {1}" -f $tpm.TpmPresent, $tpm.TpmReady)
} catch { Add-KV 'TPM' 'non lisible (droits admin requis)' }

# --- 3. BITLOCKER  (risque n°1) ---------------------------------------------
Add-Header '3. BITLOCKER  (cause n1 de Windows inaccessible)'
$BitLockerOn = $false
try {
    $bv = Get-BitLockerVolume -ErrorAction Stop
    foreach ($v in $bv) {
        $st = $v.ProtectionStatus
        if ($st -eq 'On') { $BitLockerOn = $true }
        Add-Line ("  Volume {0,-4} chiffrement={1,-12} protection={2,-4} methode={3}" -f `
            $v.MountPoint, $v.VolumeStatus, $st, $v.EncryptionMethod)
    }
    if (-not $bv) { Add-Line '  Aucun volume BitLocker rapporte.' }
} catch {
    Add-Line '  Get-BitLockerVolume indisponible (Windows Home ou droits insuffisants).'
    Add-Line '  Repli sur manage-bde :'
    try { (& manage-bde -status 2>&1 | Out-String) -split "`n" |
            Where-Object { $_ -match 'Volume|Conversion|Protection|Chiffrement|Encryption' } |
            ForEach-Object { Add-Line ("    " + $_.Trim()) } } catch { Add-Line '    indisponible.' }
}
Add-KV 'ACTION REQUISE AVANT REPARTITION' $(if ($BitLockerOn) {
    '>>> OUI : sauvegarder la cle + suspendre BitLocker <<<' } else { 'aucune (a confirmer ci-dessus)' })

# --- 4. Demarrage rapide / hibernation (risque n°2) -------------------------
Add-Header '4. DEMARRAGE RAPIDE ET HIBERNATION  (risque de corruption NTFS)'
try {
    $pw = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -EA Stop
    $hb = $pw.HiberbootEnabled
    Add-KV 'Demarrage rapide (Fast Startup)' $(if ($hb -eq 1) {
        'ACTIVE  -> A DESACTIVER avant le dual boot' } else { 'Desactive - OK' })
} catch { Add-KV 'Demarrage rapide' 'non lisible' }

Add-KV 'hiberfil.sys present' $(if (Test-Path 'C:\hiberfil.sys') { 'OUI' } else { 'non' })
try {
    $hs = (& powercfg /a 2>&1 | Out-String).Trim() -split "`n" | Select-Object -First 6
    Add-Line '  powercfg /a :' ; $hs | ForEach-Object { Add-Line ("    " + $_.Trim()) }
} catch { }

# --- 5. Controleur de stockage (risque n°3 : Intel RST / VMD) ---------------
Add-Header '5. CONTROLEUR DE STOCKAGE  (piege Intel RST / VMD)'
$RstDetected = $false
try {
    Get-CimInstance Win32_SCSIController -EA Stop | ForEach-Object {
        Add-Line ("  " + $_.Name)
        if ($_.Name -match 'RAID|RST|VMD|Rapid Storage') { $RstDetected = $true }
    }
    Get-CimInstance Win32_IDEController -EA SilentlyContinue | ForEach-Object { Add-Line ("  " + $_.Name) }
} catch { Add-Line "  [erreur] $_" }
Add-KV 'Mode RAID/RST/VMD suspecte' $(if ($RstDetected) {
    '>>> OUI : bascule en AHCI necessaire (procedure safeboot) <<<' } else { 'non - probablement AHCI/NVMe natif' })

# --- 6. Disques -------------------------------------------------------------
Add-Header '6. DISQUES PHYSIQUES'
try {
    Get-Disk | Sort-Object Number | ForEach-Object {
        Add-Line ''
        Add-Line ("  --- Disque {0} ---" -f $_.Number)
        Add-KV '  Modele'            $_.FriendlyName
        Add-KV '  Taille'            (ConvertTo-GB $_.Size)
        Add-KV '  Table de partition' $_.PartitionStyle
        Add-KV '  Interface'         $_.BusType
        Add-KV '  Etat'              $_.HealthStatus
        Add-KV '  Disque systeme'    ("boot={0} system={1}" -f $_.IsBoot, $_.IsSystem)
    }
} catch { Add-Line "  [erreur] $_" }

# --- 7. Partitions ----------------------------------------------------------
Add-Header '7. PARTITIONS'
try {
    Add-Line ("  {0,-5} {1,-5} {2,-6} {3,-12} {4,-22} {5}" -f 'Disq','Part','Lettre','Taille','Type','Label')
    Add-Line ('  ' + '-' * 70)
    Get-Partition | Sort-Object DiskNumber, PartitionNumber | ForEach-Object {
        $vol = $null
        if ($_.DriveLetter) { $vol = Get-Volume -DriveLetter $_.DriveLetter -EA SilentlyContinue }
        Add-Line ("  {0,-5} {1,-5} {2,-6} {3,-12} {4,-22} {5}" -f `
            $_.DiskNumber, $_.PartitionNumber,
            $(if ($_.DriveLetter) { $_.DriveLetter } else { '-' }),
            (ConvertTo-GB $_.Size), $_.Type,
            $(if ($vol) { $vol.FileSystemLabel } else { '' }))
    }
} catch { Add-Line "  [erreur] $_" }

# --- 8. Partition EFI -------------------------------------------------------
Add-Header '8. PARTITION EFI (ESP)  -- doit accueillir le bootloader Linux'
try {
    $esps = Get-Partition | Where-Object { $_.Type -eq 'System' -or $_.GptType -eq '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' }
    if ($esps) {
        foreach ($e in $esps) {
            $mb = [math]::Round($e.Size / 1MB)
            $verdict = if ($mb -lt 200) { 'PETITE - surveiller, ne garder qu un seul noyau Linux' }
                       elseif ($mb -lt 300) { 'correcte' } else { 'confortable' }
            Add-Line ("  Disque {0} partition {1} : {2} Mo  -> {3}" -f $e.DiskNumber, $e.PartitionNumber, $mb, $verdict)
        }
    } else { Add-Line '  Aucune ESP trouvee (machine probablement en Legacy/MBR).' }
} catch { Add-Line "  [erreur] $_" }

# --- 9. Espace libre et retrecissement possible -----------------------------
Add-Header '9. ESPACE DISPONIBLE ET RETRECISSEMENT MAXIMUM'
try {
    Get-Volume | Where-Object { $_.DriveLetter } | Sort-Object DriveLetter | ForEach-Object {
        Add-Line ("  {0}:  {1,-10} libre sur {2,-10} ({3})" -f `
            $_.DriveLetter, (ConvertTo-GB $_.SizeRemaining), (ConvertTo-GB $_.Size), $_.FileSystem)
    }
    Add-Line ''
    $sup = Get-PartitionSupportedSize -DriveLetter C -ErrorAction Stop
    $cur = (Get-Partition -DriveLetter C).Size
    $shrinkable = $cur - $sup.SizeMin
    Add-KV 'Taille actuelle de C:'       (ConvertTo-GB $cur)
    Add-KV 'Taille minimale atteignable' (ConvertTo-GB $sup.SizeMin)
    Add-KV 'RETRECISSEMENT MAX POSSIBLE' (ConvertTo-GB $shrinkable)
    Add-Line ''
    if ($shrinkable -lt 80GB) {
        Add-Line '  >>> ALERTE : moins de 80 Go liberables.'
        Add-Line '  >>> Des fichiers inamovibles bloquent le retrecissement.'
        Add-Line '  >>> Remede : desactiver hibernation + fichier d echange + protection systeme,'
        Add-Line '  >>>          redemarrer, defragmenter, puis relancer ce diagnostic.'
    } else {
        Add-Line '  OK : marge suffisante pour une partition Linux confortable.'
    }
} catch { Add-Line "  [erreur] Get-PartitionSupportedSize : $_" }

# --- 10. Fichier d'echange et protection systeme ----------------------------
Add-Header '10. FICHIERS BLOQUANT LE RETRECISSEMENT'
try {
    $pf = Get-CimInstance Win32_PageFileUsage -EA SilentlyContinue
    if ($pf) { $pf | ForEach-Object { Add-Line ("  Fichier d echange : {0} ({1} Mo)" -f $_.Name, $_.AllocatedBaseSize) } }
    else     { Add-Line '  Fichier d echange : gere automatiquement ou absent' }
} catch { }
try {
    $sr = & vssadmin list shadowstorage 2>&1 | Out-String
    Add-Line '  Stockage des points de restauration :'
    ($sr -split "`n" | Where-Object { $_ -match 'Used|Allocated|Utilise|Alloue' } |
        Select-Object -First 6) | ForEach-Object { Add-Line ("    " + $_.Trim()) }
} catch { Add-Line '  vssadmin indisponible' }

# --- 11. Entrees de demarrage UEFI ------------------------------------------
Add-Header '11. ENTREES DE DEMARRAGE DU FIRMWARE'
try {
    $fw = & bcdedit /enum firmware 2>&1 | Out-String
    if ($fw -match 'identificateur|identifier') {
        ($fw -split "`n" | Where-Object { $_ -match 'description|identifier|identificateur' }) |
            ForEach-Object { Add-Line ("  " + $_.Trim()) }
    } else { Add-Line '  Non lisible (droits administrateur requis).' }
} catch { Add-Line '  Non lisible.' }

# --- Synthese ---------------------------------------------------------------
Add-Header 'SYNTHESE DES POINTS A TRAITER'
$n = 0
if ($BitLockerOn)                 { $n++ ; Add-Line "  [$n] BitLocker actif  -> sauvegarder la cle de recuperation PUIS suspendre." }
if ($RstDetected)                 { $n++ ; Add-Line "  [$n] Controleur RAID/RST/VMD -> basculer en AHCI via la procedure safeboot." }
if ($FirmwareMode -like 'LEGACY*'){ $n++ ; Add-Line "  [$n] Windows demarre en Legacy/BIOS -> installer Linux en Legacy aussi (pas d UEFI)." }
try {
    $pw2 = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -EA SilentlyContinue
    if ($pw2.HiberbootEnabled -eq 1) { $n++ ; Add-Line "  [$n] Demarrage rapide actif -> a desactiver (risque de corruption NTFS)." }
} catch { }
if ($n -eq 0) { Add-Line '  Aucun point bloquant detecte automatiquement.' }
Add-Line ''
Add-Line '  La sauvegarde image complete reste OBLIGATOIRE dans tous les cas.'

# --- Ecriture ---------------------------------------------------------------
try {
    $script:Lines | Out-File -FilePath $Report -Encoding UTF8 -Force
    Add-Line ''
    Add-Line ('Rapport ecrit dans : ' + $Report)
} catch {
    Write-Host "Impossible d ecrire le rapport : $_" -ForegroundColor Red
}
Add-Line ''
Add-Line 'Termine. Aucune modification n a ete faite sur cette machine.'
