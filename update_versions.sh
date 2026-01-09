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
CYAN='\033[0;36m'
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
  "docker_images": {},
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
        "dockerhub_api")
            # Ottiene l'ultimo tag da Docker Hub
            curl -s "$check_url?page_size=100" | \
                grep -oP '"name": "\K[0-9]+\.[0-9]+\.[0-9]+"' | \
                sort -V | tail -1
            ;;
        *)
            curl -s "$check_url" | grep -oP '[0-9]+\.[0-9]+(\.[0-9]+)*' | sort -V | tail -1
            ;;
    esac
}

# Controlla aggiornamenti Docker images
check_docker_images_updates() {
    print_msg "Controllo aggiornamenti immagini Docker..."
    
    # Verifica se Docker è installato
    if ! command -v docker >/dev/null 2>&1; then
        print_warning "Docker non installato, salto controllo immagini"
        return 0
    fi
    
    declare -A docker_images=(
        ["fmriprep"]="nipreps/fmriprep:24.1.1"
        ["mriqc"]="nipreps/mriqc:24.0.2"
        ["smriprep"]="nipreps/smriprep:0.15.0"
    )
    
    for img_name in "${!docker_images[@]}"; do
        local full_image="${docker_images[$img_name]}"
        local image_repo=$(echo "$full_image" | cut -d: -f1)
        local current_tag=$(echo "$full_image" | cut -d: -f2)
        
        print_msg "Verifica $img_name ($image_repo)..."
        
        # Ottieni ultima versione da Docker Hub
        local latest=$(get_latest_version "$img_name" \
            "https://hub.docker.com/v2/repositories/$image_repo/tags" \
            "dockerhub_api")
        
        if [ -n "$latest" ] && [ "$latest" != "$current_tag" ]; then
            print_warning "AGGIORNAMENTO DOCKER: $img_name $current_tag → $latest"
            echo "docker:$img_name:$current_tag:$latest" >> updates_available.txt
            
            # Controlla se l'immagine è già scaricata localmente
            if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "${image_repo}:${current_tag}"; then
                local img_size=$(docker images --format "{{.Size}}" "${image_repo}:${current_tag}")
                print_msg "Immagine attuale installata (dimensione: $img_size)"
            fi
        elif [ -n "$latest" ]; then
            print_success "$img_name è aggiornato: $current_tag"
        else
            print_warning "Impossibile verificare $img_name"
        fi
    done
}

