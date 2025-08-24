#!/usr/bin/env bats

setup() {
    export VALIDATOR="./src/validators/fstab_validator.sh"
    export TEST_DIR="tests/tmp"
    mkdir -p "$TEST_DIR"
}

teardown() {
    rm -rf "$TEST_DIR"
}

# =============================================================================
# TESTS DE BASE (MODE NON-STRICT)
# =============================================================================

@test "Empty fstab file should pass" {
    local test_file="$TEST_DIR/empty_fstab"
    touch "$test_file"

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 0 ]
}

@test "Valid fstab line (6 fields) should pass" {
    local test_file="$TEST_DIR/valid_fstab_6_fields"
    echo 'UUID=12345678-1234-1234-1234-123456789abc / ext4 defaults 0 1' > "$test_file"

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 0 ]
}

@test "Valid fstab line (5 fields) should pass" {
    local test_file="$TEST_DIR/valid_fstab_5_fields"
    echo 'UUID=12345678-1234-1234-1234-123456789abc / ext4 defaults 0' > "$test_file"

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 0 ]
}

@test "Valid fstab line (4 fields) should pass" {
    local test_file="$TEST_DIR/valid_fstab_4_fields"
    echo 'UUID=12345678-1234-1234-1234-123456789abc / ext4 defaults' > "$test_file"

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 0 ]
}

@test "Too few fields (less than 4) should fail" {
    local test_file="$TEST_DIR/too_few_fields_fstab"
    echo 'UUID=12345678-1234-1234-1234-123456789abc / ext4' > "$test_file"

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Insufficient fields"* ]]
}

@test "Invalid UUID should fail" {
    local test_file="$TEST_DIR/invalid_uuid_fstab"
    echo 'UUID=not-a-uuid / ext4 defaults 0 1' > "$test_file"

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid UUID format"* ]]
}

@test "Non-absolute mount point should fail" {
    local test_file="$TEST_DIR/invalid_mountpoint_fstab"
    echo 'UUID=12345678-1234-1234-1234-123456789abc home ext4 defaults 0 1' > "$test_file"

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Mount point must be absolute path"* ]]
}

@test "Unknown filesystem type should pass (system will boot, mount may fail)" {
    local test_file="$TEST_DIR/unknown_fs_fstab"
    echo 'UUID=12345678-1234-1234-1234-123456789abc / unknownfs defaults 0 1' > "$test_file"

    run bash "$VALIDATOR" "$test_file"

    # Type FS inconnu ne fait pas planter le boot - juste le mount échoue
    [ "$status" -eq 0 ]
}

@test "Commented and empty lines should be ignored" {
    local test_file="$TEST_DIR/commented_fstab"
    cat > "$test_file" <<EOF
# This is a comment
# Another comment

UUID=12345678-1234-1234-1234-123456789abc / ext4 defaults 0 1

# More comments
UUID=12345678-1234-1234-1234-123456789def /home ext4 defaults 0 2
EOF

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 0 ]
}

@test "Duplicate mount points should fail" {
    local test_file="$TEST_DIR/duplicate_mountpoint_fstab"
    cat > "$test_file" <<EOF
UUID=12345678-1234-1234-1234-123456789abc / ext4 defaults 0 1
UUID=12345678-1234-1234-1234-123456789def / ext4 defaults 0 1
EOF

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Duplicate mount point"* ]]
}

@test "Complex fstab with mixed valid/invalid entries should fail appropriately" {
    local test_file="$TEST_DIR/complex_fstab"
    cat > "$test_file" <<EOF
# Comment line
UUID=12345678-1234-1234-1234-123456789abc / ext4 defaults 0 1
UUID=12345678-1234-1234-1234-123456789def / ext4 defaults 0 1
UUID=invalid-uuid /home ext4 defaults 0 2
/dev/sda1 /boot ext4 defaults 0 2
none /proc proc defaults 0 0
EOF

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid UUID format"* ]]
    [[ "$output" == *"Duplicate mount point"* ]]
}

# =============================================================================
# TESTS SPÉCIFIQUES AUX TYPES DE DEVICE
# =============================================================================

@test "LABEL device specification should pass" {
    local test_file="$TEST_DIR/label_fstab"
    echo 'LABEL=root / ext4 defaults 0 1' > "$test_file"

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 0 ]
}

@test "Device path (/dev/sda1) should pass" {
    local test_file="$TEST_DIR/device_path_fstab"
    echo '/dev/sda1 / ext4 defaults 0 1' > "$test_file"

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 0 ]
}

@test "Special filesystems (proc, sysfs, tmpfs) should pass" {
    local test_file="$TEST_DIR/special_fs_fstab"
    cat > "$test_file" <<EOF
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
tmpfs /tmp tmpfs defaults 0 0
devpts /dev/pts devpts defaults 0 0
EOF

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 0 ]
}

