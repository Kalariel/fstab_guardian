#!/bin/bash
# install-recovery-hooks.sh - Installer les hooks de recovery au boot

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RECOVERY_SCRIPT="$SCRIPT_DIR/fstab-recovery.sh"
SYSTEMD_SERVICE="/etc/systemd/system/fstab-guardian-recovery.service"
SYSTEMD_TARGET_WANTS="/etc/systemd/system/local-fs.target.wants"

# Couleurs pour l'affichage
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

install_systemd_hook() {
    echo -e "${YELLOW}Installing systemd recovery hook...${NC}"
    
    # Créer le service systemd
    cat > "$SYSTEMD_SERVICE" << EOF
[Unit]
Description=fstab-guardian boot recovery
DefaultDependencies=false
Before=local-fs.target
After=local-fs-pre.target
Wants=local-fs-pre.target

[Service]
Type=oneshot
ExecStart=$RECOVERY_SCRIPT
StandardOutput=journal
StandardError=journal
RemainAfterExit=yes

[Install]
WantedBy=local-fs.target
EOF

    # Copier le script de recovery
    cp "$RECOVERY_SCRIPT" /usr/local/bin/fstab-recovery.sh
    chmod +x /usr/local/bin/fstab-recovery.sh
    
    # Activer le service
    systemctl daemon-reload
    systemctl enable fstab-guardian-recovery.service
    
    echo -e "${GREEN}✅ Systemd hook installed successfully${NC}"
}

install_initramfs_hook() {
    echo -e "${YELLOW}Installing initramfs recovery hook...${NC}"
    
    # Hook pour initramfs-tools (Debian/Ubuntu)
    if [[ -d /usr/share/initramfs-tools/hooks ]]; then
        cat > /usr/share/initramfs-tools/hooks/fstab-guardian << 'EOF'
#!/bin/sh
# Hook initramfs pour fstab-guardian

PREREQ=""

prereqs() {
    echo "$PREREQ"
}

case "$1" in
    prereqs)
        prereqs
        exit 0
        ;;
esac

. /usr/share/initramfs-tools/hook-functions

# Copier le script de recovery
copy_exec /usr/local/bin/fstab-recovery.sh /bin/fstab-recovery
copy_exec /usr/local/bin/fstab-guardian /bin/fstab-guardian

# Copier les backups si ils existent
if [ -d /etc/fstab-backups ]; then
    mkdir -p "$DESTDIR/etc/fstab-backups"
    cp /etc/fstab-backups/fstab_* "$DESTDIR/etc/fstab-backups/" 2>/dev/null || true
fi
EOF
        chmod +x /usr/share/initramfs-tools/hooks/fstab-guardian
        
        # Script de recovery pour initramfs
        cat > /usr/share/initramfs-tools/scripts/local-premount/fstab-guardian << 'EOF'
#!/bin/sh

PREREQ=""

prereqs() {
    echo "$PREREQ"
}

case "$1" in
    prereqs)
        prereqs
        exit 0
        ;;
esac

# Exécuter la recovery si nécessaire
if [ -x /bin/fstab-recovery ]; then
    /bin/fstab-recovery || true
fi
EOF
        chmod +x /usr/share/initramfs-tools/scripts/local-premount/fstab-guardian
        
        # Régénérer l'initramfs
        update-initramfs -u -k all
        
        echo -e "${GREEN}✅ Initramfs hook installed${NC}"
    else
        echo -e "${YELLOW}⚠️  initramfs-tools not found, skipping initramfs hook${NC}"
    fi
}

uninstall_hooks() {
    echo -e "${YELLOW}Uninstalling recovery hooks...${NC}"
    
    # Désactiver et supprimer le service systemd
    if [[ -f "$SYSTEMD_SERVICE" ]]; then
        systemctl disable fstab-guardian-recovery.service 2>/dev/null || true
        rm -f "$SYSTEMD_SERVICE"
        systemctl daemon-reload
    fi
    
    # Supprimer les hooks initramfs
    rm -f /usr/share/initramfs-tools/hooks/fstab-guardian
    rm -f /usr/share/initramfs-tools/scripts/local-premount/fstab-guardian
    
    # Supprimer le script
    rm -f /usr/local/bin/fstab-recovery.sh
    
    # Régénérer initramfs si nécessaire
    if command -v update-initramfs >/dev/null 2>&1; then
        update-initramfs -u -k all
    fi
    
    echo -e "${GREEN}✅ Recovery hooks uninstalled${NC}"
}

show_status() {
    echo -e "${YELLOW}fstab-guardian recovery status:${NC}"
    echo "================================"
    
    # Vérifier le service systemd
    if systemctl is-enabled fstab-guardian-recovery.service >/dev/null 2>&1; then
        echo -e "Systemd hook: ${GREEN}✅ Enabled${NC}"
    else
        echo -e "Systemd hook: ${RED}❌ Disabled${NC}"
    fi
    
    # Vérifier les hooks initramfs
    if [[ -f /usr/share/initramfs-tools/hooks/fstab-guardian ]]; then
        echo -e "Initramfs hook: ${GREEN}✅ Installed${NC}"
    else
        echo -e "Initramfs hook: ${RED}❌ Not installed${NC}"
    fi
    
    # Vérifier le script de recovery
    if [[ -x /usr/local/bin/fstab-recovery.sh ]]; then
        echo -e "Recovery script: ${GREEN}✅ Available${NC}"
    else
        echo -e "Recovery script: ${RED}❌ Missing${NC}"
    fi
}

main() {
    case "${1:-install}" in
        install)
            install_systemd_hook
            install_initramfs_hook
            ;;
        uninstall)
            uninstall_hooks
            ;;
        status)
            show_status
            ;;
        *)
            echo "Usage: $0 {install|uninstall|status}"
            exit 1
            ;;
    esac
}

# Vérifier les permissions root
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}❌ This script must be run as root${NC}"
    exit 1
fi

main "$@"