# Controlla aggiornamenti per software
check_software_updates() {
    print_msg "Controllo aggiornamenti software..."
    
    # Lista software da controllare (incluso fmriprep)
    local software_list=("fsl" "freesurfer" "ants" "afni" "mrtrix" "c3d" "fmriprep")
    
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
            fmriprep)
                # fMRIPrep usa GitHub releases
                latest=$(get_latest_version "$software" \
                    "https://api.github.com/repos/nipreps/fmriprep/releases/latest" \
                    "github_api")
                current="24.1.1"
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
    
    # Lista pacchetti da controllare (incluso fmriprep-docker)
    declare -A py_packages=(
        ["HD_BET"]="1.0"
        ["LST_AI"]="1.1.0"
        ["nnunet"]="1.7.1"
        ["torch"]="2.9.1"
        ["torchvision"]="0.24.1"
        ["pydeface"]="2.0.2"
        ["fmriprep-docker"]="24.1.1"
        ["nipype"]="1.8.6"
        ["pybids"]="0.16.4"
        ["templateflow"]="24.2.0"
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

# Aggiorna immagine Docker
update_docker_image() {
    local image_name=$1
    local new_tag=$2
    
    print_msg "Aggiornamento immagine Docker $image_name a versione $new_tag..."
    
    # Pull nuova immagine
    if docker pull "${image_name}:${new_tag}"; then
        print_success "Immagine ${image_name}:${new_tag} scaricata con successo"
        
        # Opzionalmente rimuovi vecchia immagine
        read -p "Rimuovere vecchia immagine? (s/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            local old_images=$(docker images "${image_name}" --format "{{.Tag}}" | grep -v "$new_tag")
            if [ -n "$old_images" ]; then
                echo "$old_images" | while read -r old_tag; do
                    print_msg "Rimozione ${image_name}:${old_tag}..."
                    docker rmi "${image_name}:${old_tag}" || true
                done
            fi
        fi
    else
        print_error "Errore durante il download di ${image_name}:${new_tag}"
        return 1
    fi
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
            docker)
                print_msg "Aggiorno immagine Docker $name da $current a $latest"
                
                # Aggiorna nello script bash
                if [ "$name" = "fmriprep" ]; then
                    sed -i "s/FMRIPREP_VERSION=\"$current\"/FMRIPREP_VERSION=\"$latest\"/" "$SCRIPT_FILE"
                    sed -i "s/nipreps\/fmriprep:${current}/nipreps\/fmriprep:${latest}/" "$SCRIPT_FILE"
                fi
                
                # Aggiorna nel JSON
                if command -v jq >/dev/null 2>&1 && [ -f "$CONFIG_FILE" ]; then
                    jq ".docker_images.${name}.current_tag = \"$latest\"" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
                    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
                fi
                
                # Chiedi se aggiornare anche l'immagine Docker
                if command -v docker >/dev/null 2>&1; then
                    read -p "Scaricare nuova immagine Docker? (s/n): " -n 1 -r
                    echo
                    if [[ $REPLY =~ ^[Ss]$ ]]; then
                        case $name in
                            fmriprep) update_docker_image "nipreps/fmriprep" "$latest" ;;
                            mriqc) update_docker_image "nipreps/mriqc" "$latest" ;;
                            smriprep) update_docker_image "nipreps/smriprep" "$latest" ;;
                        esac
                    fi
                fi
                ;;
                
            fsl|freesurfer|ants|afni|mrtrix|c3d|fmriprep)
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
                elif [ "$type" = "fmriprep" ]; then
                    # fMRIPrep è gestito via Docker, già aggiornato sopra
                    :
                fi
                
                # Aggiorna JSON
                if command -v jq >/dev/null 2>&1 && [ -f "$CONFIG_FILE" ]; then
                    jq ".software.${type}.current_version = \"$latest\"" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
                    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
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
                
                # Aggiorna JSON
                if command -v jq >/dev/null 2>&1 && [ -f "$CONFIG_FILE" ]; then
                    jq ".python_packages.\"${name}\".current_version = \"$latest\"" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
                    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
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
    echo "══════════════════════════════════════════════════════════"
    echo "  RIEPILOGO AGGIORNAMENTI"
    echo "══════════════════════════════════════════════════════════"
    cat "$updates_file" | while IFS=':' read -r type name current latest; do
        printf "%-15s %-15s %-10s → %-10s\n" "$type" "$name" "$current" "$latest"
    done
    echo "══════════════════════════════════════════════════════════"
    
    # Pulisci
    rm -f "$updates_file"
}

# Controlla dipendenze sistema
check_system_dependencies() {
    print_msg "Verifica dipendenze di sistema..."
    
    local deps=("curl" "wget" "git" "tar" "gzip" "cmake" "docker")
    
    for dep in "${deps[@]}"; do
        if command -v "$dep" >/dev/null 2>&1; then
            print_success "$dep: OK"
            
            # Mostra versione per alcuni tool importanti
            case $dep in
                docker)
                    local docker_version=$(docker --version | grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
                    print_msg "  Versione Docker: $docker_version"
                    ;;
                git)
                    local git_version=$(git --version | grep -oP '[0-9]+\.[0-9]+\.[0-9]+')
                    print_msg "  Versione Git: $git_version"
                    ;;
            esac
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
    
    # Verifica spazio Docker (se disponibile)
    if command -v docker >/dev/null 2>&1; then
        print_msg "Verifica immagini Docker..."
        local docker_images_count=$(docker images -q | wc -l)
        local docker_size=$(docker system df --format "{{.Size}}" 2>/dev/null | head -1 || echo "N/A")
        print_msg "  Immagini Docker installate: $docker_images_count"
        print_msg "  Spazio usato da Docker: $docker_size"
    fi
}

