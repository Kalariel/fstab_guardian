#!/bin/bash
set -euo pipefail

validate_fstab() {
    local fstab_file="$1"
    echo "DEBUG: Début de la validation du fichier $fstab_file"

    # Vérifier que le fichier existe et est lisible
    if [ ! -f "$fstab_file" ]; then
        echo "ERREUR: Le fichier $fstab_file n'existe pas."
        return 1
    fi

    if [ ! -r "$fstab_file" ]; then
        echo "ERREUR: Le fichier $fstab_file n'est pas lisible."
        return 1
    fi

    # Afficher le contenu du fichier
    echo "DEBUG: Contenu du fichier :"
    cat "$fstab_file"

    declare -A mount_points
    local line_num=1
    local errors=()

    while read -r line; do        
        echo "DEBUG: Ligne $line_num : '$line'"

        # Ignorer les commentaires et les lignes vides
        if [[ "$line" =~ ^[[:space:]]*# ]]; then
            echo "DEBUG: Ligne $line_num ignorée (commentaire)"
            continue
        fi
        if [[ -z "${line// }" ]]; then
            echo "DEBUG: Ligne $line_num ignorée (vide)"
            continue
        fi

        # Découper la ligne en champs
        IFS=' ' read -ra fields <<< "$line"
        echo "DEBUG: Champs découpés : ${#fields[@]} -> '${fields[*]}'"

        # Vérifier le nombre de champs
        if [[ ${#fields[@]} -ne 6 ]]; then
            echo "DEBUG: Ligne $line_num : Nombre de champs incorrect (${#fields[@]})"
            errors+=("Line $line_num: Expected 6 fields, got ${#fields[@]}")
            continue
        fi

        # Valider l'UUID
        if [[ "${fields[0]}" =~ ^UUID= ]]; then
            uuid="${fields[0]#UUID=}"
            echo "DEBUG: UUID détecté : '$uuid'"
            if ! [[ "$uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
                echo "DEBUG: UUID invalide : '$uuid'"
                errors+=("Line $line_num: Invalid UUID format: $uuid")
            fi
        else
            echo "DEBUG: Pas de UUID dans le premier champ : '${fields[0]}'"
        fi

        # Valider le point de montage
        mount_point="${fields[1]}"
        
        echo "DEBUG: Point de montage : '$mount_point'"
        if [[ ! "$mount_point" =~ ^/ ]] && [[ "$mount_point" != "none" ]]; then
            echo "DEBUG: Point de montage non absolu : '$mount_point'"
            errors+=("Line $line_num: Mount point must be absolute path: $mount_point")
        fi
        if [[ ! -d "$mount_point" ]] && [[ "$mount_point" != "none" ]]; then
            errors+=("Line $line_num: Mount point does not exist: $mount_point")
        fi
        if [[ -n "${mount_points[$mount_point]+isset}" ]]; then
            errors+=("Line $line_num: Duplicate mount point: $mount_point")
        else
            mount_points[$mount_point]=1
        fi

        # Valider le type de filesystem
        fs_type="${fields[2]}"
        echo "DEBUG: Type de filesystem : '$fs_type'"
        valid_fs_types=("ext2" "ext3" "ext4" "vfat" "ntfs" "swap" "proc" "sysfs" "tmpfs")
        if [[ ! " ${valid_fs_types[*]} " =~ $fs_type ]]; then
            echo "DEBUG: Type de filesystem inconnu : '$fs_type'"
            errors+=("Line $line_num: Unknown filesystem type: $fs_type")
        fi
        ((line_num++))
    done < "$fstab_file"

    echo "DEBUG: Nombre d'erreurs trouvées : ${#errors[@]}"
    if [[ ${#errors[@]} -eq 0 ]]; then
        echo "DEBUG: Aucune erreur, retour 0"
        return 0
    else
        printf '%s\n' "${errors[@]}"
        echo "DEBUG: Retour 1 (erreur)"
        return 1
    fi
}

validate_fstab "$1"
