#!/bin/bash
# fstab-guardian installer
# Usage: sudo bash install.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/src/cli/fstab-guardian.sh" install "$@"
