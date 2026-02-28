# 🛡️ fstab_guardian

Never brick your system again with a malformed fstab!

## Qu'est-ce que ça fait ?
- **Valide la syntaxe fstab** avant le démarrage du système
- **Récupération automatique** depuis une sauvegarde si fstab est corrompu
- **Affichage coloré** du fstab avec coloration syntaxique
- **Ajout interactif de disques** avec nom convivial, point de montage et options
- **Édition sécurisée** avec validation automatique et backup
- **Gestion complète des sauvegardes** avec rotation automatique

## Installation

```bash
# Depuis la racine du projet
sudo bash install.sh

# Protection au boot (optionnel mais recommandé)
sudo fstab-guardian install-boot-recovery
```

## Architecture

### 🏗️ Architecture modulaire
- **CLI principal** : `src/cli/fstab-guardian.sh` - orchestrateur principal
- **Script d'installation** : `install.sh` - à la racine du projet
- **Modules séparés** dans `src/cli/modules/` :
  - `validation.sh` - Validation fstab, affichage coloré et tests de montage
  - `backup.sh` - Gestion complète des sauvegardes
  - `admin.sh` - Administration, configuration, installation
  - `editor.sh` - Édition sécurisée avec validation temps-réel
  - `recovery.sh` - Interface boot recovery et hooks système
  - `disk_add.sh` - Ajout interactif de disques au fstab

### ✅ Validation intelligente
- **Erreurs critiques** : Problèmes qui empêchent le boot (UUID malformés, points de montage dupliqués, flags invalides)
- **Warnings informatifs** : Problèmes qui peuvent causer des échecs de mount mais permettent au système de démarrer
- **Support complet** : UUID, LABEL, chemins de devices, filesystems réseau (NFS/CIFS), filesystems virtuels

## Commandes

### Consulter le fstab

```bash
# Affichage coloré du fstab (commentaires, devices, types, options)
fstab-guardian show

# Afficher un fichier spécifique
fstab-guardian show /tmp/test-fstab

# Valider la syntaxe
fstab-guardian validate

# Valider et tester les montages
fstab-guardian validate --test
```

Exemple de sortie de `show` :
```
📄 /etc/fstab  14 lignes · 754 octets · modifié le 2026-02-27 23:13
──────────────────────────────────────────────────────────────────────
  1  # /etc/fstab: static file system information.
  2
  3  UUID=abc-123  /         ext4  errors=remount-ro  0 1
  4  UUID=def-456  /boot/efi vfat  umask=0077         0 1
  5  UUID=ghi-789  none      swap  sw                 0 0
──────────────────────────────────────────────────────────────────────
```

### Ajouter un disque

```bash
# Lancer l'assistant interactif
fstab-guardian add

# Lister les disques disponibles sans modifier le fstab
fstab-guardian add --list
```

L'assistant `add` :
1. Scanne les périphériques bloc et filtre ceux déjà dans fstab
2. Affiche un tableau numéroté (device, UUID, type, taille, label, état)
3. Demande un **nom convivial** (ajouté en commentaire dans fstab)
4. Propose un point de montage basé sur le nom (ex: `/mnt/mon_disque`)
5. Suggère des options adaptées au type de filesystem (NTFS, FAT, ext4…)
6. Crée le répertoire de montage si nécessaire
7. Backup → validation → application

Résultat dans fstab :
```
# Mon disque données - Added by fstab-guardian 2026-02-27 14:30
UUID=abc-123 /mnt/mon_disque_donnees ext4 defaults,nofail 0 2
```

### Édition sécurisée

```bash
# Éditer avec backup automatique et validation avant application
fstab-guardian edit
```

### Gestion des sauvegardes

```bash
fstab-guardian backup
fstab-guardian backup --comment "Avant mise à jour kernel"
fstab-guardian list-backups
fstab-guardian restore
fstab-guardian restore --from fstab_20260227_143000
fstab-guardian clean-backups --older-than 30d
```

### Administration

```bash
fstab-guardian status          # Vue d'ensemble du système
fstab-guardian config show     # Afficher la configuration
fstab-guardian config edit     # Modifier la configuration
fstab-guardian compare /etc/fstab /tmp/test-fstab
```

### 🛡️ Sécurité renforcée
- **Backup automatique** avant toute modification
- **Validation en temps réel** pendant l'édition et l'ajout
- **Recovery interactif** en cas d'erreur
- **Rotation des sauvegardes** (garde les 10 plus récentes par défaut)
- **Recovery automatique au boot** si fstab corrompu

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

## Exemple de sortie de validation

```bash
$ fstab-guardian validate
❌ Validation failed with 1 critical error(s) that will prevent boot:
   Line 3: Invalid UUID format: not-a-uuid

⚠️  Found 2 warning(s) (mount may fail but system will boot):
   WARNING: Line 2: UUID not found in system: 99999999-9999-9999-9999-999999999999
   WARNING: Line 4: Unknown filesystem type: unknownfs
```

## Tests

Le projet inclut une suite de tests complète avec **33 scénarios** couvrant :
- Cas réalistes (Ubuntu, serveur)
- Validation boot-critical vs warnings
- Types de devices variés (UUID, LABEL, /dev/, réseau)
- Gestion d'erreurs robuste

```bash
bats tests/test_fstab_validators.bats
```

## Note

Projet personnel pour explorer l'écriture de scripts et les tests. Des outils similaires existent peut-être déjà !
