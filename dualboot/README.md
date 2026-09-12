# Dual boot Windows + Linux — outillage

## `Diagnostic-DualBoot.ps1`

Script PowerShell **100 % lecture seule** à lancer sur la machine Windows
**avant** toute opération de partitionnement.

Il ne modifie rien : il lit la configuration et écrit `Rapport-DualBoot.txt`
sur le Bureau.

### Ce qu'il relève

| Section | Pourquoi c'est déterminant |
|---|---|
| Firmware UEFI / Legacy | décide du mode d'installation Linux |
| Secure Boot | décide du choix de distribution |
| **BitLocker** | cause n°1 de « Windows ne démarre plus » |
| **Démarrage rapide / hibernation** | cause n°1 de corruption du NTFS |
| **Contrôleur Intel RST / VMD** | cause n°1 d'`INACCESSIBLE_BOOT_DEVICE` |
| Disques, partitions, taille de l'ESP | dimensionnement du bootloader |
| Rétrécissement maximum de `C:` | espace réellement libérable |

### Utilisation

```powershell
# PowerShell lancé en tant qu'administrateur
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\Diagnostic-DualBoot.ps1
```

Le rapport généré est à relire avant partage : il contient le modèle de la
machine et la table des partitions, mais **aucune clé de chiffrement ni
donnée personnelle**.

### Validation

Syntaxe vérifiée avec le parseur PowerShell 7.6.6 et exécution de bout en
bout testée (les cmdlets Windows absentes sont interceptées proprement).
