#!/bin/bash
# update_versions.sh - Aggiorna automaticamente le versioni dei software neuroimaging

set -e

# Configurazione
CONFIG_FILE="neuroimaging_versions.json"
BACKUP_FILE="neuroimaging_versions_backup_$(date +%Y%m%d).json"
LOG_FILE="update_versions_$(date +%Y%m%d_%H%M%S).log"
SCRIPT_FILE="neuroimaging_installer.sh"
YAML_FILE="neuroimaging_env.yml"

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_msg() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

# Backup configurazione
backup_config() {
    if [ -f "$CONFIG_FILE" ]; then
        cp "$CONFIG_FILE" "$BACKUP_FILE"
        print_msg "Backup creato: $BACKUP_FILE"
    fi
}

# Carica configurazione JSON
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "File di configurazione non trovato: $CONFIG_FILE"
        print_msg "Creazione file di configurazione di default..."
        create_default_config
    fi
    
    # Usa jq se disponibile, altrimenti grep/awk
    if command -v jq >/dev/null 2>&1; then
        CONFIG=$(cat "$CONFIG_FILE")
    else
        print_warning "jq non trovato, uso metodo base per parsing JSON"
    fi
}

# Crea configurazione di default
create_default_config() {
    cat > "$CONFIG_FILE" << 'EOF'
{
  "software": {},
  "python_packages": {},
  "config": {
    "last_checked": "",
    "auto_update": false
  }
}
EOF
    print_msg "Creato file di configurazione di default"
}

# Ottieni ultima versione da URL
get_latest_version() {
    local software=$1
    local check_url=$2
    local method=$3
    
    case "$method" in
        "github_api")
            curl -s "$check_url" | grep -oP '"tag_name": "v?\K[0-9.]+' | head -1
            ;;
        "fsl_html")
            curl -s "$check_url" | grep -oP 'fsl-\K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1
            ;;
        "freesurfer_html")
            curl -s "$check_url" | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1
            ;;
        "afni_html")
            curl -s "$check_url" | grep -oP 'linux_openmp_64\.\K[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1
            ;;
        "pypi_json")
            curl -s "$check_url" | grep -oP '"version": "\K[0-9.]+' | head -1
            ;;
        *)
            curl -s "$check_url" | grep -oP '[0-9]+\.[0-9]+(\.[0-9]+)*' | sort -V | tail -1
            ;;
    esac
}

# Controlla aggiornamenti per software
check_software_updates() {
    print_msg "Controllo aggiornamenti software..."
    
    # Lista software da controllare
    local software_list=("fsl" "freesurfer" "ants" "afni" "mrtrix" "c3d")
    
    for software in "${software_list[@]}"; do
        print_msg "Verifica $software..."
        
        case $software in
            fsl)
                latest=$(get_latest_version "$software" \
                    "https://fsl.fmrib.ox.ac.uk/fsldownloads/" \
                    "fsl_html")
                current="6.0.7.1"
                ;;
            freesurfer)
                latest=$(get_latest_version "$software" \
                    "https://surfer.nmr.mgh.harvard.edu/pub/dist/freesurfer/" \
                    "freesurfer_html")
                current="7.4.1"
                ;;
            ants)
                latest=$(get_latest_version "$software" \
                    "https://api.github.com/repos/ANTsX/ANTs/releases/latest" \
                    "github_api")
                current="2.5.3"
                ;;
            afni)
                latest=$(get_latest_version "$software" \
                    "https://afni.nimh.nih.gov/pub/dist/tgz/" \
                    "afni_html")
                current="latest"
                ;;
            mrtrix)
                latest=$(get_latest_version "$software" \
                    "https://api.github.com/repos/MRtrix3/mrtrix3/releases/latest" \
                    "github_api")
                current="3.0.3"
                ;;
            c3d)
                latest=$(curl -s "https://sourceforge.net/projects/c3d/rss" | \
                    grep -oP '<title>c3d-\K[0-9]+\.[0-9]+\.[0-9]+' | \
                    sort -V | tail -1)
                current="1.4.0"
                ;;
        esac
        
        if [ -n "$latest" ] && [ "$latest" != "$current" ]; then
            print_warning "AGGIORNAMENTO DISPONIBILE: $software $current → $latest"
            echo "$software:$current:$latest" >> updates_available.txt
        elif [ -n "$latest" ]; then
            print_success "$software è aggiornato: $current"
        else
            print_warning "Impossibile verificare $software"
        fi
    done
}

