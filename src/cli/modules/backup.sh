#!/bin/bash
# fstab-guardian backup module
# Gestion des backups, restore et nettoyage

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
    local keep_count="${BACKUP_KEEP_COUNT:-10}"
    
    # Compter les backups existants
    local backup_count
    backup_count=$(find "$backup_dir" -name "fstab_*" -type f 2>/dev/null | wc -l)
    
    if [[ $backup_count -gt $keep_count ]]; then
        local to_delete=$((backup_count - keep_count))
        echo "🧹 Cleaning up $to_delete old backup(s)..."
        
        # Supprimer les plus anciens backups (et leurs métadonnées)
        find "$backup_dir" -name "fstab_*" -type f -printf '%T@ %p\n' 2>/dev/null | \
        sort -n | \
        head -n "$to_delete" | \
        while read -r _ backup_file; do
            rm -f "$backup_file"
            rm -f "${backup_file}.meta" 2>/dev/null || true
            echo "  🗑️  Removed: $(basename "$backup_file")"
        done
        
        echo "📊 Kept $keep_count most recent backups"
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
        echo -e "${RED}❌ Failed to restore from backup${NC}"
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