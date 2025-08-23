#!/usr/bin/env bats

setup() {
    export VALIDATOR="./src/validators/fstab_validator.sh"
    export TEST_DIR="tests/tmp"
    mkdir -p "$TEST_DIR"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "Empty fstab file should pass" {
    local test_file="$TEST_DIR/empty_fstab"
    touch "$test_file"

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 0 ]
}

@test "Valid fstab line should pass" {
    local test_file="$TEST_DIR/valid_fstab"
    echo 'UUID=12345678-1234-1234-1234-123456789abc / ext4 defaults 0 1' > "$test_file"

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 0 ]
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

@test "Unknown filesystem type should fail" {
    local test_file="$TEST_DIR/invalid_fs_fstab"
    echo 'UUID=12345678-1234-1234-1234-123456789abc / unknownfs defaults 0 1' > "$test_file"

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Unknown filesystem type"* ]]
}

@test "Incorrect number of fields should fail" {
    local test_file="$TEST_DIR/wrong_fields_fstab"
    echo 'UUID=12345678-1234-1234-1234-123456789abc / ext4 defaults 0' > "$test_file"

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Expected 6 fields"* ]]
}

@test "Commented or empty lines should pass" {
    local test_file="$TEST_DIR/commented_fstab"
    echo '# This is a comment' > "$test_file"
    echo '' >> "$test_file"
    echo 'UUID=12345678-1234-1234-1234-123456789abc / ext4 defaults 0 1' >> "$test_file"

    run bash "$VALIDATOR" "$test_file"

    [ "$status" -eq 0 ]
}