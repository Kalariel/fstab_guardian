#!/bin/bash
# fstab-recovery.sh - Boot recovery system for fstab_guardian
# Restaure automatiquement le fstab depuis un backup si le boot échoue

set -euo pipefail

BACKUP_DIR="/etc/fstab-backups"
RECOVERY_LOG="/var/log/fstab-guardian.log"
FSTAB_FILE="/etc/fstab"

log_recovery() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$RECOVERY_LOG"
}

# Vérifier si fstab est corrompu
is_fstab_corrupted() {
    local validator="/usr/local/bin/fstab-guardian"
    
    # Si le validator n'existe pas, on ne peut pas vérifier
    if [[ ! -x "$validator" ]]; then
        return 1
    fi
    
    # Tester la validation (mode silencieux)
    ! "$validator" validate > /dev/null 2>&1
}

# Trouver le backup le plus récent valide
find_valid_backup() {
    local validator="/usr/local/bin/fstab-guardian"
    
    # Lister les backups par date (plus récent en premier)
    find "$BACKUP_DIR" -name "fstab_*" -type f -printf '%T@ %p\n' 2>/dev/null | \
    sort -rn | \
    while read -r _ backup_file; do
        # Tester si ce backup est valide
        if [[ -x "$validator" ]] && "$validator" validate "$backup_file" > /dev/null 2>&1; then
            echo "$backup_file"
            return 0
        fi
    done
    
    # Aucun backup valide trouvé
    return 1
}

# Restaurer depuis un backup
restore_from_backup() {
    local backup_file="$1"
    
    log_recovery "RECOVERY: Attempting restore from $backup_file"
    
    # Sauvegarder le fstab corrompu pour investigation
    local corrupted_backup
    corrupted_backup="/var/log/fstab-corrupted-$(date +%Y%m%d_%H%M%S)"
    cp "$FSTAB_FILE" "$corrupted_backup" 2>/dev/null || true
    log_recovery "RECOVERY: Corrupted fstab saved as $corrupted_backup"
    
    # Restaurer le backup
    if cp "$backup_file" "$FSTAB_FILE"; then
        log_recovery "RECOVERY: Successfully restored from $backup_file"
        return 0
    else
        log_recovery "RECOVERY: Failed to restore from $backup_file"
        return 1
    fi
}

# Point d'entrée principal
main() {
    log_recovery "RECOVERY: Boot recovery check started"
    
    # Vérifier si le dossier de backup existe
    if [[ ! -d "$BACKUP_DIR" ]]; then
        log_recovery "RECOVERY: No backup directory found at $BACKUP_DIR"
        exit 1
    fi
    
    # Vérifier si fstab est corrompu
    if ! is_fstab_corrupted; then
        log_recovery "RECOVERY: fstab is valid, no recovery needed"
        exit 0
    fi
    
    log_recovery "RECOVERY: fstab corruption detected, searching for valid backup"
    
    # Chercher un backup valide
    local backup_file
    if backup_file=$(find_valid_backup); then
        log_recovery "RECOVERY: Found valid backup: $backup_file"
        
        if restore_from_backup "$backup_file"; then
            log_recovery "RECOVERY: System recovered successfully"
            # Forcer un remount pour appliquer le nouveau fstab
            mount -a 2>/dev/null || true
            exit 0
        else
            log_recovery "RECOVERY: Failed to restore backup"
            exit 1
        fi
    else
        log_recovery "RECOVERY: No valid backup found, manual intervention required"
        exit 1
    fi
}

# Exécuter seulement si appelé directement
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi