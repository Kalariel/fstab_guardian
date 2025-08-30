#!/bin/bash
# fstab-guardian editor module
# Édition sécurisée avec validation automatique

edit_fstab() {
    local fstab_file="${1:-/etc/fstab}"
    local editor="${EDITOR:-nano}"
    
    echo -e "${YELLOW}✏️  Safe editing: $fstab_file${NC}"
    echo "----------------------------------------"
    
    # Vérifier que le fichier existe
    if [[ ! -f "$fstab_file" ]]; then
        echo -e "${RED}❌ File not found: $fstab_file${NC}"
        return 1
    fi
    
    # 1. Créer un backup automatique
    echo "🔄 Step 1: Creating automatic backup..."
    if ! backup_fstab "$fstab_file"; then
        echo -e "${RED}❌ Backup failed! Aborting edit for safety.${NC}"
        return 1
    fi
    
    # 2. Validation initiale
    echo ""
    echo "🔍 Step 2: Initial validation..."
    local initial_valid=false
    if bash "$VALIDATOR" "$fstab_file" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Current fstab is valid${NC}"
        initial_valid=true
    else
        echo -e "${YELLOW}⚠️  Current fstab has issues (will validate after edit)${NC}"
    fi
    
    # 3. Copier vers un fichier temporaire pour l'édition
    local temp_file
    temp_file=$(mktemp --suffix=.fstab)
    cp "$fstab_file" "$temp_file"
    
    echo ""
    echo "📝 Step 3: Launching editor..."
    echo "Editor: $editor"
    echo "Temp file: $temp_file"
    echo ""
    echo -e "${YELLOW}💡 TIP: Save and exit when done. Validation will run automatically.${NC}"
    echo ""
    
    # Pause pour que l'utilisateur puisse lire
    read -p "Press Enter to continue..." -r
    
    # 4. Lancer l'éditeur
    if command -v "$editor" >/dev/null 2>&1; then
        "$editor" "$temp_file"
    else
        echo -e "${YELLOW}⚠️  Editor '$editor' not found. Using nano...${NC}"
        nano "$temp_file"
    fi
    
    # 5. Vérifier si le fichier a été modifié
    if cmp -s "$fstab_file" "$temp_file"; then
        echo -e "${YELLOW}ℹ️  No changes made. Cleaning up...${NC}"
        rm -f "$temp_file"
        return 0
    fi
    
    echo ""
    echo "🔍 Step 4: Validating edited fstab..."
    
    # 6. Valider le fichier édité
    if bash "$VALIDATOR" "$temp_file"; then
        echo ""
        echo -e "${GREEN}✅ Validation passed!${NC}"
        
        # 7. Demander confirmation pour appliquer les changements
        echo -e "${YELLOW}📋 Changes summary:${NC}"
        echo "=================="
        if command -v diff >/dev/null 2>&1; then
            diff -u "$fstab_file" "$temp_file" --color=always || true
        else
            echo "Modified: $temp_file"
        fi
        
        echo ""
        read -p "Apply these changes to $fstab_file? (y/N): " -r
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            # 8. Appliquer les changements
            if sudo cp "$temp_file" "$fstab_file"; then
                echo -e "${GREEN}✅ Changes applied successfully!${NC}"
                
                # 9. Test de montage si activé
                if [[ "$ENABLE_MOUNT_TEST" == "true" ]]; then
                    echo ""
                    echo "🧪 Running mount tests..."
                    test_mounts "$fstab_file" || true
                fi
                
                echo ""
                echo -e "${GREEN}🎉 Edit completed successfully!${NC}"
                echo "Your fstab has been updated and validated."
            else
                echo -e "${RED}❌ Failed to apply changes!${NC}"
                echo "Your original fstab is unchanged."
            fi
        else
            echo "❌ Changes discarded. Original fstab unchanged."
        fi
    else
        echo ""
        echo -e "${RED}❌ Validation failed!${NC}"
        echo "The edited fstab contains errors that could prevent boot."
        echo ""
        
        handle_validation_failure "$temp_file"
    fi
    
    # Nettoyage
    rm -f "$temp_file"
}