#!/bin/bash
set -euo pipefail

# Chemin vers le validateur
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATOR="$SCRIPT_DIR/../validators/fstab_validator.sh"

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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
    
    # Charger la config si elle existe
    if [[ -f "/etc/fstab-guardian.conf" ]]; then
        # shellcheck source=/etc/fstab-guardian.conf
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
    echo "Boot recovery: $BOOT_RECOVERY_ENABLED"
    echo "Recovery log: $RECOVERY_LOG"
    
    if [[ -f "/etc/fstab-guardian.conf" ]]; then
        echo -e "\n📄 Config file: /etc/fstab-guardian.conf"
    else
        echo -e "\n📄 Using default settings (no config file found)"
    fi
}

edit_config() {
    local config_file="/etc/fstab-guardian.conf"
    
    echo -e "${YELLOW}⚙️  Editing configuration...${NC}"
    
    # Créer le fichier avec des valeurs par défaut si inexistant
    if [[ ! -f "$config_file" ]]; then
        echo "📁 Creating default config file..."
        sudo tee "$config_file" > /dev/null << 'EOF'
# fstab-guardian configuration file

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
    fi
    
    # Éditer avec l'éditeur configuré
    sudo "$EDITOR" "$config_file"
    
    echo -e "${GREEN}✅ Configuration updated!${NC}"
}

validate_fstab_file() {
    local fstab_file="${1:-/etc/fstab}"
    
    echo -e "${YELLOW}🔍 Validating: $fstab_file${NC}"
    echo "----------------------------------------"
    echo "" # Ligne vide
    
    # Le validator gère l'affichage - on laisse stdout/stderr passer directement
    bash "$VALIDATOR" "$fstab_file"
    local exit_code=$?
    
    echo "" # Ligne vide après
    return $exit_code
}

backup_fstab() {
    local fstab_file="${1:-/etc/fstab}"
    local comment="${2:-}"
    local backup_dir="${BACKUP_DIR:-/etc/fstab-backups}"
    local timestamp
    timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_file="$backup_dir/fstab_$timestamp"
    
    echo -e "${YELLOW}💾 Creating backup of: $fstab_file${NC}"
    echo "----------------------------------------"
    
    # Vérifier que le fstab existe
    if [[ ! -f "$fstab_file" ]]; then
        echo -e "${RED}❌ File not found: $fstab_file${NC}"
        return 1
    fi
    
    # Créer le dossier de backup si nécessaire
    if [[ ! -d "$backup_dir" ]]; then
        echo "📁 Creating backup directory: $backup_dir"
        if ! sudo mkdir -p "$backup_dir"; then
            echo -e "${RED}❌ Failed to create backup directory${NC}"
            return 1
        fi
    fi
    
    # Créer la sauvegarde
    if sudo cp "$fstab_file" "$backup_file"; then
        echo -e "${GREEN}✅ Backup created: $backup_file${NC}"
        
        # Créer un fichier de métadonnées si commentaire fourni
        if [[ -n "$comment" ]]; then
            local meta_file="${backup_file}.meta"
            cat > "$meta_file" << EOF
# Backup metadata for $(basename "$backup_file")
# Created: $(date '+%Y-%m-%d %H:%M:%S')
# Original: $fstab_file
# Comment: $comment
EOF
            sudo chown "$(stat -c '%U:%G' "$backup_file")" "$meta_file" 2>/dev/null || true
        fi
        
        # Afficher les infos du backup
        echo "📊 Backup info:"
        echo "  - Original: $fstab_file"
        echo "  - Backup: $backup_file" 
        echo "  - Size: $(du -h "$backup_file" | cut -f1)"
        echo "  - Lines: $(wc -l < "$backup_file")"
        [[ -n "$comment" ]] && echo "  - Comment: $comment"
        
        # Garder seulement les 10 derniers backups
        cleanup_old_backups "$backup_dir"
        
        return 0
    else
        echo -e "${RED}❌ Failed to create backup${NC}"
        return 1
    fi
}