# Controlla aggiornamenti Python packages
check_python_updates() {
    print_msg "Controllo aggiornamenti pacchetti Python..."
    
    # Lista pacchetti da controllare
    declare -A py_packages=(
        ["HD_BET"]="1.0"
        ["LST_AI"]="1.1.0"
        ["nnunet"]="1.7.1"
        ["torch"]="2.9.1"
        ["torchvision"]="0.24.1"
        ["pydeface"]="2.0.2"
    )
    
    for pkg in "${!py_packages[@]}"; do
        current="${py_packages[$pkg]}"
        print_msg "Verifica $pkg..."
        
        latest=$(curl -s "https://pypi.org/pypi/$pkg/json" | \
            grep -oP '"version": "\K[0-9.]+' | head -1)
        
        if [ -n "$latest" ] && [ "$latest" != "$current" ]; then
            print_warning "AGGIORNAMENTO PYPI: $pkg $current → $latest"
            echo "python:$pkg:$current:$latest" >> updates_available.txt
        elif [ -n "$latest" ]; then
            print_success "$pkg è aggiornato: $current"
        else
            print_warning "Impossibile verificare $pkg"
        fi
    done
}

# Aggiorna file di configurazione
update_config_file() {
    local updates_file="updates_available.txt"
    
    if [ ! -f "$updates_file" ]; then
        print_success "Nessun aggiornamento disponibile!"
        return 0
    fi
    
    print_msg "Aggiornamento file di configurazione..."
    
    # Leggi aggiornamenti disponibili
    while IFS=':' read -r type name current latest; do
        case $type in
            fsl|freesurfer|ants|afni|mrtrix|c3d)
                print_msg "Aggiorno $type da $current a $latest"
                
                # Aggiorna variabili nello script
                sed -i "s/${type^^}_VERSION=\"$current\"/${type^^}_VERSION=\"$latest\"/" "$SCRIPT_FILE"
                
                # Aggiorna URL di download se necessario
                if [ "$type" = "fsl" ]; then
                    sed -i "s|fsl-${current}-centos7_64.tar.gz|fsl-${latest}-centos7_64.tar.gz|" "$SCRIPT_FILE"
                elif [ "$type" = "freesurfer" ]; then
                    sed -i "s|freesurfer/${current}/|freesurfer/${latest}/|" "$SCRIPT_FILE"
                    sed -i "s|freesurfer-linux.*${current}.tar.gz|freesurfer-linux.*${latest}.tar.gz|" "$SCRIPT_FILE"
                elif [ "$type" = "ants" ]; then
                    sed -i "s|ants-${current}-Linux|ants-${latest}-Linux|" "$SCRIPT_FILE"
                fi
                ;;
            python)
                print_msg "Aggiorno pacchetto Python $name da $current a $latest"
                
                # Aggiorna YAML file
                if grep -q "$name==$current" "$YAML_FILE"; then
                    sed -i "s/$name==$current/$name==$latest/" "$YAML_FILE"
                elif grep -q "$name>=$current" "$YAML_FILE"; then
                    sed -i "s/$name>=$current/$name>=$latest/" "$YAML_FILE"
                fi
                ;;
        esac
    done < "$updates_file"
    
    # Aggiorna data ultimo controllo
    if [ -f "$CONFIG_FILE" ] && command -v jq >/dev/null 2>&1; then
        jq '.config.last_checked = "'$(date -I)'"' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
        mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    fi
    
    print_success "File di configurazione aggiornati"
    
    # Mostra riepilogo
    echo ""
    echo "════════════════════════════════════════════════════════"
    echo "  RIEPILOGO AGGIORNAMENTI"
    echo "════════════════════════════════════════════════════════"
    cat "$updates_file" | while IFS=':' read -r type name current latest; do
        printf "%-15s %-10s → %-10s\n" "$name" "$current" "$latest"
    done
    echo "════════════════════════════════════════════════════════"
    
    # Pulisci
    rm -f "$updates_file"
}

