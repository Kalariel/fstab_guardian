#!/bin/bash
# fstab-guardian admin module
# Administration, configuration, installation, statut

show_help() {
    cat << EOF
🛡️  fstab-guardian - Never brick your system again!

Usage: fstab-guardian <command> [options]

Commands:
    validate [--test] [file]  Validate fstab syntax (default: /etc/fstab)
                            --test: also test mount operations
    edit [file]         Edit fstab with automatic validation
    backup [file]       Create backup of current fstab
                        --comment "text": add comment to backup
    list-backups        List available backups
    clean-backups --older-than <time>  Clean old backups (30d, 24h, 60m)
    restore             Interactive restore (choose from backups)
                        --from <backup-file>: restore specific backup
    compare <file1> <file2>       Compare two fstab files
    status              Show system status and recovery logs
    config show|edit    Show or edit configuration
    install             Install fstab-guardian system
    install-boot-recovery   Install boot recovery hooks
    test-boot-recovery      Simulate boot recovery process
    boot-logs          Show boot recovery logs
    help                Show this help message
    
Examples:
    fstab-guardian validate                    # Check /etc/fstab
    fstab-guardian validate --test             # Check /etc/fstab and test mounts
    fstab-guardian validate /tmp/my-fstab      # Check specific file
    fstab-guardian backup                      # Backup current fstab
    fstab-guardian backup --comment "Before kernel upgrade"  # Backup with comment
    fstab-guardian list-backups                # Show available backups
    fstab-guardian clean-backups --older-than 30d  # Clean backups older than 30 days
    fstab-guardian restore                     # Interactive restore
    fstab-guardian restore --from fstab_20231201_123456  # Restore backup
    fstab-guardian compare /etc/fstab /tmp/test-fstab     # Compare files
    fstab-guardian config edit                 # Edit configuration
    fstab-guardian install-boot-recovery       # Install boot recovery
    fstab-guardian boot-logs                   # Show recovery logs

EOF
}

load_config() {
    # Valeurs par défaut
    BACKUP_DIR="/etc/fstab-backups"
    BACKUP_KEEP_COUNT=10
    EDITOR="${EDITOR:-nano}"
    ENABLE_MOUNT_TEST=true
    DEBUG_MODE=false
    BOOT_RECOVERY_ENABLED=true
    RECOVERY_LOG="/var/log/fstab-guardian.log"
    
    # Charger la config utilisateur si elle existe
    if [[ -f "/etc/fstab-guardian.conf" ]]; then
        source "/etc/fstab-guardian.conf"
    fi
    
    # Variables d'environnement peuvent override
    BACKUP_DIR="${FG_BACKUP_DIR:-$BACKUP_DIR}"
    BACKUP_KEEP_COUNT="${FG_BACKUP_KEEP_COUNT:-$BACKUP_KEEP_COUNT}"
    EDITOR="${FG_EDITOR:-$EDITOR}"
}

show_config() {
    echo -e "${YELLOW}⚙️  Current configuration:${NC}"
    echo "----------------------------------------"
    echo "Backup directory: $BACKUP_DIR"
    echo "Backups to keep: $BACKUP_KEEP_COUNT"
    echo "Default editor: $EDITOR"
    echo "Mount test enabled: $ENABLE_MOUNT_TEST"
    echo "Debug mode: $DEBUG_MODE"
    echo "Boot recovery enabled: $BOOT_RECOVERY_ENABLED"
    echo "Recovery log: $RECOVERY_LOG"
}

edit_config() {
    local config_file="/etc/fstab-guardian.conf"
    
    # Créer la config par défaut si elle n'existe pas
    if [[ ! -f "$config_file" ]]; then
        create_default_config
    fi
    
    # Éditer avec l'éditeur configuré
    if command -v "$EDITOR" >/dev/null 2>&1; then
        sudo "$EDITOR" "$config_file"
    else
        echo -e "${YELLOW}⚠️  Editor '$EDITOR' not found. Using nano...${NC}"
        sudo nano "$config_file"
    fi
}