cleanup_old_backups() {
    local backup_dir="$1"
    local keep_count=10
    
    echo "🧹 Cleaning old backups (keeping $keep_count most recent)..."
    
    # Compter les backups
    local backup_count
    backup_count=$(find "$backup_dir" -name "fstab_*" -type f 2>/dev/null | wc -l)
    
    if [[ $backup_count -gt $keep_count ]]; then
        # Supprimer les plus anciens
        find "$backup_dir" -name "fstab_*" -type f -printf '%T@ %p\n' 2>/dev/null | \
        sort -n | \
        head -n -$keep_count | \
        cut -d' ' -f2- | \
        sudo xargs rm -f
        
        echo "🗑️  Removed $((backup_count - keep_count)) old backups"
    fi
}

list_backups() {
    local backup_dir="${BACKUP_DIR:-/etc/fstab-backups}"
    
    echo -e "${YELLOW}📋 Available backups:${NC}"
    echo "----------------------------------------"
    
    # Vérifier si le dossier existe et contient des backups
    if [[ ! -d "$backup_dir" ]] || ! find "$backup_dir" -name "fstab_*" -type f -print -quit 2>/dev/null | grep -q .; then
        echo "No backups found."
        return 0
    fi
    
    # Lister les backups triés par date (plus récent en premier)
    find "$backup_dir" -name "fstab_*" -type f -printf '%TY-%Tm-%Td %TH:%TM  %s bytes  %p\n' 2>/dev/null | \
    sort -r | while IFS= read -r line; do
        backup_file=$(echo "$line" | awk '{print $NF}')
        meta_file="${backup_file}.meta"
        
        # Afficher la ligne de base
        echo "$line"
        
        # Ajouter le commentaire s'il existe
        if [[ -f "$meta_file" ]]; then
            comment=$(grep "^# Comment:" "$meta_file" 2>/dev/null | sed 's/^# Comment: //')
            if [[ -n "$comment" ]]; then
                echo "                           💬 $comment"
            fi
        fi
    done
}

edit_fstab() {
    local fstab_file="${1:-/etc/fstab}"
    local editor="${EDITOR:-nano}"
    
    echo -e "${YELLOW}✏️  Safe editing: $fstab_file${NC}"
    echo "----------------------------------------"
    
    # Vérifier que le fichier existe
    if [[ ! -f "$fstab_file" ]]; then
        echo -e "${RED}❌ File not found: $fstab_file${NC}"
        return 1
    fi
    
    # 1. Créer un backup automatique
    echo "🔄 Step 1: Creating automatic backup..."
    if ! backup_fstab "$fstab_file"; then
        echo -e "${RED}❌ Backup failed! Aborting edit for safety.${NC}"
        return 1
    fi
    
    # 2. Valider le fichier actuel
    echo -e "\n🔍 Step 2: Validating current file..."
    if ! bash "$VALIDATOR" "$fstab_file" > /dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  Current file has validation issues (proceeding anyway)${NC}"
        echo -e "${YELLOW}   Run 'fstab-guardian validate' to see details${NC}"
    else
        echo -e "${GREEN}✅ Current file is valid${NC}"
    fi
    
    # 3. Créer une copie temporaire pour l'édition
    local temp_file
    temp_file=$(mktemp)
    cp "$fstab_file" "$temp_file"
    
    echo -e "\n📝 Step 3: Opening editor ($editor)..."
    echo "💡 Tip: Make your changes and save. Validation will happen automatically."
    read -p "Press Enter to continue..." -r
    
    # 4. Ouvrir l'éditeur
    if ! $editor "$temp_file"; then
        echo -e "${RED}❌ Editor exited with error${NC}"
        rm -f "$temp_file"
        return 1
    fi
    
    # 5. Valider les modifications
    echo -e "\n🔍 Step 4: Validating your changes..."
    if bash "$VALIDATOR" "$temp_file"; then
        echo -e "\n${GREEN}✅ Validation passed!${NC}"
        
        # 6. Appliquer les changements
        echo -e "\n💾 Step 5: Applying changes..."
        if sudo cp "$temp_file" "$fstab_file"; then
            echo -e "${GREEN}✅ Changes applied successfully!${NC}"
            
            # 7. Test final
            echo -e "\n🧪 Step 6: Final verification..."
            if sudo mount -a 2>/dev/null; then
                echo -e "${GREEN}✅ Mount test passed! Your fstab is ready.${NC}"
            else
                echo -e "${YELLOW}⚠️  Mount test had issues, but file is syntactically valid.${NC}"
                echo -e "${YELLOW}   You may want to check your mount points manually.${NC}"
            fi
        else
            echo -e "${RED}❌ Failed to apply changes!${NC}"
            rm -f "$temp_file"
            return 1
        fi
    else
        echo -e "${RED}❌ Validation failed!${NC}"
        handle_validation_failure "$fstab_file" "$temp_file"
    fi
    
    rm -f "$temp_file"
}

