# Changelog

Toutes les modifications notables de ce projet seront documentées dans ce fichier.

## [Non publié] - 2026-02-27

### ✨ Nouvelles fonctionnalités
- **Commande `add`** : Ajout interactif de disques/partitions au fstab
  - Scan automatique des périphériques bloc via `lsblk`
  - Filtre les devices déjà présents dans fstab
  - Tableau numéroté avec device, UUID, type, taille, label et état de montage
  - Saisie d'un nom convivial ajouté en commentaire dans fstab
  - Point de montage suggéré automatiquement d'après le nom
  - Options de montage adaptées au filesystem (NTFS, FAT, exFAT, ext4…)
  - Création automatique du répertoire de montage
  - Gestion séparée des partitions swap
  - Option `--list` pour lister sans modifier
- **Commande `show`** (alias `cat`) : Affichage coloré du fstab
  - En-tête avec chemin, nombre de lignes, taille et date de modification
  - Commentaires en jaune, devices en cyan/gras, fstypes en vert, options grisées
  - Numéros de ligne
- **Script `install.sh`** à la racine du projet
  - Permet d'installer depuis la racine sans naviguer dans `src/cli/`
  - Usage : `sudo bash install.sh`

### 🔧 Technique
- Nouveau module `src/cli/modules/disk_add.sh`
- Parsing `lsblk -P` sans `eval` (extraction par grep/cut)
- Correction bug `set -e` sur `((line_num++))` → remplacé par `$((line_num + 1))`

## [Non publié] - 2025-08-30

### 🏗️ Changements majeurs
- **Refactorisation modulaire complète** : Restructuration du CLI monolithique en architecture modulaire
  - Script principal réduit de ~800 à 130 lignes
  - Séparation en 5 modules spécialisés dans `src/cli/modules/` :
    - `validation.sh` - Validation fstab et tests de montage
    - `backup.sh` - Gestion complète des sauvegardes et restore
    - `admin.sh` - Administration, configuration système, installation
    - `editor.sh` - Édition sécurisée avec validation en temps réel
    - `recovery.sh` - Interface boot recovery et hooks système

### ✨ Améliorations
- **Maintenabilité** : Code organisé par domaine fonctionnel
- **Lisibilité** : Chaque module se concentre sur sa responsabilité
- **Évolutivité** : Ajout facile de nouvelles fonctionnalités
- **Backward compatibility** : Conservation de l'ancienne version en `fstab-guardian-old.sh`

### 🔧 Technique
- Chargement dynamique des modules au démarrage
- Conservation de toutes les fonctionnalités existantes
- Architecture prête pour extensions futures (API REST, plugins)

## [Précédent] - 2025-08-29

### 🚀 Fonctionnalités
- Implémentation gestion avancée des backups
- Boot Recovery + hooks système
- Interface CLI complète