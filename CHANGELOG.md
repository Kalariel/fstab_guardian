# Changelog

Toutes les modifications notables de ce projet seront documentées dans ce fichier.

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