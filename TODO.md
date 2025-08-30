# TODO - Fonctionnalités futures

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
- [ ] Tests d'intégration des hooks de recovery
- [ ] Support pour autres systèmes d'init (non-systemd)

## Déjà fait ✅
- [x] `restore` interactif sans --from
- [x] `backup --comment "text"`  
- [x] `clean-backups --older-than 30d`
- [x] `restore --from <file>`
- [x] `validate --test`
- [x] `compare <file1> <file2>`
- [x] `install-boot-recovery` - Hooks systemd/initramfs
- [x] `test-boot-recovery` - Simulation recovery
- [x] `boot-logs` - Logs de recovery
- [x] **Refactorisation modulaire complète** - Séparation en 5 modules distincts (validation, backup, admin, editor, recovery)