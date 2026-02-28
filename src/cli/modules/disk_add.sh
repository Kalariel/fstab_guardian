#!/bin/bash
# fstab-guardian disk-add module
# Ajout interactif de disques/partitions au fstab

# Retourne les devices non présents dans fstab (un par ligne: NAME|UUID|FSTYPE|SIZE|LABEL|MOUNTPOINT)
_get_devices_not_in_fstab() {
    local fstab_file="${1:-/etc/fstab}"

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        local name uuid fstype size label mountpoint
        name=$(echo "$line"       | grep -o 'NAME="[^"]*"'       | cut -d'"' -f2)
        uuid=$(echo "$line"       | grep -o 'UUID="[^"]*"'       | cut -d'"' -f2)
        fstype=$(echo "$line"     | grep -o 'FSTYPE="[^"]*"'     | cut -d'"' -f2)
        size=$(echo "$line"       | grep -o 'SIZE="[^"]*"'       | cut -d'"' -f2)
        label=$(echo "$line"      | grep -o 'LABEL="[^"]*"'      | cut -d'"' -f2)
        mountpoint=$(echo "$line" | grep -o 'MOUNTPOINT="[^"]*"' | cut -d'"' -f2)

        # Ignorer si pas d'UUID ou de fstype
        [[ -z "$uuid" || -z "$fstype" ]] && continue

        # Ignorer les types conteneurs/chiffrés
        case "$fstype" in
            LVM2_member|linux_raid_member|crypto_LUKS) continue ;;
        esac

        # Ignorer si l'UUID est déjà dans fstab
        grep -q "UUID=$uuid" "$fstab_file" 2>/dev/null && continue

        echo "${name}|${uuid}|${fstype}|${size}|${label}|${mountpoint}"
    done < <(lsblk -P -o NAME,UUID,FSTYPE,SIZE,LABEL,MOUNTPOINT -p 2>/dev/null)
}