@test "Network filesystems should pass" {
    local test_file="$TEST_DIR/network_fs_fstab"
    cat > "$test_file" <<EOF
//server/share /mnt/share cifs defaults 0 0
server:/path /mnt/nfs nfs defaults 0 0
EOF

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 0 ]
}

# =============================================================================
# TESTS DE VALIDATION DES OPTIONS
# =============================================================================

@test "Common mount options should pass" {
    local test_file="$TEST_DIR/mount_options_fstab"
    cat > "$test_file" <<EOF
UUID=12345678-1234-1234-1234-123456789abc / ext4 defaults,noatime,relatime 0 1
UUID=12345678-1234-1234-1234-123456789def /home ext4 rw,user,exec,dev 0 2
EOF

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 0 ]
}

@test "Filesystem-specific options should pass" {
    local test_file="$TEST_DIR/fs_specific_options_fstab"
    cat > "$test_file" <<EOF
UUID=12345678-1234-1234-1234-123456789abc / ext4 defaults,data=ordered,barrier 0 1
UUID=12345678-1234-1234-1234-123456789def /boot vfat defaults,uid=1000,gid=1000,umask=022 0 2
UUID=12345678-1234-1234-1234-123456789012 none swap defaults,pri=1 0 0
EOF

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 0 ]
}

# =============================================================================
# TESTS DE VALIDATION DES FLAGS DUMP ET PASS
# =============================================================================

@test "Invalid dump flag (non-numeric) should fail" {
    local test_file="$TEST_DIR/invalid_dump_fstab"
    echo 'UUID=12345678-1234-1234-1234-123456789abc / ext4 defaults x 1' > "$test_file"

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid dump flag"* ]]
}

@test "Invalid pass flag (non-numeric) should fail" {
    local test_file="$TEST_DIR/invalid_pass_fstab"
    echo 'UUID=12345678-1234-1234-1234-123456789abc / ext4 defaults 0 x' > "$test_file"

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid pass flag"* ]]
}

@test "Invalid pass flag (greater than 2) should fail" {
    local test_file="$TEST_DIR/invalid_pass_high_fstab"
    echo 'UUID=12345678-1234-1234-1234-123456789abc / ext4 defaults 0 3' > "$test_file"

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid pass flag"* ]]
}

@test "Pass flag 1 on non-root filesystem should fail" {
    local test_file="$TEST_DIR/pass1_non_root_fstab"
    echo 'UUID=12345678-1234-1234-1234-123456789abc /home ext4 defaults 0 1' > "$test_file"

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Only root filesystem (/) should have pass=1"* ]]
}

# =============================================================================
# TESTS DE COHÉRENCE LOGIQUE
# =============================================================================

@test "Swap filesystem with wrong mount point should fail" {
    local test_file="$TEST_DIR/swap_wrong_mount_fstab"
    echo 'UUID=12345678-1234-1234-1234-123456789abc /home swap defaults 0 0' > "$test_file"

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Swap filesystem should have 'none' or 'swap' as mount point"* ]]
}

@test "Valid swap entry should pass" {
    local test_file="$TEST_DIR/valid_swap_fstab"
    echo 'UUID=12345678-1234-1234-1234-123456789abc none swap defaults 0 0' > "$test_file"

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 0 ]
}

# =============================================================================
# TESTS BOOT-CRITICAL - Ce qui fait vraiment planter le système
# =============================================================================

@test "BOOT-CRITICAL: Malformed UUID causes boot failure" {
    local test_file="$TEST_DIR/malformed_uuid_fstab"
    echo 'UUID=not-a-uuid / ext4 defaults 0 1' > "$test_file"

    run bash "$VALIDATOR" "$test_file"

    # UUID malformé peut causer des erreurs de parsing au boot
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid UUID format"* ]]
}

@test "BOOT-CRITICAL: Duplicate root mount causes boot failure" {
    local test_file="$TEST_DIR/duplicate_root_fstab"
    cat > "$test_file" <<EOF
UUID=12345678-1234-1234-1234-123456789abc / ext4 defaults 0 1
UUID=12345678-1234-1234-1234-123456789def / ext4 defaults 0 1
EOF

    run bash "$VALIDATOR" "$test_file"

    # Plusieurs montages sur / causent des conflits au boot
    [ "$status" -eq 1 ]
    [[ "$output" == *"Duplicate mount point"* ]]
}

