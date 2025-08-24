# TODO - Fonctionnalités futures

## Gestion avancée des backups
- [ ] `restore` interactif sans --from
- [ ] `backup --comment "text"`  
- [ ] `clean-backups --older-than 30d`

## Validation avancée  
- [ ] `validate --strict` (warnings = erreurs)
- [ ] `validate --ignore-warnings`
- [ ] `validate --format json`

## Outils pratiques
- [ ] `generate` (créer fstab depuis mounts actuels)
- [ ] `show-mounts` (comparer fstab vs système)
- [ ] `find-uuid /dev/sda1`
- [ ] `diff` (fstab vs mounts actuels)
- [ ] `fix --auto` (corrections automatiques)

## Boot recovery
- [ ] `install-boot-hooks`
- [ ] Scripts dans src/boot/ (actuellement vide)

## Déjà fait ✅
- [x] `restore --from <file>`
- [x] `validate --test`
- [x] `compare <file1> <file2>`