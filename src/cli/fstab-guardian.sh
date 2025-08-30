#!/bin/bash
# fstab-guardian - Never brick your system again!
# Main orchestrator script

set -euo pipefail

# =============================================================================
# INITIALIZATION
# =============================================================================

# Chemins et configuration de base
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/../validators/fstab_validator.sh"

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# =============================================================================
# MODULE LOADING
# =============================================================================

# Charger tous les modules
for module in "$SCRIPT_DIR/modules"/*.sh; do
    if [[ -f "$module" ]]; then
        source "$module"
    fi
done

# =============================================================================
# MAIN LOGIC
# =============================================================================

# Charger la configuration
load_config

# Dispatcher principal
case "${1:-}" in
    # === VALIDATION ===
    "validate"|"check")
        if [[ "${2:-}" == "--test" ]]; then
            # Validate puis test des mounts
            fstab_file="${3:-/etc/fstab}"
            if validate_fstab_file "$fstab_file"; then
                echo "" # Ligne vide
                test_mounts "$fstab_file"
            else
                echo -e "\n${RED}❌ Cannot test mounts: validation failed${NC}"
                exit 1
            fi
        else
            # Validation normale
            validate_fstab_file "${2:-}"
        fi
        ;;
        
    # === BACKUP MANAGEMENT ===
    "backup")
        if [[ "${2:-}" == "--comment" ]] && [[ -n "${3:-}" ]]; then
            backup_fstab "${4:-}" "$3"
        else
            backup_fstab "${2:-}"
        fi
        ;;
        
    "list-backups"|"backups")
        list_backups
        ;;
        
    "clean-backups")
        if [[ "${2:-}" == "--older-than" ]] && [[ -n "${3:-}" ]]; then
            clean_old_backups "$3"
        else
            echo -e "${RED}❌ Usage: fstab-guardian clean-backups --older-than <time>${NC}"
            echo "Time format: 30d (days), 24h (hours), 60m (minutes)"
            echo "Example: fstab-guardian clean-backups --older-than 30d"
            exit 1
        fi
        ;;
        
    # === RESTORE ===
    "restore")
        if [[ "${2:-}" == "--from" ]] && [[ -n "${3:-}" ]]; then
            restore_backup "$3"
        else
            restore_interactive
        fi
        ;;
        
    # === EDITING ===
    "edit")
        edit_fstab "${2:-}"
        ;;
        
    # === COMPARISON ===
    "compare")
        if [[ -n "${2:-}" ]] && [[ -n "${3:-}" ]]; then
            compare_fstab "$2" "$3"
        else
            echo -e "${RED}❌ Usage: fstab-guardian compare <file1> <file2>${NC}"
            echo "Example: fstab-guardian compare /etc/fstab /tmp/test-fstab"
            exit 1
        fi
        ;;
        
    # === ADMINISTRATION ===
    "config")
        case "${2:-show}" in
            "show"|"")
                show_config
                ;;
            "edit")
                edit_config
                ;;
            *)
                echo "Usage: fstab-guardian config {show|edit}"
                exit 1
                ;;
        esac
        ;;
        
    "status")
        show_status
        ;;
        
    "install")
        install_system
        ;;
        
    # === BOOT RECOVERY ===
    "install-boot-recovery")
        install_boot_recovery
        ;;
        
    "test-boot-recovery")
        test_boot_recovery
        ;;
        
    "boot-logs")
        show_boot_logs
        ;;
        
    # === HELP ===
    "help"|"--help"|"-h"|"")
        show_help
        ;;
        
    # === ERROR ===
    *)
        echo -e "${RED}❌ Unknown command: $1${NC}"
        echo "Run 'fstab-guardian help' for usage information."
        exit 1
        ;;
esac