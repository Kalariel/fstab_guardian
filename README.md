# 🛡️ fstab_guardian

Never brick your system again with a malformed fstab!

## Qu'est-ce que ça fait ?
- **Valide la syntaxe fstab** avant le démarrage du système
- **Récupération automatique** depuis une sauvegarde si fstab est corrompu  
- **Rapports de statut clairs** avec distinction erreurs/warnings
- **Édition sécurisée** avec validation automatique et backup
- **Gestion complète des sauvegardes** avec rotation automatique

## Fonctionnalités principales

### ✅ Validation intelligente
- **Erreurs critiques** : Problèmes qui empêchent le boot (UUID malformés, points de montage dupliqués, flags invalides)
- **Warnings informatifs** : Problèmes qui peuvent causer des échecs de mount mais permettent au système de démarrer
- **Support complet** : UUID, LABEL, chemins de devices, filesystems réseau (NFS/CIFS), filesystems virtuels

### 🔧 CLI intuitive
```bash
# Validation simple
fstab-guardian validate /etc/fstab

# Édition sécurisée avec backup automatique
fstab-guardian edit

# Gestion des sauvegardes
fstab-guardian backup
fstab-guardian list-backups

# Statut du système
fstab-guardian status
```

### 🛡️ Sécurité renforcée  
- **Backup automatique** avant toute modification
- **Validation en temps réel** pendant l'édition
- **Recovery interactif** en cas d'erreur
- **Rotation des sauvegardes** (garde les 10 plus récentes par défaut)
- **Recovery automatique au boot** si fstab corrompu

## Exemple de sortie

```bash
$ fstab-guardian validate
❌ Validation failed with 1 critical error(s) that will prevent boot:
   Line 3: Invalid UUID format: not-a-uuid

⚠️  Found 2 warning(s) (mount may fail but system will boot):
   WARNING: Line 2: UUID not found in system: 99999999-9999-9999-9999-999999999999
   WARNING: Line 4: Unknown filesystem type: unknownfs
```

## Installation

```bash
# Installation système
sudo fstab-guardian install

# Test de validation
fstab-guardian validate

# Configuration
fstab-guardian config edit

# Protection au boot (optionnel)
sudo fstab-guardian install-boot-recovery
```

## Boot Recovery

Protection automatique contre les fstab corrompus au boot :

- **Détection automatique** des erreurs fstab au démarrage
- **Restauration intelligente** depuis le backup le plus récent valide  
- **Double protection** : hooks systemd + initramfs
- **Logging complet** dans `/var/log/fstab-guardian.log`

```bash
# Installer la protection boot
sudo fstab-guardian install-boot-recovery

# Tester le système de recovery
sudo fstab-guardian test-boot-recovery  

# Voir les logs de recovery
fstab-guardian boot-logs
```

## Tests

Le projet inclut une suite de tests complète avec **33 scénarios** couvrant :
- Cas réalistes (Ubuntu, serveur)
- Validation boot-critical vs warnings
- Types de devices variés (UUID, LABEL, /dev/, réseau)
- Gestion d'erreurs robuste

```bash
# Lancer les tests
bats tests/test_fstab_validators.bats
```

## Note

Projet personnel pour explorer l'écriture de scripts et les tests. Des outils similaires existent peut-être déjà !