handle_validation_failure() {
    local original_file="$1"
    local temp_file="$2"
    local backup_dir="${BACKUP_DIR:-/etc/fstab-backups}"
    
    echo -e "\n${YELLOW}🤔 What would you like to do?${NC}"
    echo "1) Re-edit the file (fix the errors)"
    echo "2) Restore from latest backup (discard changes)"
    echo "3) Show differences between original and your changes"
    echo "4) Exit without saving (discard changes)"
    
    read -p "Choose an option (1-4): " -r choice
    
    case $choice in
        1)
            echo -e "\n${YELLOW}📝 Re-opening editor...${NC}"
            edit_fstab "$original_file"
            ;;
        2)
            echo -e "\n${YELLOW}🔄 Restoring from backup...${NC}"
            local latest_backup
            latest_backup=$(find "$backup_dir" -name "fstab_*" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
            if [[ -n "$latest_backup" ]] && sudo cp "$latest_backup" "$original_file"; then
                echo -e "${GREEN}✅ Restored from: $latest_backup${NC}"
            else
                echo -e "${RED}❌ Failed to restore from backup${NC}"
            fi
            ;;
        3)
            echo -e "\n${YELLOW}📊 Differences (- original, + your changes):${NC}"
            diff -u "$original_file" "$temp_file" || true
            handle_validation_failure "$original_file" "$temp_file"
            ;;
        4)
            echo -e "${YELLOW}👋 Exiting without saving changes.${NC}"
            ;;
        *)
            echo -e "${RED}❌ Invalid choice${NC}"
            handle_validation_failure "$original_file" "$temp_file"
            ;;
    esac
}

show_status() {
    echo -e "${YELLOW}📊 fstab-guardian System Status${NC}"
    echo "========================================"
    
    # 1. État du fstab actuel
    echo -e "\n🔍 Current fstab status:"
    local fstab_file="/etc/fstab"
    if bash "$VALIDATOR" "$fstab_file" > /dev/null 2>&1; then
        echo -e "   ${GREEN}✅ Valid${NC} - $fstab_file"
    else
        echo -e "   ${RED}❌ Has issues${NC} - $fstab_file"
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
    echo -e "\n🛡️  Boot recovery status:"
    if check_boot_recovery_installed; then
        echo -e "   ${GREEN}✅ Installed and active${NC}"
        
        # Logs de recovery récents
        if [[ -f "$RECOVERY_LOG" ]]; then
            local recovery_count
            recovery_count=$(grep -c "recovery applied" "$RECOVERY_LOG" 2>/dev/null || echo "0")
            if [[ $recovery_count -gt 0 ]]; then
                echo -e "   ${YELLOW}⚠️  $recovery_count recoveries performed${NC}"
                echo "   📅 Last recovery: $(tail -1 "$RECOVERY_LOG" 2>/dev/null | head -c 50)..."
            else
                echo -e "   ${GREEN}✅ No recoveries needed${NC}"
            fi
        fi
    else
        echo -e "   ${RED}❌ Not installed${NC}"
        echo "   Run 'fstab-guardian install' to enable boot protection"
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
    if [[ ! -f "/etc/fstab-guardian.conf" ]]; then
        echo "   • Create config file: fstab-guardian config edit"
    fi
}

