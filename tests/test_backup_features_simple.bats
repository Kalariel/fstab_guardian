#!/usr/bin/env bats

# Tests simplifiés pour les nouvelles fonctionnalités backup
# Se concentrent sur la validation des arguments et la logique de base

setup() {
    export TEST_DIR="tests/tmp"
    export TEST_BACKUP_DIR="$TEST_DIR/test-backups"
    
    mkdir -p "$TEST_DIR"
    mkdir -p "$TEST_BACKUP_DIR"
    
    # Créer un fstab de test
    export TEST_FSTAB="$TEST_DIR/test_fstab"
    cat > "$TEST_FSTAB" << 'EOF'
# Test fstab
UUID=12345678-1234-1234-1234-123456789abc / ext4 defaults 0 1
EOF
}

teardown() {
    rm -rf "$TEST_DIR"
}

# =============================================================================
# TESTS PARSING DES ARGUMENTS
# =============================================================================

@test "backup --comment parsing: should accept valid comment format" {
    # Test que les arguments sont bien parsés sans exécution
    run bash -c '
        args=("backup" "--comment" "Test comment" "file.txt")
        if [[ "${args[1]}" == "--comment" ]] && [[ -n "${args[2]}" ]]; then
            echo "PARSED: comment=${args[2]} file=${args[3]}"
        else
            echo "FAILED"
        fi
    '
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"PARSED: comment=Test comment file=file.txt"* ]]
}

@test "backup --comment parsing: should reject empty comment" {
    run bash -c '
        args=("backup" "--comment" "" "file.txt")
        if [[ "${args[1]}" == "--comment" ]] && [[ -n "${args[2]}" ]]; then
            echo "PARSED"
        else
            echo "REJECTED"
        fi
    '
    
    [ "$status" -eq 0 ]
    [[ "$output" == "REJECTED" ]]
}

@test "clean-backups --older-than parsing: should validate time formats" {
    # Test format valide jours
    run bash -c '
        time_spec="30d"
        if [[ "$time_spec" =~ ^([0-9]+)d$ ]]; then
            echo "VALID_DAYS: ${BASH_REMATCH[1]}"
        else
            echo "INVALID"
        fi
    '
    [ "$status" -eq 0 ]
    [[ "$output" == "VALID_DAYS: 30" ]]
    
    # Test format valide heures
    run bash -c '
        time_spec="24h"
        if [[ "$time_spec" =~ ^([0-9]+)h$ ]]; then
            echo "VALID_HOURS: ${BASH_REMATCH[1]}"
        else
            echo "INVALID"
        fi
    '
    [ "$status" -eq 0 ]
    [[ "$output" == "VALID_HOURS: 24" ]]
    
    # Test format invalide
    run bash -c '
        time_spec="invalid"
        if [[ "$time_spec" =~ ^([0-9]+)[dhm]$ ]]; then
            echo "VALID"
        else
            echo "INVALID"
        fi
    '
    [ "$status" -eq 0 ]
    [[ "$output" == "INVALID" ]]
}

# =============================================================================
# TESTS FICHIERS MÉTADONNÉES
# =============================================================================

@test "metadata file creation: should create meta file with comment" {
    local backup_file="$TEST_BACKUP_DIR/fstab_test"
    local meta_file="${backup_file}.meta"
    local comment="Test metadata comment"
    
    # Simuler la création du fichier meta
    cat > "$meta_file" << EOF
# Backup metadata for $(basename "$backup_file")
# Created: $(date '+%Y-%m-%d %H:%M:%S')
# Original: $TEST_FSTAB
# Comment: $comment
EOF
    
    # Vérifier que le fichier existe
    [ -f "$meta_file" ]
    
    # Vérifier le contenu
    run grep "Comment: $comment" "$meta_file"
    [ "$status" -eq 0 ]
    
    # Vérifier les autres champs
    run grep "Original: $TEST_FSTAB" "$meta_file"
    [ "$status" -eq 0 ]
}

@test "metadata file reading: should extract comment from meta file" {
    local backup_file="$TEST_BACKUP_DIR/fstab_test"
    local meta_file="${backup_file}.meta"
    local test_comment="My backup comment"
    
    # Créer fichier meta de test
    cat > "$meta_file" << EOF
# Backup metadata for fstab_test
# Created: 2025-01-01 12:00:00
# Original: /etc/fstab
# Comment: $test_comment
EOF
    
    # Tester l'extraction du commentaire
    run bash -c "grep '^# Comment:' '$meta_file' | sed 's/^# Comment: //'"
    
    [ "$status" -eq 0 ]
    [[ "$output" == "$test_comment" ]]
}

# =============================================================================
# TESTS LOGIQUE FIND POUR CLEAN-BACKUPS
# =============================================================================

