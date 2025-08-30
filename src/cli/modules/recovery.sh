#!/bin/bash
# fstab-guardian recovery module
# Interface avec les hooks de boot recovery

check_boot_recovery_installed() {
    # Vérifier si le service systemd est installé et activé
    if systemctl is-enabled fstab-guardian-recovery.service >/dev/null 2>&1; then
        return 0
    fi
    
    # Vérifier si les hooks initramfs sont installés
    if [[ -f /usr/share/initramfs-tools/hooks/fstab-guardian ]]; then
        return 0
    fi
    
    return 1
}

install_boot_recovery() {
    echo -e "${YELLOW}🛡️  Installing boot recovery hooks...${NC}"
    echo "============================================="
    
    # Vérifier les permissions root
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ Boot recovery installation requires root privileges${NC}"
        echo "Please run: sudo fstab-guardian install-boot-recovery"
        return 1
    fi
    
    # Déléguer à l'installateur dédié
    if [[ -x "$SCRIPT_DIR/../boot/install-recovery-hooks.sh" ]]; then
        "$SCRIPT_DIR/../boot/install-recovery-hooks.sh" install
    else
        echo -e "${RED}❌ Recovery installer not found: $SCRIPT_DIR/../boot/install-recovery-hooks.sh${NC}"
        return 1
    fi
}

test_boot_recovery() {
    echo -e "${YELLOW}🧪 Testing boot recovery...${NC}"
    echo "==============================="
    
    # Vérifier les permissions root
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ Boot recovery testing requires root privileges${NC}"
        echo "Please run: sudo fstab-guardian test-boot-recovery"
        return 1
    fi
    
    # Déléguer au testeur dédié
    if [[ -x "$SCRIPT_DIR/../boot/fstab-recovery.sh" ]]; then
        "$SCRIPT_DIR/../boot/fstab-recovery.sh"
    else
        echo -e "${RED}❌ Recovery script not found: $SCRIPT_DIR/../boot/fstab-recovery.sh${NC}"
        return 1
    fi
}

show_boot_logs() {
    local recovery_log="${RECOVERY_LOG:-/var/log/fstab-guardian.log}"
    
    if [[ -f "$recovery_log" ]]; then
        echo -e "${YELLOW}📄 Boot recovery logs:${NC}"
        echo "=============================="
        
        # Afficher les logs avec pagination si le fichier est long
        local log_lines
        log_lines=$(wc -l < "$recovery_log")
        
        if [[ $log_lines -gt 50 ]]; then
            echo "📊 Total entries: $log_lines (showing last 50)"
            echo ""
            tail -50 "$recovery_log"
        else
            echo "📊 Total entries: $log_lines"
            echo ""
            cat "$recovery_log"
        fi
        
        # Ajouter un résumé des événements récents
        echo ""
        echo -e "${YELLOW}📈 Recent activity summary:${NC}"
        echo "============================"
        
        local today=$(date '+%Y-%m-%d')
        local recent_count
        recent_count=$(grep "$today" "$recovery_log" 2>/dev/null | wc -l)
        
        if [[ $recent_count -gt 0 ]]; then
            echo "🕒 Today: $recent_count entries"
            
            # Compter les types d'événements
            local recovery_count
            recovery_count=$(grep "$today.*RECOVERY:" "$recovery_log" 2>/dev/null | wc -l)
            [[ $recovery_count -gt 0 ]] && echo "🔄 Recoveries: $recovery_count"
            
            local error_count
            error_count=$(grep "$today.*ERROR:" "$recovery_log" 2>/dev/null | wc -l)
            [[ $error_count -gt 0 ]] && echo "❌ Errors: $error_count"
            
            local warning_count
            warning_count=$(grep "$today.*WARNING:" "$recovery_log" 2>/dev/null | wc -l)
            [[ $warning_count -gt 0 ]] && echo "⚠️  Warnings: $warning_count"
        else
            echo "✅ No activity today"
        fi
        
        # Afficher le statut du dernier boot
        echo ""
        echo -e "${YELLOW}🚀 Last boot status:${NC}"
        echo "===================="
        
        local last_boot
        last_boot=$(grep "RECOVERY:" "$recovery_log" 2>/dev/null | tail -1)
        
        if [[ -n "$last_boot" ]]; then
            echo "$last_boot"
        else
            echo "✅ No recovery needed at last boot"
        fi
        
    else
        echo -e "${YELLOW}⚠️  No recovery logs found at $recovery_log${NC}"
        echo ""
        echo "This could mean:"
        echo "• Boot recovery hooks are not installed"
        echo "• No recovery events have occurred"
        echo "• Log file location has been changed"
        echo ""
        echo "To install boot recovery: sudo fstab-guardian install-boot-recovery"
    fi
}