@test "BOOT-CRITICAL: Invalid pass flags cause fsck issues" {
    local test_file="$TEST_DIR/invalid_pass_boot_fstab"
    echo 'UUID=12345678-1234-1234-1234-123456789abc / ext4 defaults 0 x' > "$test_file"

    run bash "$VALIDATOR" "$test_file"

    # Pass flags non-numériques causent des erreurs fsck
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid pass flag"* ]]
}

@test "NON-CRITICAL: Unknown mount options should pass (ignored by mount)" {
    local test_file="$TEST_DIR/unknown_options_fstab"
    echo 'UUID=12345678-1234-1234-1234-123456789abc / ext4 defaults,unknownoption 0 1' > "$test_file"

    run bash "$VALIDATOR" "$test_file"

    # Options inconnues sont ignorées par mount - pas de plantage
    [ "$status" -eq 0 ]
}

@test "NON-CRITICAL: Non-existent UUID should pass with warning" {
    local test_file="$TEST_DIR/nonexistent_uuid_fstab"
    echo 'UUID=12345678-1234-1234-1234-123456789abc /home ext4 defaults 0 2' > "$test_file"

    run bash "$VALIDATOR" "$test_file" 2>&1

    # UUID inexistant -> warning mais passe (mount échoue, système démarre)
    [ "$status" -eq 0 ]
    [[ "$output" == *"✅ Validation successful"* ]]
    [[ "$output" == *"WARNING:"* ]]
}

@test "NON-CRITICAL: Unknown filesystem type should pass with warning" {
    local test_file="$TEST_DIR/unknown_fs_warning_fstab"
    echo 'UUID=12345678-1234-1234-1234-123456789abc / unknownfs defaults 0 1' > "$test_file"

    run bash "$VALIDATOR" "$test_file" 2>&1

    # Type FS inconnu -> warning mais passe
    [ "$status" -eq 0 ]
    [[ "$output" == *"✅ Validation successful"* ]]
    [[ "$output" == *"WARNING:"* ]]
}

# =============================================================================
# TESTS DES FLAGS DE DEBUG
# =============================================================================

@test "Debug mode should produce debug output" {
    local test_file="$TEST_DIR/debug_test_fstab"
    echo 'UUID=12345678-1234-1234-1234-123456789abc / ext4 defaults 0 1' > "$test_file"

    run bash "$VALIDATOR" --debug "$test_file" 2>&1

    [ "$status" -eq 0 ]
    [[ "$output" == *"DEBUG:"* ]]
}

@test "Warning messages should appear on stderr" {
    local test_file="$TEST_DIR/warning_stderr_fstab"
    echo 'UUID=12345678-1234-1234-1234-123456789abc / unknownfs defaults 0 1' > "$test_file"

    run bash "$VALIDATOR" "$test_file" 2>&1

    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING:"* ]]
    [[ "$output" == *"✅ Validation successful"* ]]
}

# =============================================================================
# TESTS D'INTÉGRATION - FICHIERS FSTAB RÉALISTES
# =============================================================================

@test "Realistic Ubuntu-style fstab should pass" {
    local test_file="$TEST_DIR/ubuntu_style_fstab"
    cat > "$test_file" <<EOF
# /etc/fstab: static file system information.
#
# Use 'blkid' to print the universally unique identifier for a
# device; this may be used with UUID= as a more robust way to name devices
# that works even if disks are added and removed. See fstab(5).
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
# / was on /dev/sda1 during installation
UUID=12345678-1234-1234-1234-123456789abc /               ext4    errors=remount-ro 0       1
# /home was on /dev/sda2 during installation  
UUID=12345678-1234-1234-1234-123456789def /home           ext4    defaults        0       2
# swap was on /dev/sda3 during installation
UUID=12345678-1234-1234-1234-123456789014 none            swap    sw              0       0
/dev/sr0        /media/cdrom0   udf,iso9660 user,noauto     0       0
EOF

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 0 ]
}

@test "Realistic server-style fstab should pass" {
    local test_file="$TEST_DIR/server_style_fstab"
    cat > "$test_file" <<EOF
# Server configuration with various mount points
UUID=12345678-1234-1234-1234-123456789abc / ext4 defaults 0 1
UUID=12345678-1234-1234-1234-123456789def /boot ext4 defaults 0 2
UUID=12345678-1234-1234-1234-123456789013 /home xfs defaults,noatime 0 2
UUID=12345678-1234-1234-1234-123456789345 /var btrfs defaults,compress=zstd 0 0
UUID=12345678-1234-1234-1234-123456789678 none swap sw 0 0
tmpfs /tmp tmpfs defaults,nodev,nosuid,size=2G 0 0
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
devpts /dev/pts devpts defaults 0 0
//fileserver/data /mnt/data cifs username=backup,password=secret,uid=1000 0 0
EOF

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 0 ]
}