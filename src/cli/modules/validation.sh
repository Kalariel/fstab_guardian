#!/bin/bash
# fstab-guardian validation module
# Validation fstab, tests de montage, comparaisons

validate_fstab_file() {
    local fstab_file="${1:-/etc/fstab}"
    local validator="$VALIDATOR"
    
    # Validation avec le script dédié
    if bash "$validator" "$fstab_file"; then
        echo -e "${GREEN}✅ Validation passed${NC}"
        return 0
    else
        local exit_code=$?
        echo -e "${RED}❌ Validation failed${NC}"
        return $exit_code
    fi
}

handle_validation_failure() {
    local fstab_file="$1"
    
    echo ""
    echo -e "${RED}🚨 VALIDATION FAILED!${NC}"
    echo "====================================="
    echo "Your fstab has critical errors that could prevent your system from booting."
    echo ""
    echo -e "${YELLOW}What would you like to do?${NC}"
    echo "1. 🔧 Edit and fix the issues"
    echo "2. 🔄 Restore from backup"
    echo "3. ❌ Abort (leave fstab as-is)"
    echo ""
    
    while true; do
        read -p "Choice [1-3]: " choice
        case "$choice" in
            1)
                echo "🔧 Launching editor..."
                edit_fstab "$fstab_file"
                break
                ;;
            2)
                echo "🔄 Looking for available backups..."
                local backup_dir="${BACKUP_DIR:-/etc/fstab-backups}"
                if [[ -d "$backup_dir" ]] && find "$backup_dir" -name "fstab_*" -type f -print -quit 2>/dev/null | grep -q .; then
                    local latest_backup
                    latest_backup=$(find "$backup_dir" -name "fstab_*" -type f -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2-)
                    echo "📁 Found latest backup: $(basename "$latest_backup")"
                    echo "   Created: $(date -r "$latest_backup" '+%Y-%m-%d %H:%M:%S')"
                    echo ""
                    read -p "Restore this backup? (y/N): " -r
                    if [[ $REPLY =~ ^[Yy]$ ]]; then
                        if sudo cp "$latest_backup" "$fstab_file"; then
                            echo -e "${GREEN}✅ Restored from: $latest_backup${NC}"
                        else
                            echo -e "${RED}❌ Failed to restore from backup${NC}"
                        fi
                    fi
                else
                    echo -e "${YELLOW}⚠️  No backups found${NC}"
                    echo "Create a backup first: fstab-guardian backup"
                fi
                break
                ;;
            3)
                echo "⚠️  Leaving fstab as-is. Please fix manually before rebooting!"
                return 1
                ;;
            *)
                echo "Please choose 1, 2, or 3"
                ;;
        esac
    done
}