uninstall_boot_recovery() {
    echo -e "${YELLOW}🗑️  Uninstalling boot recovery hooks...${NC}"
    echo "=============================================="
    
    # Vérifier les permissions root
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}❌ Boot recovery uninstallation requires root privileges${NC}"
        echo "Please run: sudo fstab-guardian uninstall-boot-recovery"
        return 1
    fi
    
    # Déléguer à l'installateur avec option uninstall
    if [[ -x "$SCRIPT_DIR/../boot/install-recovery-hooks.sh" ]]; then
        "$SCRIPT_DIR/../boot/install-recovery-hooks.sh" uninstall
    else
        echo -e "${RED}❌ Recovery installer not found: $SCRIPT_DIR/../boot/install-recovery-hooks.sh${NC}"
        return 1
    fi
}

show_recovery_status() {
    echo -e "${YELLOW}🛡️  Boot Recovery Status${NC}"
    echo "============================"
    
    # Vérifier l'installation
    if check_boot_recovery_installed; then
        echo -e "${GREEN}✅ Boot recovery is installed${NC}"
        
        # Détails de l'installation
        echo ""
        echo "📋 Installation details:"
        
        # Service systemd
        if systemctl is-enabled fstab-guardian-recovery.service >/dev/null 2>&1; then
            echo -e "   ${GREEN}✅ Systemd service: enabled${NC}"
            local service_status
            service_status=$(systemctl is-active fstab-guardian-recovery.service 2>/dev/null || echo "inactive")
            echo "      Status: $service_status"
        else
            echo -e "   ${YELLOW}⚠️  Systemd service: not enabled${NC}"
        fi
        
        # Hooks initramfs
        if [[ -f /usr/share/initramfs-tools/hooks/fstab-guardian ]]; then
            echo -e "   ${GREEN}✅ Initramfs hook: installed${NC}"
        else
            echo -e "   ${YELLOW}⚠️  Initramfs hook: not found${NC}"
        fi
        
        # Script de recovery
        if [[ -x "$SCRIPT_DIR/../boot/fstab-recovery.sh" ]]; then
            echo -e "   ${GREEN}✅ Recovery script: available${NC}"
        else
            echo -e "   ${RED}❌ Recovery script: missing${NC}"
        fi
        
    else
        echo -e "${RED}❌ Boot recovery is not installed${NC}"
        echo ""
        echo "To install: sudo fstab-guardian install-boot-recovery"
    fi
    
    # Logs récents
    echo ""
    local recovery_log="${RECOVERY_LOG:-/var/log/fstab-guardian.log}"
    if [[ -f "$recovery_log" ]]; then
        local log_entries
        log_entries=$(wc -l < "$recovery_log")
        echo "📄 Recovery logs: $log_entries entries"
        
        local recent_entries
        recent_entries=$(tail -5 "$recovery_log" 2>/dev/null | wc -l)
        if [[ $recent_entries -gt 0 ]]; then
            echo "   Last activity: $(tail -1 "$recovery_log" 2>/dev/null | awk '{print $1, $2}')"
        fi
    else
        echo "📄 Recovery logs: none found"
    fi
}