check_boot_recovery_installed() {
    # Check si le boot wrapper est installé
    if [[ -f "/boot/fstab-guardian-wrapper.sh" ]] && grep -q "fstab-guardian-wrapper" /boot/cmdline.txt 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

install_system() {
    echo -e "${YELLOW}📦 Installing fstab-guardian system...${NC}"
    echo "========================================"
    
    # 1. Créer les dossiers nécessaires
    echo "📁 Creating directories..."
    sudo mkdir -p "$BACKUP_DIR"
    sudo mkdir -p "$(dirname "$RECOVERY_LOG")"
    
    # 2. Créer la config par défaut
    create_default_config
    
    # 3. Copier les scripts dans /usr/local/bin
    echo "📋 Installing CLI..."
    sudo cp "$SCRIPT_DIR/../cli/fstab-guardian" "/usr/local/bin/"
    sudo chmod +x "/usr/local/bin/fstab-guardian"
    
    # 4. Créer un backup initial
    echo "💾 Creating initial backup..."
    backup_fstab
    
    echo -e "${GREEN}✅ Installation complete!${NC}"
    echo ""
    echo "Next steps:"
    echo "• Test the CLI: fstab-guardian status"
    echo "• Enable boot protection: fstab-guardian install-boot-guard"
    echo "• Configure: fstab-guardian config edit"
}

create_default_config() {
    if [[ ! -f "/etc/fstab-guardian.conf" ]]; then
        echo "⚙️  Creating default configuration..."
        sudo tee "/etc/fstab-guardian.conf" > /dev/null << EOF
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
    fi
}

restore_backup() {
    local backup_file="$1"
    local target="${2:-/etc/fstab}"
    
    if [[ ! -f "$backup_file" ]]; then
        echo -e "${RED}❌ Backup file not found: $backup_file${NC}"
        return 1
    fi
    
    # Valider le backup avant restauration
    if ! bash "$VALIDATOR" "$backup_file"; then
        echo -e "${YELLOW}⚠️  Warning: Backup file has validation issues${NC}"
        read -p "Continue anyway? (y/N): " -r
        [[ ! $REPLY =~ ^[Yy]$ ]] && return 1
    fi
    
    # Créer un backup du fichier actuel avant restauration
    backup_fstab "$target"
    
    if sudo cp "$backup_file" "$target"; then
        echo -e "${GREEN}✅ Restored from backup: $backup_file${NC}"
        return 0
    else
        echo -e "${RED}❌ Failed to restore backup${NC}"
        return 1
    fi
}

test_mounts() {
    local fstab_file="${1:-/etc/fstab}"
    echo -e "${YELLOW}🧪 Testing mount operations...${NC}"
    
    # Avertissement si fichier différent de /etc/fstab
    if [[ "$fstab_file" != "/etc/fstab" ]]; then
        echo -e "${YELLOW}⚠️  Warning: mount -a always uses /etc/fstab, not $fstab_file${NC}"
        echo -e "${YELLOW}   This test will check your current system fstab, not the specified file.${NC}"
        read -p "Continue with mount test on /etc/fstab? (y/N): " -r
        [[ ! $REPLY =~ ^[Yy]$ ]] && return 0
        echo ""
    fi
    
    # Test en mode dry-run d'abord
    if sudo mount -a --fake -v 2>/dev/null; then
        echo -e "${GREEN}✅ Dry-run test passed${NC}"
        
        read -p "Perform actual mount test? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Running mount -a...${NC}"
            sudo mount -a 2>&1 | while read -r line; do
                echo "   $line"
            done
        fi
    else
        echo -e "${RED}❌ Dry-run test failed${NC}"
        return 1
    fi
}

restore_interactive() {
    local backup_dir="${BACKUP_DIR:-/etc/fstab-backups}"
    
    echo -e "${YELLOW}🔄 Interactive restore${NC}"
    echo "======================================="
    
    # Vérifier si des backups existent
    if [[ ! -d "$backup_dir" ]] || ! find "$backup_dir" -name "fstab_*" -type f -print -quit 2>/dev/null | grep -q .; then
        echo -e "${RED}❌ No backups found in $backup_dir${NC}"
        echo "Create a backup first: fstab-guardian backup"
        return 1
    fi
    
    # Lister les backups disponibles avec numéros
    echo "Available backups:"
    echo "==================="
    local i=1
    local -a backups=()
    local -a backup_names=()
    
    while IFS= read -r line; do
        backup_file=$(echo "$line" | awk '{print $NF}')
        backup_name=$(basename "$backup_file")
        backups[i]=$backup_file
        backup_names[i]=$backup_name
        
        # Afficher avec numéro
        printf "%2d. %s\n" "$i" "$line"
        
        # Ajouter commentaire s'il existe
        meta_file="${backup_file}.meta"
        if [[ -f "$meta_file" ]]; then
            comment=$(grep "^# Comment:" "$meta_file" 2>/dev/null | sed 's/^# Comment: //')
            if [[ -n "$comment" ]]; then
                printf "    💬 %s\n" "$comment"
            fi
        fi
        
        ((i++))
    done < <(find "$backup_dir" -name "fstab_*" -type f -printf '%TY-%Tm-%Td %TH:%TM  %s bytes  %p\n' 2>/dev/null | sort -r)
    
    local total_backups=$((i-1))
    
    echo ""
    echo -n "Select backup to restore [1-$total_backups, or 'q' to quit]: "
    read -r choice
    
    # Vérifier l'input
    if [[ "$choice" == "q" ]] || [[ "$choice" == "Q" ]]; then
        echo "Restore cancelled."
        return 0
    fi
    
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ "$choice" -lt 1 ]] || [[ "$choice" -gt "$total_backups" ]]; then
        echo -e "${RED}❌ Invalid selection: $choice${NC}"
        return 1
    fi
    
    # Confirmer la restauration
    selected_backup="${backups[$choice]}"
    selected_name="${backup_names[$choice]}"
    
    echo ""
    echo -e "${YELLOW}Selected backup: $selected_name${NC}"
    echo -n "This will replace /etc/fstab. Continue? [y/N]: "
    read -r confirm
    
    if [[ "$confirm" != "y" ]] && [[ "$confirm" != "Y" ]]; then
        echo "Restore cancelled."
        return 0
    fi
    
    # Effectuer la restauration
    restore_backup "$selected_backup"
}