test_mounts() {
    local fstab_file="${1:-/etc/fstab}"
    
    echo -e "${YELLOW}🧪 Testing mount operations (dry-run)${NC}"
    echo "=========================================="
    
    # Créer un dossier temporaire pour les tests
    local temp_dir
    temp_dir=$(mktemp -d)
    local test_log="$temp_dir/mount_test.log"
    
    echo "📝 Test log: $test_log"
    echo ""
    
    # Lire le fstab ligne par ligne et tester les montages
    local line_num=0
    local test_passed=0
    local test_failed=0
    
    while IFS= read -r line; do
        ((line_num++))
        
        # Ignorer les commentaires et lignes vides
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        # Parser les champs
        read -r device mountpoint fstype options dump pass <<< "$line"
        
        # Ignorer certains types de système de fichiers
        case "$fstype" in
            "swap"|"proc"|"sysfs"|"devpts"|"tmpfs"|"devtmpfs"|"cgroup"|"cgroup2"|"pstore"|"bpf"|"configfs"|"debugfs"|"tracefs"|"securityfs"|"fusectl"|"fuse.gvfsd-fuse")
                echo "⏭️  Line $line_num: Skipping $fstype ($mountpoint)"
                continue
                ;;
        esac
        
        printf "🧪 Line %2d: Testing %s -> %s (%s)..." "$line_num" "$device" "$mountpoint" "$fstype"
        
        # Test 1: Vérifier que le device existe (pour les devices locaux)
        local device_ok=false
        case "$device" in
            UUID=*)
                local uuid=${device#UUID=}
                if blkid -U "$uuid" >/dev/null 2>&1; then
                    device_ok=true
                else
                    echo " ❌ UUID not found" | tee -a "$test_log"
                    ((test_failed++))
                    continue
                fi
                ;;
            LABEL=*)
                local label=${device#LABEL=}
                if blkid -L "$label" >/dev/null 2>&1; then
                    device_ok=true
                else
                    echo " ❌ LABEL not found" | tee -a "$test_log"
                    ((test_failed++))
                    continue
                fi
                ;;
            /dev/*)
                if [[ -b "$device" ]]; then
                    device_ok=true
                else
                    echo " ❌ Device not found" | tee -a "$test_log"
                    ((test_failed++))
                    continue
                fi
                ;;
            */*)
                # Réseau (NFS, CIFS, etc.)
                echo " ⚠️  Network mount (not tested)" | tee -a "$test_log"
                continue
                ;;
            *)
                echo " ⚠️  Special device (not tested)" | tee -a "$test_log"
                continue
                ;;
        esac
        
        # Test 2: Vérifier que le point de montage existe ou peut être créé
        if [[ ! -d "$mountpoint" ]]; then
            echo " ❌ Mount point does not exist: $mountpoint" | tee -a "$test_log"
            ((test_failed++))
            continue
        fi
        
        # Test 3: Tester le montage en lecture seule (dry-run)
        local mount_opts="ro,noexec"
        if timeout 10s sudo mount -t "$fstype" -o "$mount_opts" "$device" "$temp_dir" 2>>"$test_log"; then
            sudo umount "$temp_dir" 2>/dev/null
            echo " ✅ OK" | tee -a "$test_log"
            ((test_passed++))
        else
            echo " ❌ Mount test failed" | tee -a "$test_log"
            ((test_failed++))
        fi
        
    done < "$fstab_file"
    
    # Résumé des tests
    echo ""
    echo "📊 Test Summary:"
    echo "================="
    echo -e "✅ Passed: ${GREEN}$test_passed${NC}"
    echo -e "❌ Failed: ${RED}$test_failed${NC}"
    
    # Nettoyage
    rm -rf "$temp_dir"
    
    if [[ $test_failed -eq 0 ]]; then
        echo -e "${GREEN}✅ All mount tests passed${NC}"
        return 0
    else
        echo -e "${RED}❌ Some mount tests failed${NC}"
        return 1
    fi
}

show_fstab() {
    local fstab_file="${1:-/etc/fstab}"
    local CYAN='\033[0;36m'
    local BOLD='\033[1m'
    local DIM='\033[2m'

    if [[ ! -f "$fstab_file" ]]; then
        echo -e "${RED}❌ Fichier introuvable: $fstab_file${NC}"
        return 1
    fi

    echo -e "${YELLOW}📄 $fstab_file${NC}  $(wc -l < "$fstab_file") lignes · $(stat -c%s "$fstab_file") octets · modifié le $(date -r "$fstab_file" '+%Y-%m-%d %H:%M')"
    echo "$(printf '%.s─' {1..70})"

    local line_num=0
    while IFS= read -r line; do
        line_num=$((line_num + 1))
        printf "${DIM}%3d${NC}  " "$line_num"

        if [[ "$line" =~ ^[[:space:]]*# ]]; then
            # Commentaire
            echo -e "${YELLOW}$line${NC}"
        elif [[ -z "${line// }" ]]; then
            # Ligne vide
            echo ""
        else
            # Entrée fstab : coloriser les champs
            local device mountpoint fstype options dump pass rest
            read -r device mountpoint fstype options dump pass rest <<< "$line"
            echo -e "${BOLD}${CYAN}${device}${NC}  ${mountpoint}  ${GREEN}${fstype}${NC}  ${DIM}${options} ${dump} ${pass}${NC}"
        fi
    done < "$fstab_file"

    echo "$(printf '%.s─' {1..70})"
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