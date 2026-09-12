# Poste de travail distant — la tour comme atelier

Installer Linux sur une machine fixe puissante et l'utiliser depuis un portable
via SSH, plutôt que d'installer Linux sur le portable lui-même.

Intérêt : le portable garde son Windows intact, la puissance reste là où elle
est, et les services qui doivent tourner en continu (bot, indexeur, nœud) vivent
sur une machine qui ne se met jamais en veille.

## `diagnostic-tour.sh`

Script **100 % lecture seule** à exécuter sur la machine fixe, avant toute
installation. Aucune écriture disque, aucun paquet installé, aucun service
démarré ou arrêté.

```bash
# Depuis le portable, sans rien copier :
ssh utilisateur@tour 'bash -s' < diagnostic-tour.sh

# Ou directement sur la machine :
bash diagnostic-tour.sh
```

`sudo` n'est pas requis — certaines lignes seront simplement moins détaillées.

### Ce qu'il relève

| Section | Décision qu'elle permet |
|---|---|
| Système, virtualisation, WSL | la machine est-elle un vrai Linux autonome ? |
| Mode d'exécution | headless ou bureau graphique installé |
| CPU / RAM | dimensionnement des VM ou conteneurs |
| GPU | streaming du bureau possible, ou terminal seul |
| Stockage | disque libre pour un système dédié, ou partitionnement nécessaire |
| Réseau et débit des liens | filaire gigabit ou sans-fil |
| Serveur SSH | ce qu'il reste à durcir avant exposition |
| Outillage présent | ce qui est déjà installé |
| Cibles de veille | aptitude au fonctionnement 24/7 |

### Validation

Syntaxe vérifiée (`bash -n`) et script exécuté de bout en bout sur une machine
Linux réelle. Les commandes absentes sont interceptées proprement et signalées
plutôt que de produire une section vide.
