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
    show [file]         Display fstab with syntax highlighting (default: /etc/fstab)
    add [file]          Interactively add a disk/partition to fstab
                        --list: only list available disks (no modification)
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
    uninstall           Uninstall fstab-guardian (keeps backups and config)
    install-boot-recovery   Install boot recovery hooks
    test-boot-recovery      Simulate boot recovery process
    boot-logs          Show boot recovery logs
    help                Show this help message
    
Examples:
    fstab-guardian validate                    # Check /etc/fstab
    fstab-guardian validate --test             # Check /etc/fstab and test mounts
    fstab-guardian validate /tmp/my-fstab      # Check specific file
    fstab-guardian show                        # Display /etc/fstab
    fstab-guardian show /tmp/my-fstab          # Display specific file
    fstab-guardian add                         # Add a disk interactively
    fstab-guardian add --list                  # List available disks
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

    local dest_bin="/usr/local/bin/fstab-guardian"
    local dest_lib="/usr/local/lib/fstab-guardian"

    # Répertoire source (src/) depuis SCRIPT_DIR (src/cli/)
    local src_dir
    src_dir="$(cd "$SCRIPT_DIR/.." && pwd)"

    # 1. Créer l'arborescence des dossiers
    echo "📁 Creating directories..."
    mkdir -p "$dest_lib/modules"
    mkdir -p "$dest_lib/validators"
    mkdir -p "$dest_lib/boot"
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$(dirname "$RECOVERY_LOG")"

    # 2. Installer le script principal
    echo "📄 Installing main script → $dest_bin"
    cp "$SCRIPT_DIR/fstab-guardian.sh" "$dest_bin"
    chmod 755 "$dest_bin"

    # 3. Installer les modules
    echo "📦 Installing modules → $dest_lib/modules/"
    cp "$SCRIPT_DIR/modules/"*.sh "$dest_lib/modules/"
    chmod 644 "$dest_lib/modules/"*.sh

    # 4. Installer le validator
    echo "🔍 Installing validator → $dest_lib/validators/"
    cp "$src_dir/validators/"*.sh "$dest_lib/validators/"
    chmod 755 "$dest_lib/validators/"*.sh

    # 5. Installer les scripts de boot recovery
    echo "🛡️  Installing boot scripts → $dest_lib/boot/"
    cp "$src_dir/boot/"*.sh "$dest_lib/boot/"
    chmod 755 "$dest_lib/boot/"*.sh

    # 6. Créer la config par défaut
    create_default_config

    # 7. Backup initial du fstab
    echo "💾 Creating initial backup..."
    backup_fstab

    echo ""
    echo -e "${GREEN}✅ Installation complete!${NC}"
    echo ""
    echo "   Binary  : $dest_bin"
    echo "   Lib dir : $dest_lib"
    echo "   Config  : /etc/fstab-guardian.conf"
    echo "   Backups : $BACKUP_DIR"
    echo ""
    echo "Next steps:"
    echo "  • fstab-guardian validate"
    echo "  • sudo fstab-guardian install-boot-recovery"
    echo "  • fstab-guardian status"
}

uninstall_system() {
    echo -e "${YELLOW}🗑️  Uninstalling fstab-guardian system${NC}"
    echo "============================================="

    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ Uninstallation requires root privileges${NC}"
        echo "Please run: sudo fstab-guardian uninstall"
        return 1
    fi

    echo -n "This will remove the binary and lib files (backups are kept). Continue? [y/N]: "
    read -r confirm
    [[ "$confirm" != "y" ]] && [[ "$confirm" != "Y" ]] && { echo "Cancelled."; return 0; }

    rm -f /usr/local/bin/fstab-guardian
    rm -rf /usr/local/lib/fstab-guardian

    echo -e "${GREEN}✅ fstab-guardian uninstalled.${NC}"
    echo "   Backups kept in: $BACKUP_DIR"
    echo "   Config kept at:  /etc/fstab-guardian.conf"
    echo "   Remove manually if desired."
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