# Affiche la liste des disques disponibles (non encore dans fstab)
list_available_disks() {
    local fstab_file="${1:-/etc/fstab}"

    echo -e "${YELLOW}💿 Disques disponibles (non présents dans fstab):${NC}"
    echo "============================================================="

    if [[ ! -f "$fstab_file" ]]; then
        echo -e "${RED}❌ Fichier introuvable: $fstab_file${NC}"
        return 1
    fi

    local devices=()
    while IFS= read -r dev; do
        devices+=("$dev")
    done < <(_get_devices_not_in_fstab "$fstab_file")

    if [[ ${#devices[@]} -eq 0 ]]; then
        echo -e "   ${GREEN}✅ Tous les disques détectés sont déjà dans fstab${NC}"
        return 0
    fi

    printf "  %-4s %-22s %-38s %-8s %-8s %-15s %s\n" \
        "#" "DEVICE" "UUID" "TYPE" "SIZE" "LABEL" "MOUNTPOINT"
    echo "  $(printf '%.s─' {1..105})"

    local idx=1
    for dev in "${devices[@]}"; do
        IFS='|' read -r name uuid fstype size label mountpoint <<< "$dev"
        local display_label="${label:-(no label)}"
        local display_mp="${mountpoint:-(not mounted)}"
        printf "  %-4s %-22s %-38s %-8s %-8s %-15s %s\n" \
            "[$idx]" "$name" "$uuid" "$fstype" "$size" "$display_label" "$display_mp"
        ((idx++))
    done
}

# Ajoute une partition swap au fstab
_add_swap_entry() {
    local fstab_file="$1"
    local uuid="$2"
    local dev="$3"

    echo ""
    local default_name="swap-${dev##*/}"
    read -p "Nom convivial [$default_name]: " -r friendly_name
    friendly_name="${friendly_name:-$default_name}"

    local fstab_comment="# $friendly_name - Added by fstab-guardian $(date '+%Y-%m-%d %H:%M')"
    local fstab_entry="UUID=$uuid none swap sw 0 0"

    echo ""
    echo -e "${YELLOW}📋 Aperçu de l'entrée fstab:${NC}"
    echo "----------------------------------------"
    echo "$fstab_comment"
    echo "$fstab_entry"
    echo "----------------------------------------"
    echo ""

    read -p "Ajouter cette entrée dans $fstab_file ? [y/N]: " -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Annulé."
        return 0
    fi

    echo ""
    echo "💾 Création du backup..."
    backup_fstab "$fstab_file"

    local temp_file
    temp_file=$(mktemp --suffix=.fstab)
    cp "$fstab_file" "$temp_file"

    { echo ""; echo "$fstab_comment"; echo "$fstab_entry"; } >> "$temp_file"

    echo ""
    echo "🔍 Validation du fstab modifié..."
    if bash "$VALIDATOR" "$temp_file"; then
        if sudo cp "$temp_file" "$fstab_file"; then
            echo ""
            echo -e "${GREEN}🎉 Partition swap '$friendly_name' ajoutée avec succès !${NC}"
            echo ""
            echo -e "${YELLOW}💡 Pour activer maintenant:${NC}"
            echo "   sudo swapon -a"
        else
            echo -e "${RED}❌ Impossible d'écrire dans $fstab_file${NC}"
        fi
    else
        echo -e "${RED}❌ Validation échouée ! Entrée non ajoutée.${NC}"
        handle_validation_failure "$temp_file"
    fi

    rm -f "$temp_file"
}

# Commande principale: ajout interactif d'un disque au fstab
add_disk_interactive() {
    local fstab_file="${1:-/etc/fstab}"

    echo -e "${YELLOW}➕ Ajout d'un disque au fstab: $fstab_file${NC}"
    echo "============================================================="

    if [[ ! -f "$fstab_file" ]]; then
        echo -e "${RED}❌ Fichier introuvable: $fstab_file${NC}"
        return 1
    fi

    # Détection des disques disponibles
    echo "🔍 Scan des périphériques bloc..."
    echo ""

    local devices=()
    while IFS= read -r dev; do
        devices+=("$dev")
    done < <(_get_devices_not_in_fstab "$fstab_file")

    if [[ ${#devices[@]} -eq 0 ]]; then
        echo -e "${GREEN}✅ Tous les disques détectés sont déjà dans fstab${NC}"
        echo ""
        echo "Pour voir le contenu actuel: fstab-guardian validate"
        echo "Pour éditer manuellement:    fstab-guardian edit"
        return 0
    fi

    # Affichage du tableau des disques disponibles
    printf "  %-4s %-22s %-38s %-8s %-8s %-15s %s\n" \
        "#" "DEVICE" "UUID" "TYPE" "SIZE" "LABEL" "MOUNTPOINT"
    echo "  $(printf '%.s─' {1..105})"

    local idx=1
    for dev in "${devices[@]}"; do
        IFS='|' read -r name uuid fstype size label mountpoint <<< "$dev"
        local display_label="${label:-(no label)}"
        local display_mp="${mountpoint:-(not mounted)}"
        printf "  %-4s %-22s %-38s %-8s %-8s %-15s %s\n" \
            "[$idx]" "$name" "$uuid" "$fstype" "$size" "$display_label" "$display_mp"
        ((idx++))
    done

    echo ""
    read -p "Sélectionner un disque [1-${#devices[@]}] ou (q)uitter: " -r choice

    [[ "$choice" =~ ^[qQ]$ ]] && { echo "Annulé."; return 0; }

    if ! [[ "$choice" =~ ^[0-9]+$ ]] || [[ $choice -lt 1 || $choice -gt ${#devices[@]} ]]; then
        echo -e "${RED}❌ Sélection invalide${NC}"
        return 1
    fi

    local selected="${devices[$((choice-1))]}"
    IFS='|' read -r sel_name sel_uuid sel_fstype sel_size sel_label sel_mountpoint <<< "$selected"

    echo ""
    echo -e "${GREEN}Sélectionné:${NC} $sel_name"
    echo "   UUID  : $sel_uuid"
    echo "   Type  : $sel_fstype"
    echo "   Taille: $sel_size"
    [[ -n "$sel_label" ]] && echo "   Label : $sel_label"
    [[ -n "$sel_mountpoint" ]] && echo "   Monté actuellement sur: $sel_mountpoint"

    # Cas particulier: partition swap
    if [[ "$sel_fstype" == "swap" ]]; then
        _add_swap_entry "$fstab_file" "$sel_uuid" "$sel_name"
        return $?
    fi

    # === Partition classique ===
    echo ""
    echo -e "${YELLOW}💡 Un nom convivial sera ajouté en commentaire dans fstab${NC}"

    local default_name="${sel_label:-${sel_name##*/}}"
    read -p "Nom convivial / description [$default_name]: " -r friendly_name
    friendly_name="${friendly_name:-$default_name}"

    # Point de montage (sanitize le nom pour en faire un chemin valide)
    local sanitized_name
    sanitized_name=$(echo "$friendly_name" \
        | tr '[:upper:]' '[:lower:]' \
        | tr ' ' '_' \
        | tr -cd 'a-z0-9_-')
    local default_mp="/mnt/$sanitized_name"

    read -p "Point de montage [$default_mp]: " -r mount_point
    mount_point="${mount_point:-$default_mp}"

    # Options de montage selon le type de filesystem
    local default_opts
    case "$sel_fstype" in
        ntfs|ntfs-3g) default_opts="defaults,nofail,uid=1000,gid=1000" ;;
        vfat|fat32)   default_opts="defaults,nofail,uid=1000,gid=1000,umask=022" ;;
        exfat)        default_opts="defaults,nofail,uid=1000,gid=1000" ;;
        *)            default_opts="defaults,nofail" ;;
    esac

    read -p "Options de montage [$default_opts]: " -r mount_opts
    mount_opts="${mount_opts:-$default_opts}"

    # dump / pass
    local dump="0"
    local pass="0"
    if [[ "$sel_fstype" =~ ^ext[234]$|^xfs$|^btrfs$ ]]; then
        pass="2"
    fi

    # Identifiant : UUID ou LABEL si disponible
    local device_id="UUID=$sel_uuid"
    if [[ -n "$sel_label" ]]; then
        echo ""
        echo "Identifier ce disque dans fstab par :"
        echo "  [1] UUID=$sel_uuid  (recommandé, toujours stable)"
        echo "  [2] LABEL=$sel_label  (lisible, mais modifiable)"
        read -p "Choix [1]: " -r id_choice
        if [[ "${id_choice:-1}" == "2" ]]; then
            device_id="LABEL=$sel_label"
        fi
    fi

    # Construction de l'entrée fstab
    local fstab_comment="# $friendly_name - Added by fstab-guardian $(date '+%Y-%m-%d %H:%M')"
    local fstab_entry="$device_id $mount_point $sel_fstype $mount_opts $dump $pass"

    # Aperçu
    echo ""
    echo -e "${YELLOW}📋 Aperçu de l'entrée fstab:${NC}"
    echo "----------------------------------------"
    echo "$fstab_comment"
    echo "$fstab_entry"
    echo "----------------------------------------"
    echo ""

    read -p "Ajouter cette entrée dans $fstab_file ? [y/N]: " -r confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Annulé."
        return 0
    fi

    # Créer le point de montage si nécessaire
    if [[ ! -d "$mount_point" ]]; then
        read -p "Le point de montage '$mount_point' n'existe pas. Le créer ? [Y/n]: " -r create_mp
        if [[ "${create_mp:-Y}" =~ ^[Yy]$ ]]; then
            if sudo mkdir -p "$mount_point"; then
                echo -e "${GREEN}✅ Créé: $mount_point${NC}"
            else
                echo -e "${RED}❌ Impossible de créer le point de montage${NC}"
                return 1
            fi
        fi
    fi

    # Backup avant modification
    echo ""
    echo "💾 Création du backup..."
    backup_fstab "$fstab_file"

    # Écriture dans un fichier temporaire puis validation
    local temp_file
    temp_file=$(mktemp --suffix=.fstab)
    cp "$fstab_file" "$temp_file"

    { echo ""; echo "$fstab_comment"; echo "$fstab_entry"; } >> "$temp_file"

    echo ""
    echo "🔍 Validation du fstab modifié..."

    if bash "$VALIDATOR" "$temp_file"; then
        if sudo cp "$temp_file" "$fstab_file"; then
            echo ""
            echo -e "${GREEN}🎉 '$friendly_name' ajouté avec succès au fstab !${NC}"
            echo ""
            echo "   Entrée : $fstab_entry"
            echo ""
            echo -e "${YELLOW}💡 Pour monter maintenant:${NC}"
            echo "   sudo mount $mount_point"
            echo "   # ou monter tout:"
            echo "   sudo mount -a"
        else
            echo -e "${RED}❌ Impossible d'écrire dans $fstab_file${NC}"
        fi
    else
        echo -e "${RED}❌ Validation échouée ! Entrée non ajoutée.${NC}"
        handle_validation_failure "$temp_file"
    fi

    rm -f "$temp_file"
}