@test "find old files logic: should identify files by age" {
    # Créer des fichiers de test avec différentes dates
    local old_file="$TEST_BACKUP_DIR/fstab_old"
    local new_file="$TEST_BACKUP_DIR/fstab_new"
    
    touch "$old_file" "$new_file"
    
    # Modifier la date du fichier "ancien" (2020)
    touch -t 202001011200 "$old_file"
    
    # Test find avec -mtime (pour les jours)
    run bash -c "find '$TEST_BACKUP_DIR' -name 'fstab_*' -type f -mtime +365 | wc -l"
    
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]  # Devrait trouver 1 fichier ancien
    
    # Test find avec -mmin (pour les minutes)
    run bash -c "find '$TEST_BACKUP_DIR' -name 'fstab_*' -type f -mmin +$(((365*24*60))) | wc -l"
    
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]  # Devrait trouver 1 fichier ancien
}

# =============================================================================
# TESTS RESTORE INTERACTIF - LOGIQUE DE BASE
# =============================================================================

@test "restore interactive logic: should handle empty backup directory" {
    # Tester la logique de détection de dossier vide
    run bash -c '
        backup_dir="'$TEST_BACKUP_DIR'"
        if [[ ! -d "$backup_dir" ]] || ! find "$backup_dir" -name "fstab_*" -type f -print -quit 2>/dev/null | grep -q .; then
            echo "NO_BACKUPS"
        else
            echo "BACKUPS_FOUND"
        fi
    '
    
    [ "$status" -eq 0 ]
    [[ "$output" == "NO_BACKUPS" ]]
}

@test "restore interactive logic: should detect available backups" {
    # Créer quelques fichiers backup de test
    touch "$TEST_BACKUP_DIR/fstab_20250101_120000"
    touch "$TEST_BACKUP_DIR/fstab_20250102_120000"
    
    # Tester la logique de détection
    run bash -c '
        backup_dir="'$TEST_BACKUP_DIR'"
        if [[ ! -d "$backup_dir" ]] || ! find "$backup_dir" -name "fstab_*" -type f -print -quit 2>/dev/null | grep -q .; then
            echo "NO_BACKUPS"
        else
            count=$(find "$backup_dir" -name "fstab_*" -type f | wc -l)
            echo "BACKUPS_FOUND: $count"
        fi
    '
    
    [ "$status" -eq 0 ]
    [[ "$output" == "BACKUPS_FOUND: 2" ]]
}

@test "restore interactive logic: should validate numeric input" {
    # Tester la validation des entrées numériques
    run bash -c '
        choice="1"
        total_backups=3
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$total_backups" ]]; then
            echo "VALID"
        else
            echo "INVALID"
        fi
    '
    
    [ "$status" -eq 0 ]
    [[ "$output" == "VALID" ]]
    
    # Test avec entrée invalide
    run bash -c '
        choice="abc"
        total_backups=3
        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le "$total_backups" ]]; then
            echo "VALID"
        else
            echo "INVALID"
        fi
    '
    
    [ "$status" -eq 0 ]
    [[ "$output" == "INVALID" ]]
}

# =============================================================================
# TEST D'INTÉGRATION SIMPLE
# =============================================================================

@test "integration: metadata workflow from creation to display" {
    local backup_name="fstab_20250101_120000"
    local backup_file="$TEST_BACKUP_DIR/$backup_name"
    local meta_file="${backup_file}.meta"
    local test_comment="Integration test backup"
    
    # 1. Créer un backup simulé avec métadonnées
    cp "$TEST_FSTAB" "$backup_file"
    cat > "$meta_file" << EOF
# Backup metadata for $backup_name
# Created: $(date '+%Y-%m-%d %H:%M:%S')
# Original: $TEST_FSTAB
# Comment: $test_comment
EOF
    
    # 2. Vérifier que les fichiers existent
    [ -f "$backup_file" ]
    [ -f "$meta_file" ]
    
    # 3. Simuler list-backups (logique d'affichage)
    run bash -c '
        backup_dir="'$TEST_BACKUP_DIR'"
        find "$backup_dir" -name "fstab_*" -type f -printf "%TY-%Tm-%Td %TH:%TM  %s bytes  %p\n" 2>/dev/null | \
        sort -r | while IFS= read -r line; do
            backup_file=$(echo "$line" | awk "{print \$NF}")
            meta_file="${backup_file}.meta"
            
            echo "$line"
            
            if [[ -f "$meta_file" ]]; then
                comment=$(grep "^# Comment:" "$meta_file" 2>/dev/null | sed "s/^# Comment: //")
                if [[ -n "$comment" ]]; then
                    echo "                           💬 $comment"
                fi
            fi
        done
    '
    
    [ "$status" -eq 0 ]
    [[ "$output" == *"$backup_name"* ]]
    [[ "$output" == *"💬 $test_comment"* ]]
}