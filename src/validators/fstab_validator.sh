#!/bin/bash
set -euo pipefail

# Configuration
DEBUG=${DEBUG:-false}

debug_log() {
    if [[ "$DEBUG" == "true" ]]; then
        echo "DEBUG: $*" >&2
    fi
}

warning_log() {
    echo "WARNING: $*" >&2
}

# Fonction pour ajouter un warning au tableau
add_warning() {
    warnings+=("$1")
}

info_log() {
    if [[ "$DEBUG" == "true" ]]; then
        echo "INFO: $*" >&2
    fi
}

# Fonction pour valider les spécifications de device et retourner errors + warnings
validate_device_spec() {
    local device_spec="$1"
    local line_num="$2"
    local -n error_ref=$3
    local -n warning_ref=$4

    case "$device_spec" in
        UUID=*)
            local uuid="${device_spec#UUID=}"
            debug_log "Validating UUID: '$uuid'"
            # UUID malformé peut causer des erreurs de parsing critiques
            if ! [[ "$uuid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]]; then
                error_ref+=("Line $line_num: Invalid UUID format: $uuid")
            else
                # UUID bien formé mais vérifier s'il existe
                if ! blkid | grep -q "UUID=\"$uuid\"" 2>/dev/null; then
                    warning_ref+=("Line $line_num: UUID not found in system: $uuid (mount will fail but system will boot)")
                fi
            fi
            ;;
        LABEL=*)
            local label="${device_spec#LABEL=}"
            debug_log "Validating LABEL: '$label'"
            if [[ -z "$label" ]]; then
                error_ref+=("Line $line_num: Empty label")
            else
                # LABEL bien formé mais vérifier s'il existe
                if ! blkid | grep -q "LABEL=\"$label\"" 2>/dev/null; then
                    warning_ref+=("Line $line_num: Label not found in system: $label (mount will fail but system will boot)")
                fi
            fi
            ;;
        /dev/*)
            debug_log "Validating device path: '$device_spec'"
            # Vérifier si le device existe
            if [[ ! -b "$device_spec" ]] && [[ ! -c "$device_spec" ]]; then
                warning_ref+=("Line $line_num: Block/character device not found: $device_spec (mount will fail but system will boot)")
            fi
            ;;
        tmpfs|proc|sysfs|devpts|devtmpfs)
            debug_log "Special filesystem: '$device_spec'"
            info_log "Line $line_num: Virtual filesystem detected: $device_spec"
            ;;
        //*)
            debug_log "Network path detected: '$device_spec'"
            info_log "Line $line_num: SMB/CIFS network path: $device_spec (requires network)"
            ;;
        *:*)
            debug_log "Network path detected (NFS-style): '$device_spec'"  
            info_log "Line $line_num: NFS network path: $device_spec (requires network)"
            ;;
        *)
            debug_log "Other device specification: '$device_spec'"
            warning_ref+=("Line $line_num: Unknown device format: $device_spec (may cause mount failure)")
            ;;
    esac
}

validate_mount_options() {
    local options="$1"
    local fs_type="$2"
    local line_num="$3"
    local errors=()

    debug_log "Validating mount options: '$options' for fs_type '$fs_type'"

    # Options inconnues ne font généralement pas planter le boot
    # mount les ignore simplement avec des warnings
    # Donc on fait juste du debug logging, pas d'erreurs

    debug_log "Mount options validation: options are generally ignored if unknown, no boot failure"

    # On pourrait ajouter ici une validation des options critiques si nécessaire
    # mais pour l'instant, les options inconnues ne font pas planter le boot

    printf '%s\n' "${errors[@]}"
}

validate_fstab() {
    local fstab_file="$1"
    debug_log "Starting validation of $fstab_file"

    # Vérifier que le fichier existe et est lisible
    if [[ ! -f "$fstab_file" ]]; then
        echo "ERREUR: Le fichier $fstab_file n'existe pas."
        return 1
    fi

    if [[ ! -r "$fstab_file" ]]; then
        echo "ERREUR: Le fichier $fstab_file n'est pas lisible."
        return 1
    fi

    debug_log "File content:"
    if [[ "$DEBUG" == "true" ]]; then
        cat "$fstab_file" >&2
    fi

    declare -A mount_points
    local line_num=1
    local errors=()
    local warnings=()

    while IFS= read -r line; do        
        debug_log "Line $line_num: '$line'"

        # Ignorer les commentaires et les lignes vides
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "${line// }" ]]; then
            debug_log "Line $line_num skipped (comment or empty)"
            ((line_num++))
            continue
        fi

        # Découper la ligne (supporter tabs et espaces multiples)
        read -ra fields <<< "$line"
        debug_log "Fields parsed: ${#fields[@]} -> '${fields[*]}'"

        # Les lignes fstab doivent avoir 4 à 6 champs
        if [[ ${#fields[@]} -lt 4 || ${#fields[@]} -gt 6 ]]; then
            errors+=("Line $line_num: Insufficient fields (expected 4-6, got ${#fields[@]})")
            ((line_num++))
            continue
        fi

        local device="${fields[0]}"
        local mount_point="${fields[1]}"
        local fs_type="${fields[2]}"
        local options="${fields[3]}"
        local dump="0"
        local pass="0"
        if [[ ${#fields[@]} -ge 5 ]]; then
            dump="${fields[4]}"
        fi
        if [[ ${#fields[@]} -ge 6 ]]; then
            pass="${fields[5]}"
        fi

        debug_log "Parsed: device='$device' mount='$mount_point' fs='$fs_type' opts='$options' dump='$dump' pass='$pass'"

        # Validation du device/UUID/LABEL
        validate_device_spec "$device" "$line_num" errors warnings

        # Validation du point de montage
        debug_log "Validating mount point: '$mount_point'"
        if [[ "$mount_point" != "none" ]] && [[ "$mount_point" != "swap" ]]; then
            if [[ ! "$mount_point" =~ ^/ ]]; then
                errors+=("Line $line_num: Mount point must be absolute path: $mount_point")
            else
                # Point de montage bien formé mais vérifier s'il existe
                if [[ ! -d "$mount_point" ]]; then
                    warnings+=("Line $line_num: Mount point directory does not exist: $mount_point (mount will fail but system will boot)")
                fi
            fi
        fi

        # Vérifier les points de montage dupliqués
        if [[ -n "${mount_points[$mount_point]:-}" ]]; then
            errors+=("Line $line_num: Duplicate mount point: $mount_point")
        else
            mount_points[$mount_point]=1
        fi

        # Validation du type de filesystem - mode permissif avec warnings
        debug_log "Validating filesystem type: '$fs_type'"
        local valid_fs_types=("ext2" "ext3" "ext4" "xfs" "btrfs" "f2fs" "vfat" "ntfs" "exfat"
                              "swap" "proc" "sysfs" "tmpfs" "devpts" "devtmpfs" "cgroup" "cgroup2"
                              "nfs" "nfs4" "cifs" "iso9660" "udf" "squashfs" "overlay" "fuse")
        
        local fs_valid=false
        for valid_fs in "${valid_fs_types[@]}"; do
            if [[ "$fs_type" == "$valid_fs" ]]; then
                fs_valid=true
                break
            fi
        done
        
        # FS inconnu - warning mais pas d'erreur
        if [[ "$fs_valid" == "false" ]]; then
            warnings+=("Line $line_num: Unknown filesystem type: $fs_type (may cause mount failure if module not available)")
        fi

        # Validation des options de montage
        local option_errors
        option_errors=$(validate_mount_options "$options" "$fs_type" "$line_num")
        if [[ -n "$option_errors" ]]; then
            errors+=("$option_errors")
        fi

        # Validation dump flag (seulement si présent)
        if [[ ${#fields[@]} -ge 5 ]] && [[ ! "$dump" =~ ^[0-9]+$ ]]; then
            errors+=("Line $line_num: Invalid dump flag (must be numeric): $dump")
        fi

        # Validation pass flag (seulement si présent)
        if [[ ${#fields[@]} -ge 6 ]]; then
            if [[ ! "$pass" =~ ^[0-9]+$ ]]; then
                errors+=("Line $line_num: Invalid pass flag (must be numeric): $pass")
            elif [[ "$pass" -gt 2 ]]; then
                errors+=("Line $line_num: Invalid pass flag (must be 0, 1, or 2): $pass")
            fi
        fi

        # Vérifications logiques
        if [[ "$fs_type" == "swap" ]] && [[ "$mount_point" != "none" ]] && [[ "$mount_point" != "swap" ]]; then
            errors+=("Line $line_num: Swap filesystem should have 'none' or 'swap' as mount point")
        fi

        if [[ "$pass" == "1" ]] && [[ "$mount_point" != "/" ]]; then
            errors+=("Line $line_num: Only root filesystem (/) should have pass=1")
        fi

        ((line_num++))
    done < "$fstab_file"

    debug_log "Validation complete. Found ${#errors[@]} critical errors and ${#warnings[@]} warnings"
    
    # Afficher les erreurs critiques
    if [[ ${#errors[@]} -gt 0 ]]; then
        echo "❌ Validation failed with ${#errors[@]} critical error(s) that will prevent boot:"
        printf '   %s\n' "${errors[@]}"
    fi
    
    # Afficher les warnings
    if [[ ${#warnings[@]} -gt 0 ]]; then
        echo "⚠️  Found ${#warnings[@]} warning(s) (mount may fail but system will boot):" >&2
        printf '   WARNING: %s\n' "${warnings[@]}" >&2
    fi
    
    # Retourner le code approprié
    if [[ ${#errors[@]} -eq 0 ]]; then
        if [[ ${#warnings[@]} -eq 0 ]]; then
            echo "✅ Validation successful: No issues found"
        else
            echo "✅ Validation successful: No boot-critical issues found"
        fi
        return 0
    else
        return 1
    fi
}

# Support des flags de ligne de commande
DEBUG=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --debug)
            DEBUG=true
            shift
            ;;
        --help)
            echo "Usage: $0 [--debug] <fstab_file>"
            echo "  --debug: Enable debug output"
            echo ""
            echo "Exit codes:"
            echo "  0: No boot-critical issues (system will boot)"
            echo "  1: Critical issues found (system may not boot)"
            echo ""
            echo "Output levels:"
            echo "  ✅/❌: Validation result (stdout)"
            echo "  WARNING: Mount issues that won't prevent boot (stderr)" 
            echo "  DEBUG: Detailed validation info (stderr, --debug only)"
            exit 0
            ;;
        *)
            break
            ;;
    esac
done

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 [--strict] [--debug] <fstab_file>"
    exit 1
fi

validate_fstab "$1"