# Controlla dipendenze sistema
check_system_dependencies() {
    print_msg "Verifica dipendenze di sistema..."
    
    local deps=("curl" "wget" "git" "tar" "gzip" "cmake")
    
    for dep in "${deps[@]}"; do
        if command -v "$dep" >/dev/null 2>&1; then
            print_success "$dep: OK"
        else
            print_warning "$dep: NON TROVATO"
        fi
    done
    
    # Verifica spazio disco
    local disk_space=$(df -h . | awk 'NR==2 {print $4}')
    print_msg "Spazio disco disponibile: $disk_space"
    
    # Verifica RAM
    local total_ram=$(free -h | awk '/^Mem:/ {print $2}')
    print_msg "RAM totale: $total_ram"
}

# Genera report
generate_report() {
    local report_file="version_report_$(date +%Y%m%d).md"
    
    cat > "$report_file" << EOF
# Report Aggiornamenti Neuroimaging
**Data**: $(date)
**Sistema**: $(uname -a)

## Software Neuroimaging

| Software | Versione Corrente | Ultima Versione | Stato |
|----------|-------------------|-----------------|--------|
EOF
    
    # Aggiungi righe per ogni software
    for software in fsl freesurfer ants afni mrtrix c3d; do
        # Qui andrebbe la logica per ottenere le versioni
        echo "| $software | ... | ... | ... |" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF

## Pacchetti Python

| Pacchetto | Versione Corrente | Ultima Versione | Stato |
|-----------|-------------------|-----------------|--------|
EOF
    
    print_success "Report generato: $report_file"
}

# Menu principale
show_menu() {
    echo ""
    echo "════════════════════════════════════════════════════════"
    echo "  AGGREDITORE VERSIONI NEUROIMAGING"
    echo "════════════════════════════════════════════════════════"
    echo "1) Controlla aggiornamenti software"
    echo "2) Controlla aggiornamenti pacchetti Python"
    echo "3) Verifica dipendenze sistema"
    echo "4) Aggiorna file di configurazione"
    echo "5) Genera report completo"
    echo "6) Esegui tutti i controlli"
    echo "7) Esci"
    echo "════════════════════════════════════════════════════════"
    echo -n "Scelta: "
}

# Main
main() {
    echo "========================================================"
    echo "  NEUROIMAGING VERSION UPDATER"
    echo "========================================================"
    
    # Backup
    backup_config
    load_config
    
    # Menu interattivo
    while true; do
        show_menu
        read choice
        
        case $choice in
            1)
                check_software_updates
                ;;
            2)
                check_python_updates
                ;;
            3)
                check_system_dependencies
                ;;
            4)
                update_config_file
                ;;
            5)
                generate_report
                ;;
            6)
                check_software_updates
                check_python_updates
                check_system_dependencies
                update_config_file
                generate_report
                ;;
            7)
                print_msg "Arrivederci!"
                exit 0
                ;;
            *)
                print_error "Scelta non valida"
                ;;
        esac
    done
}

# Gestisci argomenti da riga di comando
case "$1" in
    "--auto")
        check_software_updates
        check_python_updates
        update_config_file
        ;;
    "--check-only")
        check_software_updates
        check_python_updates
        ;;
    "--report")
        generate_report
        ;;
    *)
        main
        ;;
esac