show_status() {
    echo -e "${YELLOW}📊 fstab-guardian System Status${NC}"
    echo "============================================="
    
    # 1. Validation du fstab actuel
    echo -e "\n🔍 Current fstab validation:"
    if bash "$VALIDATOR" /etc/fstab >/dev/null 2>&1; then
        echo -e "   ${GREEN}✅ /etc/fstab is valid${NC}"
    else
        echo -e "   ${RED}❌ /etc/fstab has issues${NC}"
        echo "   Run 'fstab-guardian validate' for details"
    fi
    
    # 2. Backups disponibles
    echo -e "\n💾 Backup status:"
    local backup_count
    backup_count=$(find "$BACKUP_DIR" -name "fstab_*" -type f 2>/dev/null | wc -l)
    if [[ $backup_count -gt 0 ]]; then
        echo -e "   ${GREEN}✅ $backup_count backups available${NC}"
        local latest_backup
        latest_backup=$(find "$BACKUP_DIR" -name "fstab_*" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
        if [[ -n "$latest_backup" ]]; then
            echo "   📅 Latest: $(basename "$latest_backup") ($(date -r "$latest_backup" '+%Y-%m-%d %H:%M:%S'))"
        fi
    else
        echo -e "   ${YELLOW}⚠️  No backups found${NC}"
        echo "   Run 'fstab-guardian backup' to create one"
    fi
    
    # 3. Boot recovery status
    echo -e "\n🛡️  Boot recovery:"
    if check_boot_recovery_installed; then
        echo -e "   ${GREEN}✅ Boot recovery hooks installed${NC}"
        
        # Vérifier les logs de recovery récents
        if [[ -f "$RECOVERY_LOG" ]]; then
            local recent_logs
            recent_logs=$(tail -10 "$RECOVERY_LOG" 2>/dev/null | wc -l)
            if [[ $recent_logs -gt 0 ]]; then
                echo "   📄 Recent recovery logs: $recent_logs entries"
            fi
        fi
    else
        echo -e "   ${YELLOW}⚠️  Boot recovery not installed${NC}"
        echo "   Run 'fstab-guardian install-boot-recovery' to enable"
    fi
    
    # 4. Configuration
    echo -e "\n⚙️  Configuration:"
    echo "   📁 Backup dir: $BACKUP_DIR"
    echo "   📝 Editor: $EDITOR"
    echo "   🔢 Keep backups: $BACKUP_KEEP_COUNT"
    
    # 5. Recommandations
    echo -e "\n💡 Recommendations:"
    if [[ $backup_count -eq 0 ]]; then
        echo "   • Create a backup: fstab-guardian backup"
    fi
    if ! check_boot_recovery_installed; then
        echo "   • Install boot protection: fstab-guardian install"
    fi
    if ! bash "$VALIDATOR" /etc/fstab >/dev/null 2>&1; then
        echo "   • Fix fstab issues: fstab-guardian validate"
    fi
}

install_system() {
    echo -e "${YELLOW}📦 Installing fstab-guardian system${NC}"
    echo "============================================="
    
    # Vérifier les permissions root
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ Installation requires root privileges${NC}"
        echo "Please run: sudo fstab-guardian install"
        return 1
    fi
    
    # 1. Créer les dossiers nécessaires
    echo "📁 Creating directories..."
    sudo mkdir -p "$BACKUP_DIR"
    sudo mkdir -p "$(dirname "$RECOVERY_LOG")"
    
    # 2. Créer la config par défaut
    create_default_config
    
    # 3. Copier le script principal vers /usr/local/bin
    echo "📄 Installing script..."
    sudo cp "$SCRIPT_DIR/fstab-guardian.sh" /usr/local/bin/fstab-guardian
    sudo chmod +x /usr/local/bin/fstab-guardian
    
    # 4. Créer un backup initial
    echo "💾 Creating initial backup..."
    backup_fstab
    
    echo -e "${GREEN}✅ Installation complete!${NC}"
    echo ""
    echo "Next steps:"
    echo "• Test: fstab-guardian validate"
    echo "• Enable boot protection: sudo fstab-guardian install-boot-recovery"
    echo "• Show status: fstab-guardian status"
}

create_default_config() {
    local config_file="/etc/fstab-guardian.conf"
    
    if [[ -f "$config_file" ]]; then
        echo "⚠️  Config file already exists: $config_file"
        return 0
    fi
    
    cat > "$config_file" << EOF
# fstab-guardian configuration file
# Created: $(date)

# Backup settings
BACKUP_DIR="/etc/fstab-backups"
BACKUP_KEEP_COUNT=10

# Editor preference  
EDITOR="nano"

# Validation settings
ENABLE_MOUNT_TEST=true
DEBUG_MODE=false

# Boot recovery settings
BOOT_RECOVERY_ENABLED=true
RECOVERY_LOG="/var/log/fstab-guardian.log"
EOF
    
    echo "✅ Config created: /etc/fstab-guardian.conf"
}