# Genera report
generate_report() {
    local report_file="version_report_$(date +%Y%m%d).md"
    
    cat > "$report_file" << EOF
# Report Aggiornamenti Neuroimaging
**Data**: $(date)
**Sistema**: $(uname -a)

## Software Neuroimaging

| Software | Versione Corrente | Ultima Versione | Stato | Note |
|----------|-------------------|-----------------|--------|------|
EOF
    
    # Verifica versioni e aggiungi al report
    for software in fsl freesurfer ants afni mrtrix c3d fmriprep; do
        print_msg "Controllo $software per report..."
        
        case $software in
            fmriprep)
                current="24.1.1"
                latest=$(get_latest_version "$software" \
                    "https://api.github.com/repos/nipreps/fmriprep/releases/latest" \
                    "github_api")
                note="Docker-based"
                ;;
            *)
                current="..."
                latest="..."
                note=""
                ;;
        esac
        
        if [ "$current" = "$latest" ] || [ -z "$latest" ]; then
            status="✓ Aggiornato"
        else
            status="⚠ Aggiornamento disponibile"
        fi
        
        echo "| $software | $current | ${latest:-N/A} | $status | $note |" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF

## Pacchetti Python

| Pacchetto | Versione Corrente | Ultima Versione | Stato |
|-----------|-------------------|-----------------|--------|
EOF
    
    for pkg in fmriprep-docker nipype pybids templateflow; do
        echo "| $pkg | ... | ... | ... |" >> "$report_file"
    done
    
    cat >> "$report_file" << EOF

## Immagini Docker

| Immagine | Tag Corrente | Ultimo Tag | Dimensione | Stato |
|----------|--------------|------------|------------|--------|
EOF
    
    if command -v docker >/dev/null 2>&1; then
        for img in "nipreps/fmriprep" "nipreps/mriqc" "nipreps/smriprep"; do
            if docker images --format "{{.Repository}}" | grep -q "$img"; then
                local tag=$(docker images "$img" --format "{{.Tag}}" | head -1)
                local size=$(docker images "$img" --format "{{.Size}}" | head -1)
                echo "| $img | $tag | ... | $size | ✓ Installata |" >> "$report_file"
            else
                echo "| $img | - | ... | - | ✗ Non installata |" >> "$report_file"
            fi
        done
    fi
    
    cat >> "$report_file" << EOF

## Dipendenze Sistema

$(check_system_dependencies 2>&1)

---
*Report generato automaticamente da update_versions.sh*
EOF
    
    print_success "Report generato: $report_file"
}

# Menu principale
show_menu() {
    echo ""
    echo "══════════════════════════════════════════════════════════"
    echo "  AGGIORNATORE VERSIONI NEUROIMAGING"
    echo "══════════════════════════════════════════════════════════"
    echo "1) Controlla aggiornamenti software"
    echo "2) Controlla aggiornamenti pacchetti Python"
    echo "3) Controlla aggiornamenti immagini Docker"
    echo "4) Verifica dipendenze sistema"
    echo "5) Aggiorna file di configurazione"
    echo "6) Genera report completo"
    echo "7) Esegui tutti i controlli"
    echo "8) Pulisci vecchie immagini Docker"
    echo "9) Esci"
    echo "══════════════════════════════════════════════════════════"
    echo -n "Scelta: "
}

# Pulisci vecchie immagini Docker
cleanup_docker_images() {
    if ! command -v docker >/dev/null 2>&1; then
        print_error "Docker non installato"
        return 1
    fi
    
    print_msg "Pulizia immagini Docker non utilizzate..."
    
    # Mostra immagini non taggate
    local dangling=$(docker images -f "dangling=true" -q | wc -l)
    print_msg "Immagini dangling trovate: $dangling"
    
    if [ "$dangling" -gt 0 ]; then
        read -p "Rimuovere immagini dangling? (s/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            docker image prune -f
            print_success "Immagini dangling rimosse"
        fi
    fi
    
    # Mostra spazio liberabile
    print_msg "Analisi spazio Docker..."
    docker system df
    
    read -p "Eseguire pulizia completa? (s/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        docker system prune -a --volumes -f
        print_success "Pulizia Docker completata"
    fi
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
                check_docker_images_updates
                ;;
            4)
                check_system_dependencies
                ;;
            5)
                update_config_file
                ;;
            6)
                generate_report
                ;;
            7)
                check_software_updates
                check_python_updates
                check_docker_images_updates
                check_system_dependencies
                update_config_file
                generate_report
                ;;
            8)
                cleanup_docker_images
                ;;
            9)
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
        check_docker_images_updates
        update_config_file
        ;;
    "--check-only")
        check_software_updates
        check_python_updates
        check_docker_images_updates
        ;;
    "--report")
        generate_report
        ;;
    "--docker-cleanup")
        cleanup_docker_images
        ;;
    *)
        main
        ;;
esac