compare_fstab() {
    local file1="${1:-/etc/fstab}"
    local file2="$2"
    
    echo -e "${YELLOW}📊 Comparing fstab files${NC}"
    echo "========================================="
    echo "File 1: $file1"
    echo "File 2: $file2"
    echo ""
    
    if diff -u --color=always "$file1" "$file2" 2>/dev/null; then
        echo -e "${GREEN}✅ Files are identical${NC}"
    fi
}

clean_old_backups() {
    local time_spec="$1"
    local backup_dir="${BACKUP_DIR:-/etc/fstab-backups}"
    
    echo -e "${YELLOW}🧹 Cleaning old backups${NC}"
    echo "======================================="
    
    # Vérifier si le dossier existe
    if [[ ! -d "$backup_dir" ]]; then
        echo -e "${YELLOW}⚠️  Backup directory not found: $backup_dir${NC}"
        return 0
    fi
    
    # Convertir la spécification de temps en format find
    local find_option=""
    local find_time=""
    if [[ "$time_spec" =~ ^([0-9]+)d$ ]]; then
        local days="${BASH_REMATCH[1]}"
        find_option="-mtime"
        find_time="+$days"
        echo "Looking for backups older than $days days..."
    elif [[ "$time_spec" =~ ^([0-9]+)h$ ]]; then
        local hours="${BASH_REMATCH[1]}"
        find_option="-mmin"
        find_time="+$(($hours * 60))"
        echo "Looking for backups older than $hours hours..."
    elif [[ "$time_spec" =~ ^([0-9]+)m$ ]]; then
        local minutes="${BASH_REMATCH[1]}"
        find_option="-mmin"
        find_time="+$minutes"
        echo "Looking for backups older than $minutes minutes..."
    else
        echo -e "${RED}❌ Invalid time format: $time_spec${NC}"
        echo "Valid formats: 30d (days), 24h (hours), 60m (minutes)"
        return 1
    fi
    
    # Rechercher les fichiers anciens
    local old_backups=()
    local old_metas=()
    
    while IFS= read -r -d '' file; do
        old_backups+=("$file")
        # Ajouter le fichier meta associé s'il existe
        if [[ -f "${file}.meta" ]]; then
            old_metas+=("${file}.meta")
        fi
    done < <(find "$backup_dir" -name "fstab_*" -type f "$find_option" "$find_time" -print0 2>/dev/null)
    
    local total_files=$((${#old_backups[@]} + ${#old_metas[@]}))
    
    if [[ $total_files -eq 0 ]]; then
        echo -e "${GREEN}✅ No old backups found${NC}"
        return 0
    fi
    
    # Afficher les fichiers qui seront supprimés
    echo ""
    echo "Files to be deleted:"
    echo "==================="
    for backup in "${old_backups[@]}"; do
        local file_date=$(date -r "$backup" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "unknown")
        echo "  📄 $(basename "$backup") ($file_date)"
        
        if [[ -f "${backup}.meta" ]]; then
            echo "  📄 $(basename "${backup}.meta") (metadata)"
        fi
    done
    
    echo ""
    echo -e "${YELLOW}⚠️  This will delete $total_files file(s)${NC}"
    echo -n "Continue? [y/N]: "
    read -r confirm
    
    if [[ "$confirm" != "y" ]] && [[ "$confirm" != "Y" ]]; then
        echo "Cleanup cancelled."
        return 0
    fi
    
    # Supprimer les fichiers
    local deleted=0
    for backup in "${old_backups[@]}"; do
        if rm -f "$backup"; then
            echo "🗑️  Deleted: $(basename "$backup")"
            ((deleted++))
        else
            echo -e "${RED}❌ Failed to delete: $(basename "$backup")${NC}"
        fi
    done
    
    for meta in "${old_metas[@]}"; do
        if rm -f "$meta"; then
            echo "🗑️  Deleted: $(basename "$meta")"
            ((deleted++))
        else
            echo -e "${RED}❌ Failed to delete: $(basename "$meta")${NC}"
        fi
    done
    
    echo ""
    echo -e "${GREEN}✅ Cleanup complete: $deleted/$total_files files deleted${NC}"
    
    # Afficher le statut final
    local remaining=$(find "$backup_dir" -name "fstab_*" -type f 2>/dev/null | wc -l)
    echo "📊 Remaining backups: $remaining"
}

load_config

case "${1:-}" in
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
    "edit")
        edit_fstab "${2:-}"
        ;;
    "help"|"--help"|"-h"|"")
        show_help
        ;;
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
    "restore")
        if [[ "${2:-}" == "--from" ]] && [[ -n "${3:-}" ]]; then
            restore_backup "$3"
        else
            restore_interactive
        fi
        ;;
    "compare")
        if [[ -n "${2:-}" ]] && [[ -n "${3:-}" ]]; then
            compare_fstab "$2" "$3"
        else
            echo -e "${RED}❌ Usage: fstab-guardian compare <file1> <file2>${NC}"
            echo "Example: fstab-guardian compare /etc/fstab /tmp/test-fstab"
            exit 1
        fi
        ;;
    "install")
        install_system
        ;;
    "install-boot-recovery")
        sudo "$SCRIPT_DIR/../boot/install-recovery-hooks.sh" install
        ;;
    "test-boot-recovery")
        echo -e "${YELLOW}🧪 Testing boot recovery...${NC}"
        sudo "$SCRIPT_DIR/../boot/fstab-recovery.sh"
        ;;
    "boot-logs")
        if [[ -f "$RECOVERY_LOG" ]]; then
            echo -e "${YELLOW}📄 Boot recovery logs:${NC}"
            echo "=============================="
            tail -20 "$RECOVERY_LOG"
        else
            echo -e "${YELLOW}⚠️  No recovery logs found at $RECOVERY_LOG${NC}"
        fi
        ;;
    *)
        echo -e "${RED}❌ Unknown command: $1${NC}"
        echo "Run 'fstab-guardian help' for usage information."
        exit 1
        ;;
esac