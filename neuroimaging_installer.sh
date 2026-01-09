#!/bin/bash

# ============================================================================
# NEUROIMAGING ENVIRONMENT INSTALLER - VERSIONE COMPLETA CON FMRIPREP
# ============================================================================

set -e  # Exit on error
trap 'cleanup_error' ERR

# Colori per output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# ============================================================================
# CONFIGURAZIONE
# ============================================================================

# Directory
INSTALL_DIR="${NEUROIMAGING_DIR:-$HOME/neuroimaging}"
CONDA_DIR="${INSTALL_DIR}/micromamba"
LOG_DIR="${INSTALL_DIR}/logs"
CONFIG_DIR="${INSTALL_DIR}/config"
BACKUP_DIR="${INSTALL_DIR}/backup"

# Versioni software
FSL_VERSION="6.0.7.1"
FREESURFER_VERSION="7.4.1"
ANTs_VERSION="2.5.3"
AFNI_VERSION="latest"
MRTRIX_VERSION="3.0.3"
SPM_VERSION="12"
MINICONDA_VERSION="latest"
C3D_VERSION="1.4.0"
CONN_VERSION="22.a"
FMRIPREP_VERSION="24.1.1"
MRIQC_VERSION="24.0.2"
SMRIPREP_VERSION="0.15.0"

# URL download
declare -A DOWNLOAD_URLS=(
    ["fsl"]="https://fsl.fmrib.ox.ac.uk/fsldownloads/fsl-${FSL_VERSION}-centos7_64.tar.gz"
    ["freesurfer"]="https://surfer.nmr.mgh.harvard.edu/pub/dist/freesurfer/${FREESURFER_VERSION}/freesurfer-linux-ubuntu22_amd64-${FREESURFER_VERSION}.tar.gz"
    ["ants"]="https://github.com/ANTsX/ANTs/releases/download/v${ANTs_VERSION}/ants-${ANTs_VERSION}-Linux_x86_64.tar.gz"
    ["c3d"]="https://downloads.sourceforge.net/project/c3d/c3d/c3d-${C3D_VERSION}/c3d-${C3D_VERSION}-Linux-x86_64.tar.gz"
)

# Flag
SILENT_MODE=false
INSTALL_ALL=false
SKIP_DEPENDENCIES=false
FORCE_INSTALL=false
CREATE_CONDA_ENV=false
EXPORT_CONTAINER=false

# Software da installare
declare -A INSTALL_SOFTWARE=(
    ["fsl"]=false
    ["freesurfer"]=false
    ["ants"]=false
    ["afni"]=false
    ["mrtrix"]=false
    ["spm"]=false
    ["c3d"]=false
    ["conn"]=false
    ["micromamba"]=false
    ["fmriprep"]=false
    ["mriqc"]=false
    ["smriprep"]=false
)

# ============================================================================
# FUNZIONI UTILITY
# ============================================================================

print_header() {
    echo -e "\n${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ${BOLD}$1${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}\n"
}

print_message() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[✓]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_debug() { [ "$DEBUG" = "true" ] && echo -e "${MAGENTA}[DEBUG]${NC} $1"; }

# Funzione per prompt silenzioso
prompt_user() {
    if [ "$SILENT_MODE" = true ]; then
        echo "$2"  # Ritorna valore di default
    else
        read -p "$1 " response
        echo "$response"
    fi
}

# Controllo comandi
command_exists() { command -v "$1" >/dev/null 2>&1; }

# Creazione directory
create_dirs() {
    mkdir -p "$INSTALL_DIR" "$LOG_DIR" "$CONFIG_DIR" "$BACKUP_DIR"
    mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/lib" "$INSTALL_DIR/share"
}

# Backup configurazioni
backup_config() {
    local config_file="$1"
    if [ -f "$config_file" ]; then
        cp "$config_file" "${BACKUP_DIR}/$(basename "$config_file").bak.$(date +%Y%m%d_%H%M%S)"
    fi
}

# ============================================================================
# CONTROLLO VERSIONI ONLINE
# ============================================================================

check_online_version() {
    local software=$1
    local current_version=$2
    
    print_message "Controllo versione online per ${BOLD}$software${NC}..."
    
    case $software in
        fsl)
            latest=$(curl -s https://fsl.fmrib.ox.ac.uk/fsldownloads/ | \
                    grep -oP 'fsl-\K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1)
            ;;
        freesurfer)
            latest=$(curl -s https://surfer.nmr.mgh.harvard.edu/pub/dist/freesurfer/ | \
                    grep -oP '[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1)
            ;;
        ants)
            latest=$(curl -s https://api.github.com/repos/ANTsX/ANTs/releases/latest | \
                    grep -oP '"tag_name": "v?\K[0-9.]+')
            ;;
        mrtrix)
            latest=$(curl -s https://api.github.com/repos/MRtrix3/mrtrix3/releases/latest | \
                    grep -oP '"tag_name": "v?\K[0-9.]+')
            ;;
        afni)
            latest=$(curl -s https://afni.nimh.nih.gov/pub/dist/tgz/ | \
                    grep -oP 'linux_openmp_64\.\K[0-9]+\.[0-9]+\.[0-9]+' | sort -V | tail -1)
            ;;
        *)
            print_warning "Controllo versione non implementato per $software"
            return 1
            ;;
    esac
    
    if [ -n "$latest" ] && [ "$latest" != "$current_version" ]; then
        print_warning "Nuova versione disponibile: $current_version → $latest"
        if [ "$SILENT_MODE" = false ]; then
            read -p "Aggiornare? (s/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Ss]$ ]]; then
                eval "${software}_version=\"$latest\""
                DOWNLOAD_URLS["$software"]=$(update_download_url "$software" "$latest")
                return 0
            fi
        fi
    elif [ -n "$latest" ]; then
        print_success "Versione aggiornata: $current_version"
    fi
    
    return 1
}

# ============================================================================
# INSTALLAZIONE SOFTWARE
# ============================================================================

install_system_dependencies() {
    print_header "INSTALLAZIONE DIPENDENZE DI SISTEMA"
    
    if command_exists apt-get; then
        sudo apt-get update
        sudo apt-get install -y \
            wget curl git build-essential unzip tcsh \
            python3 python3-pip python3-dev python3-venv \
            libgl1-mesa-dev libglu1-mesa-dev libglw1-mesa \
            libgomp1 libjpeg62-dev libxml2-dev libxslt1-dev \
            libeigen3-dev zlib1g-dev libqt5core5a libqt5gui5 \
            libqt5widgets5 libqt5opengl5 libqt5svg5-dev \
            libopenblas-dev libfftw3-dev libnifti-dev \
            libtool automake autoconf cmake g++ gcc \
            perl tcsh xfonts-base python-is-python3 \
            gnome-tweak-tool libjpeg62 xvfb xterm vim \
            netpbm gnome-tweak-tool libxp6
        
    elif command_exists yum; then
        sudo yum install -y \
            wget curl git gcc-c++ make unzip tcsh \
            python3 python3-pip python3-devel \
            mesa-libGL-devel mesa-libGLU-devel \
            libjpeg-turbo-devel libxml2-devel libxslt-devel \
            eigen3-devel zlib-devel qt5-qtbase-devel \
            qt5-qtsvg-devel openblas-devel fftw-devel \
            libtool automake autoconf cmake gcc perl \
            libXp netpbm-progs
        
    elif command_exists dnf; then
        sudo dnf install -y \
            wget curl git gcc-c++ make unzip tcsh \
            python3 python3-pip python3-devel \
            mesa-libGL-devel mesa-libGLU-devel \
            libjpeg-turbo-devel libxml2-devel libxslt-devel \
            eigen3-devel zlib-devel qt5-qtbase-devel \
            qt5-qtsvg-devel openblas-devel fftw-devel \
            libtool automake autoconf cmake gcc perl \
            libXp netpbm-progs
    fi
    
    print_success "Dipendenze di sistema installate"
}

install_micromamba() {
    print_header "INSTALLAZIONE MICROMAMBA"
    
    local mamba_url="https://micro.mamba.pm/api/micromamba/linux-64/latest"
    
    mkdir -p "$CONDA_DIR"
    cd "$CONDA_DIR"
    
    print_message "Download micromamba..."
    curl -Ls "$mamba_url" | tar -xj bin/micromamba
    
    # Inizializza shell
    ./bin/micromamba shell init -p "${CONDA_DIR}/envs" -s bash
    
    # Configura ambiente
    echo "# Micromamba Configuration" >> ~/.bashrc
    echo "export MAMBA_ROOT_PREFIX=\"${CONDA_DIR}/envs\"" >> ~/.bashrc
    echo "export MAMBA_EXE=\"${CONDA_DIR}/bin/micromamba\"" >> ~/.bashrc
    echo 'eval "$(${MAMBA_EXE} shell hook --shell bash)"' >> ~/.bashrc
    
    # Crea ambiente neuroimaging
    if [ -f "${CONFIG_DIR}/neuroimaging_env.yml" ]; then
        print_message "Creazione ambiente da YAML..."
        "${CONDA_DIR}/bin/micromamba" create -f "${CONFIG_DIR}/neuroimaging_env.yml" -y
    else
        print_message "Creazione ambiente neuroimaging di base..."
        "${CONDA_DIR}/bin/micromamba" create -n neuroimaging \
            python=3.10 \
            numpy scipy pandas matplotlib seaborn \
            scikit-learn scikit-image jupyter jupyterlab \
            nibabel dipy nilearn nipype nipy \
            ipython ipykernel ipywidgets \
            pip -y
    fi
    
    print_success "Micromamba installato in $CONDA_DIR"
}

install_fsl() {
    print_header "INSTALLAZIONE FSL"
    
    local fsl_dir="${INSTALL_DIR}/fsl"
    local temp_file="/tmp/fsl_${FSL_VERSION}.tar.gz"
    
    # Check se già installato
    if [ -d "$fsl_dir" ] && [ "$FORCE_INSTALL" = false ]; then
        print_warning "FSL già installato in $fsl_dir"
        return 0
    fi
    
    check_online_version "fsl" "$FSL_VERSION"
    
    print_message "Download FSL ${FSL_VERSION}..."
    wget --progress=bar:force "${DOWNLOAD_URLS[fsl]}" -O "$temp_file"
    
    print_message "Estrazione..."
    mkdir -p "$fsl_dir"
    tar -xzf "$temp_file" -C "$fsl_dir" --strip-components=1
    
    # Setup environment
    backup_config ~/.bashrc
    echo "# FSL Configuration" >> ~/.bashrc
    echo "export FSLDIR=\"$fsl_dir\"" >> ~/.bashrc
    echo "export PATH=\"\${FSLDIR}/bin:\${PATH}\"" >> ~/.bashrc
    echo "source \${FSLDIR}/etc/fslconf/fsl.sh" >> ~/.bashrc
    echo "export FSLOUTPUTTYPE=NIFTI_GZ" >> ~/.bashrc
    
    # Verifica installazione
    if [ -f "${fsl_dir}/bin/fsl" ]; then
        print_success "FSL installato in $fsl_dir"
    else
        print_error "Installazione FSL fallita"
        return 1
    fi
    
    rm -f "$temp_file"
}

install_freesurfer() {
    print_header "INSTALLAZIONE FREESURFER"
    
    local fs_dir="${INSTALL_DIR}/freesurfer"
    local license_file="${CONFIG_DIR}/license.txt"
    
    if [ -d "$fs_dir" ] && [ "$FORCE_INSTALL" = false ]; then
        print_warning "FreeSurfer già installato in $fs_dir"
        return 0
    fi
    
    check_online_version "freesurfer" "$FREESURFER_VERSION"
    
    # Richiedi licenza
    if [ ! -f "$license_file" ] && [ "$SILENT_MODE" = false ]; then
        print_warning "FreeSurfer richiede una licenza"
        echo "Ottienila da: https://surfer.nmr.mgh.harvard.edu/registration.html"
        read -p "Incolla il contenuto della licenza (Ctrl+D per terminare):" license_content
        echo "$license_content" > "$license_file"
    elif [ "$SILENT_MODE" = true ]; then
        print_warning "Modalità silenziosa: assicurati di avere il file ${license_file}"
    fi
    
    # Download
    local temp_file="/tmp/freesurfer_${FREESURFER_VERSION}.tar.gz"
    print_message "Download FreeSurfer ${FREESURFER_VERSION}..."
    wget --progress=bar:force "${DOWNLOAD_URLS[freesurfer]}" -O "$temp_file"
    
    # Estrazione
    mkdir -p "$fs_dir"
    tar -xzf "$temp_file" -C "$fs_dir" --strip-components=1
    
    # Configurazione
    backup_config ~/.bashrc
    echo "# FreeSurfer Configuration" >> ~/.bashrc
    echo "export FREESURFER_HOME=\"$fs_dir\"" >> ~/.bashrc
    echo "export FS_LICENSE=\"$license_file\"" >> ~/.bashrc
    echo "source \${FREESURFER_HOME}/SetUpFreeSurfer.sh" >> ~/.bashrc
    
    # Setup subject directory
    export SUBJECTS_DIR="${INSTALL_DIR}/freesurfer_subjects"
    mkdir -p "$SUBJECTS_DIR"
    echo "export SUBJECTS_DIR=\"$SUBJECTS_DIR\"" >> ~/.bashrc
    
    print_success "FreeSurfer installato in $fs_dir"
    rm -f "$temp_file"
}

install_ants() {
    print_header "INSTALLAZIONE ANTs"
    
    local ants_dir="${INSTALL_DIR}/ants"
    
    check_online_version "ants" "$ANTs_VERSION"
    
    # Download
    local temp_file="/tmp/ants_${ANTs_VERSION}.tar.gz"
    print_message "Download ANTs ${ANTs_VERSION}..."
    wget --progress=bar:force "${DOWNLOAD_URLS[ants]}" -O "$temp_file"
    
    # Estrazione
    mkdir -p "$ants_dir"
    tar -xzf "$temp_file" -C "$ants_dir" --strip-components=1
    
    # Configurazione
    backup_config ~/.bashrc
    echo "# ANTs Configuration" >> ~/.bashrc
    echo "export ANTSPATH=\"$ants_dir\"" >> ~/.bashrc
    echo "export PATH=\"\${ANTSPATH}:\${PATH}\"" >> ~/.bashrc
    
    # Verifica
    if [ -f "${ants_dir}/antsRegistration" ]; then
        print_success "ANTs installato in $ants_dir"
    else
        print_error "Installazione ANTs fallita"
        return 1
    fi
    
    rm -f "$temp_file"
}

install_afni() {
    print_header "INSTALLAZIONE AFNI"
    
    check_online_version "afni" "$AFNI_VERSION"
    
    # Installa dipendenze specifiche AFNI
    print_message "Installazione dipendenze AFNI..."
    if command_exists apt-get; then
        sudo apt-get install -y \
            libxp6 libxpm4 libxmu6 libxt6 \
            libmotif-common libmotif-dev \
            libglu1-mesa-dev libglw1-mesa-dev \
            libxm4 libxpm-dev libxt-dev \
            libxi6 libxinerama1
    fi
    
    # Installa R (opzionale ma utile)
    if ! command_exists R; then
        print_message "Installazione R per AFNI..."
        if command_exists apt-get; then
            sudo apt-get install -y r-base r-base-dev
        fi
    fi
    
    # Installa AFNI
    print_message "Installazione AFNI..."
    cd /tmp
    curl -O https://afni.nimh.nih.gov/pub/dist/bin/linux_openmp_64/@update.afni.binaries
    tcsh @update.afni.binaries -package linux_openmp_64 -do_extras -bindir "${INSTALL_DIR}/abin"
    
    # Configurazione
    backup_config ~/.bashrc
    echo "# AFNI Configuration" >> ~/.bashrc
    echo "export PATH=\"${INSTALL_DIR}/abin:\$PATH\"" >> ~/.bashrc
    echo "export AFNI_PLUGINPATH=\"${INSTALL_DIR}/abin\"" >> ~/.bashrc
    
    print_success "AFNI installato"
}

install_mrtrix() {
    print_header "INSTALLAZIONE MRtrix3"
    
    local mrtrix_dir="${INSTALL_DIR}/mrtrix3"
    
    check_online_version "mrtrix" "$MRTRIX_VERSION"
    
    # Clone o update
    if [ -d "$mrtrix_dir" ]; then
        print_message "Aggiornamento MRtrix3..."
        cd "$mrtrix_dir"
        git pull
    else
        print_message "Clone MRtrix3..."
        git clone https://github.com/MRtrix3/mrtrix3.git "$mrtrix_dir"
        cd "$mrtrix_dir"
    fi
    
    # Configura e compila
    print_message "Configurazione e compilazione..."
    ./configure
    ./build -parallel $(nproc)
    
    # Configurazione
    backup_config ~/.bashrc
    echo "# MRtrix3 Configuration" >> ~/.bashrc
    echo "export PATH=\"${mrtrix_dir}/bin:\$PATH\"" >> ~/.bashrc
    
    print_success "MRtrix3 installato in $mrtrix_dir"
}

install_c3d() {
    print_header "INSTALLAZIONE Convert3D"
    
    local c3d_dir="${INSTALL_DIR}/c3d"
    local temp_file="/tmp/c3d_${C3D_VERSION}.tar.gz"
    
    print_message "Download Convert3D ${C3D_VERSION}..."
    wget --progress=bar:force "${DOWNLOAD_URLS[c3d]}" -O "$temp_file"
    
    mkdir -p "$c3d_dir"
    tar -xzf "$temp_file" -C "$c3d_dir" --strip-components=1
    
    backup_config ~/.bashrc
    echo "# Convert3D Configuration" >> ~/.bashrc
    echo "export PATH=\"${c3d_dir}/bin:\$PATH\"" >> ~/.bashrc
    
    print_success "Convert3D installato in $c3d_dir"
    rm -f "$temp_file"
}

install_conn() {
    print_header "INSTALLAZIONE CONN"
    
    local conn_dir="${INSTALL_DIR}/conn"
    local conn_url="https://www.linode.com/static/images/products/one-click-apps/conn_standalone.zip"
    
    print_message "Download CONN..."
    wget --progress=bar:force "$conn_url" -O /tmp/conn.zip
    
    mkdir -p "$conn_dir"
    unzip /tmp/conn.zip -d "$conn_dir"
    
    # Richiede MATLAB
    if command_exists matlab; then
        print_message "Aggiunta CONN a MATLAB path..."
        echo "addpath('$conn_dir'); savepath;" > /tmp/conn_setup.m
        matlab -batch "run('/tmp/conn_setup.m')"
    fi
    
    print_success "CONN installato in $conn_dir"
    rm -f /tmp/conn.zip
}

# ============================================================================
# INSTALLAZIONE DOCKER
# ============================================================================

install_docker() {
    print_header "INSTALLAZIONE DOCKER"
    
    if command_exists apt-get; then
        # Ubuntu/Debian
        print_message "Installazione Docker su Ubuntu/Debian..."
        
        # Rimuovi versioni vecchie
        sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
        
        # Installa dipendenze
        sudo apt-get update
        sudo apt-get install -y \
            ca-certificates \
            curl \
            gnupg \
            lsb-release
        
        # Aggiungi repository Docker
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
            sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
            $(lsb_release -cs) stable" | \
            sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Installa Docker
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        
    elif command_exists yum; then
        # CentOS/RHEL
        print_message "Installazione Docker su CentOS/RHEL..."
        sudo yum install -y yum-utils
        sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        
    elif command_exists dnf; then
        # Fedora
        print_message "Installazione Docker su Fedora..."
        sudo dnf -y install dnf-plugins-core
        sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
        sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi
    
    # Avvia e abilita Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Verifica installazione
    if docker --version >/dev/null 2>&1; then
        print_success "Docker installato correttamente"
        docker --version
    else
        print_error "Installazione Docker fallita"
        return 1
    fi
}

# ============================================================================
# INSTALLAZIONE FMRIPREP-DOCKER
# ============================================================================

install_fmriprep_docker() {
    print_header "CONFIGURAZIONE FMRIPREP-DOCKER"
    
    # Verifica Docker
    if ! command_exists docker; then
        print_error "Docker non trovato. Installazione Docker..."
        install_docker
    fi
    
    # Verifica che Docker sia in esecuzione
    if ! docker info >/dev/null 2>&1; then
        print_warning "Docker non è in esecuzione. Avvio Docker..."
        sudo systemctl start docker
        sleep 3
        if ! docker info >/dev/null 2>&1; then
            print_error "Docker non può essere avviato. Avvialo manualmente con: sudo systemctl start docker"
            return 1
        fi
    fi
    
    # Aggiungi utente al gruppo docker se necessario
    if ! groups | grep -q docker; then
        print_warning "Aggiunta utente al gruppo docker..."
        sudo usermod -aG docker "$USER"
        print_warning "IMPORTANTE: Riavvia la sessione per applicare le modifiche al gruppo docker"
        print_warning "Oppure esegui: newgrp docker"
    fi
    
    # Installa fmriprep-docker tramite pip nell'ambiente conda
    print_message "Installazione fmriprep-docker wrapper..."
    if [ -f "${CONDA_DIR}/bin/micromamba" ]; then
        "${CONDA_DIR}/bin/micromamba" run -n neuroimaging pip install fmriprep-docker
    elif command_exists conda; then
        conda run -n neuroimaging pip install fmriprep-docker
    else
        pip install --user fmriprep-docker
    fi
    
    # Pre-download dell'immagine Docker di fMRIPrep (opzionale ma consigliato)
    local fmriprep_version="${FMRIPREP_VERSION}"
    
    if [ "$SILENT_MODE" = false ]; then
        read -p "Scaricare l'immagine Docker di fMRIPrep ${fmriprep_version}? (s/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            print_message "Download immagine fMRIPrep ${fmriprep_version}... (potrebbe richiedere tempo)"
            docker pull nipreps/fmriprep:${fmriprep_version}
            print_success "Immagine fMRIPrep scaricata"
        fi
    fi
    
    # Crea directory per TemplateFlow
    local templateflow_dir="${INSTALL_DIR}/templateflow"
    mkdir -p "$templateflow_dir"
    
    # Configura variabili d'ambiente
    backup_config ~/.bashrc
    echo "" >> ~/.bashrc
    echo "# fMRIPrep Configuration" >> ~/.bashrc
    echo "export TEMPLATEFLOW_HOME=\"${templateflow_dir}\"" >> ~/.bashrc
    echo "export FMRIPREP_VERSION=\"${fmriprep_version}\"" >> ~/.bashrc
    
    # Crea script helper per fMRIPrep
    create_fmriprep_helper_script
    
    print_success "fMRIPrep-Docker configurato"
    print_message "Versione: ${fmriprep_version}"
    print_message "TemplateFlow: ${templateflow_dir}"
    print_message "Script helper: ${INSTALL_DIR}/bin/run_fmriprep.sh"
}

install_mriqc_docker() {
    print_header "CONFIGURAZIONE MRIQC-DOCKER"
    
    # Verifica Docker
    if ! command_exists docker; then
        print_error "Docker non trovato. Installazione Docker..."
        install_docker
    fi
    
    # Verifica che Docker sia in esecuzione
    if ! docker info >/dev/null 2>&1; then
        print_warning "Docker non è in esecuzione. Avvio Docker..."
        sudo systemctl start docker
        sleep 3
    fi
    
    # Pre-download dell'immagine Docker di MRIQC
    local mriqc_version="${MRIQC_VERSION}"
    
    if [ "$SILENT_MODE" = false ]; then
        read -p "Scaricare l'immagine Docker di MRIQC ${mriqc_version}? (s/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            print_message "Download immagine MRIQC ${mriqc_version}..."
            docker pull nipreps/mriqc:${mriqc_version}
            print_success "Immagine MRIQC scaricata"
        fi
    fi
    
    # Configura variabili d'ambiente
    backup_config ~/.bashrc
    echo "" >> ~/.bashrc
    echo "# MRIQC Configuration" >> ~/.bashrc
    echo "export MRIQC_VERSION=\"${mriqc_version}\"" >> ~/.bashrc
    
    # Crea script helper per MRIQC
    create_mriqc_helper_script
    
    print_success "MRIQC-Docker configurato"
    print_message "Versione: ${mriqc_version}"
    print_message "Script helper: ${INSTALL_DIR}/bin/run_mriqc.sh"
}

install_smriprep_docker() {
    print_header "CONFIGURAZIONE SMRIPREP-DOCKER"
    
    # Verifica Docker
    if ! command_exists docker; then
        print_error "Docker non trovato. Installazione Docker..."
        install_docker
    fi
    
    # Verifica che Docker sia in esecuzione
    if ! docker info >/dev/null 2>&1; then
        print_warning "Docker non è in esecuzione. Avvio Docker..."
        sudo systemctl start docker
        sleep 3
    fi
    
    # Pre-download dell'immagine Docker di sMRIPrep
    local smriprep_version="${SMRIPREP_VERSION}"
    
    if [ "$SILENT_MODE" = false ]; then
        read -p "Scaricare l'immagine Docker di sMRIPrep ${smriprep_version}? (s/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            print_message "Download immagine sMRIPrep ${smriprep_version}..."
            docker pull nipreps/smriprep:${smriprep_version}
            print_success "Immagine sMRIPrep scaricata"
        fi
    fi
    
    # Crea directory per TemplateFlow se non esiste
    local templateflow_dir="${INSTALL_DIR}/templateflow"
    mkdir -p "$templateflow_dir"
    
    # Configura variabili d'ambiente
    backup_config ~/.bashrc
    echo "" >> ~/.bashrc
    echo "# sMRIPrep Configuration" >> ~/.bashrc
    echo "export SMRIPREP_VERSION=\"${smriprep_version}\"" >> ~/.bashrc
    
    # Crea script helper per sMRIPrep
    create_smriprep_helper_script
    
    print_success "sMRIPrep-Docker configurato"
    print_message "Versione: ${smriprep_version}"
    print_message "Script helper: ${INSTALL_DIR}/bin/run_smriprep.sh"
}

create_fmriprep_helper_script() {
    local helper_script="${INSTALL_DIR}/bin/run_fmriprep.sh"
    
    mkdir -p "${INSTALL_DIR}/bin"
    
    cat > "$helper_script" << 'FMRIPREP_SCRIPT'
#!/bin/bash

# ============================================================================
# FMRIPREP DOCKER HELPER SCRIPT
# ============================================================================

set -e

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_usage() {
    cat << EOF
Uso: $(basename "$0") [opzioni]

Script helper per eseguire fMRIPrep con Docker

Opzioni:
    -b, --bids-dir DIR          Directory BIDS input (richiesto)
    -o, --output-dir DIR        Directory output (richiesto)
    -p, --participant-label ID  Partecipante da processare (opzionale)
    -w, --work-dir DIR          Directory di lavoro (default: ./work)
    -f, --fs-license FILE       File licenza FreeSurfer
    -v, --version VERSION       Versione fMRIPrep (default: da \$FMRIPREP_VERSION)
    --skip-bids-validation      Salta validazione BIDS
    --fs-no-reconall            Salta ricostruzione FreeSurfer
    --use-aroma                 Usa ICA-AROMA per denoising
    --mem MB                    Memoria massima (default: 16000)
    --n-cpus N                  Numero CPU (default: auto)
    -h, --help                  Mostra questo messaggio

Esempio:
    $(basename "$0") -b /data/bids -o /data/derivatives -p sub-01

EOF
}

# Valori di default
BIDS_DIR=""
OUTPUT_DIR=""
PARTICIPANT=""
WORK_DIR="./work"
FS_LICENSE="${HOME}/neuroimaging/config/license.txt"
FMRIPREP_VERSION="${FMRIPREP_VERSION:-24.1.1}"
SKIP_BIDS_VALIDATION=""
FS_NO_RECONALL=""
USE_AROMA=""
MEM_MB=16000
N_CPUS=$(nproc)

# Parsing argomenti
while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--bids-dir)
            BIDS_DIR="$2"
            shift 2
            ;;
        -o|--output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -p|--participant-label)
            PARTICIPANT="$2"
            shift 2
            ;;
        -w|--work-dir)
            WORK_DIR="$2"
            shift 2
            ;;
        -f|--fs-license)
            FS_LICENSE="$2"
            shift 2
            ;;
        -v|--version)
            FMRIPREP_VERSION="$2"
            shift 2
            ;;
        --skip-bids-validation)
            SKIP_BIDS_VALIDATION="--skip-bids-validation"
            shift
            ;;
        --fs-no-reconall)
            FS_NO_RECONALL="--fs-no-reconall"
            shift
            ;;
        --use-aroma)
            USE_AROMA="--use-aroma"
            shift
            ;;
        --mem)
            MEM_MB="$2"
            shift 2
            ;;
        --n-cpus)
            N_CPUS="$2"
            shift 2
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo -e "${RED}Errore: opzione sconosciuta $1${NC}"
            print_usage
            exit 1
            ;;
    esac
done

# Verifica parametri obbligatori
if [ -z "$BIDS_DIR" ] || [ -z "$OUTPUT_DIR" ]; then
    echo -e "${RED}Errore: --bids-dir e --output-dir sono obbligatori${NC}"
    print_usage
    exit 1
fi

# Verifica esistenza directory
if [ ! -d "$BIDS_DIR" ]; then
    echo -e "${RED}Errore: BIDS directory non trovata: $BIDS_DIR${NC}"
    exit 1
fi

# Verifica licenza FreeSurfer
if [ ! -f "$FS_LICENSE" ]; then
    echo -e "${YELLOW}Warning: Licenza FreeSurfer non trovata in $FS_LICENSE${NC}"
    echo "Ottienila da: https://surfer.nmr.mgh.harvard.edu/registration.html"
    read -p "Inserisci il percorso alla licenza FreeSurfer: " FS_LICENSE
    if [ ! -f "$FS_LICENSE" ]; then
        echo -e "${RED}Errore: Licenza non valida${NC}"
        exit 1
    fi
fi

# Crea directory output e work se non esistono
mkdir -p "$OUTPUT_DIR"
mkdir -p "$WORK_DIR"

# Converti path relativi in assoluti
BIDS_DIR=$(realpath "$BIDS_DIR")
OUTPUT_DIR=$(realpath "$OUTPUT_DIR")
WORK_DIR=$(realpath "$WORK_DIR")
FS_LICENSE=$(realpath "$FS_LICENSE")

# Costruisci comando
echo -e "${BLUE}=== Configurazione fMRIPrep ===${NC}"
echo "BIDS Directory: $BIDS_DIR"
echo "Output Directory: $OUTPUT_DIR"
echo "Work Directory: $WORK_DIR"
echo "Participant: ${PARTICIPANT:-all}"
echo "Version: $FMRIPREP_VERSION"
echo "Memory: ${MEM_MB} MB"
echo "CPUs: $N_CPUS"
echo ""

# Comando base
CMD="docker run --rm -it \
    -v ${BIDS_DIR}:/data:ro \
    -v ${OUTPUT_DIR}:/out \
    -v ${WORK_DIR}:/work \
    -v ${FS_LICENSE}:/opt/freesurfer/license.txt:ro \
    -v ${TEMPLATEFLOW_HOME:-$HOME/.cache/templateflow}:/home/fmriprep/.cache/templateflow \
    nipreps/fmriprep:${FMRIPREP_VERSION} \
    /data /out participant \
    --work-dir /work \
    --mem-mb ${MEM_MB} \
    --n-cpus ${N_CPUS} \
    --output-spaces MNI152NLin2009cAsym:res-2 anat fsnative \
    --write-graph --verbose \
    ${SKIP_BIDS_VALIDATION} \
    ${FS_NO_RECONALL} \
    ${USE_AROMA}"

# Aggiungi partecipante se specificato
if [ -n "$PARTICIPANT" ]; then
    CMD="$CMD --participant-label $PARTICIPANT"
fi

echo -e "${GREEN}Esecuzione fMRIPrep...${NC}"
echo "$CMD"
echo ""

# Esegui
eval $CMD

echo -e "${GREEN}✓ fMRIPrep completato!${NC}"
FMRIPREP_SCRIPT
    
    chmod +x "$helper_script"
    
    print_success "Script helper creato: $helper_script"
}

create_mriqc_helper_script() {
    local helper_script="${INSTALL_DIR}/bin/run_mriqc.sh"
    
    mkdir -p "${INSTALL_DIR}/bin"
    
    cat > "$helper_script" << 'MRIQC_SCRIPT'
#!/bin/bash

# ============================================================================
# MRIQC DOCKER HELPER SCRIPT
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_usage() {
    cat << EOF
Uso: $(basename "$0") [opzioni]

Script helper per eseguire MRIQC con Docker

Opzioni:
    -b, --bids-dir DIR          Directory BIDS input (richiesto)
    -o, --output-dir DIR        Directory output (richiesto)
    -p, --participant-label ID  Partecipante da processare (opzionale)
    -w, --work-dir DIR          Directory di lavoro (default: ./work)
    -v, --version VERSION       Versione MRIQC (default: da \$MRIQC_VERSION)
    --modality TYPE             Modalità: T1w, bold, T2w (default: tutte)
    --mem MB                    Memoria massima (default: 16000)
    --n-cpus N                  Numero CPU (default: auto)
    -h, --help                  Mostra questo messaggio

Esempio:
    $(basename "$0") -b /data/bids -o /data/mriqc_out -p sub-01

EOF
}

BIDS_DIR=""
OUTPUT_DIR=""
PARTICIPANT=""
WORK_DIR="./work"
MRIQC_VERSION="${MRIQC_VERSION:-24.0.2}"
MODALITY=""
MEM_MB=16000
N_CPUS=$(nproc)

while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--bids-dir) BIDS_DIR="$2"; shift 2 ;;
        -o|--output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        -p|--participant-label) PARTICIPANT="$2"; shift 2 ;;
        -w|--work-dir) WORK_DIR="$2"; shift 2 ;;
        -v|--version) MRIQC_VERSION="$2"; shift 2 ;;
        --modality) MODALITY="--modality $2"; shift 2 ;;
        --mem) MEM_MB="$2"; shift 2 ;;
        --n-cpus) N_CPUS="$2"; shift 2 ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo -e "${RED}Errore: opzione sconosciuta $1${NC}"; print_usage; exit 1 ;;
    esac
done

if [ -z "$BIDS_DIR" ] || [ -z "$OUTPUT_DIR" ]; then
    echo -e "${RED}Errore: --bids-dir e --output-dir sono obbligatori${NC}"
    print_usage
    exit 1
fi

if [ ! -d "$BIDS_DIR" ]; then
    echo -e "${RED}Errore: BIDS directory non trovata: $BIDS_DIR${NC}"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
mkdir -p "$WORK_DIR"

BIDS_DIR=$(realpath "$BIDS_DIR")
OUTPUT_DIR=$(realpath "$OUTPUT_DIR")
WORK_DIR=$(realpath "$WORK_DIR")

echo -e "${BLUE}=== Configurazione MRIQC ===${NC}"
echo "BIDS Directory: $BIDS_DIR"
echo "Output Directory: $OUTPUT_DIR"
echo "Work Directory: $WORK_DIR"
echo "Participant: ${PARTICIPANT:-all}"
echo "Version: $MRIQC_VERSION"
echo ""

CMD="docker run --rm -it \
    -v ${BIDS_DIR}:/data:ro \
    -v ${OUTPUT_DIR}:/out \
    -v ${WORK_DIR}:/work \
    nipreps/mriqc:${MRIQC_VERSION} \
    /data /out participant \
    --work-dir /work \
    --mem-gb $(($MEM_MB / 1000)) \
    --n-cpus ${N_CPUS} \
    --verbose-reports \
    ${MODALITY}"

if [ -n "$PARTICIPANT" ]; then
    CMD="$CMD --participant-label $PARTICIPANT"
fi

echo -e "${GREEN}Esecuzione MRIQC...${NC}"
echo "$CMD"
echo ""

eval $CMD

echo -e "${GREEN}✓ MRIQC completato!${NC}"
echo -e "${BLUE}Report disponibile in: ${OUTPUT_DIR}${NC}"
MRIQC_SCRIPT
    
    chmod +x "$helper_script"
    print_success "Script MRIQC helper creato: $helper_script"
}

create_smriprep_helper_script() {
    local helper_script="${INSTALL_DIR}/bin/run_smriprep.sh"
    
    mkdir -p "${INSTALL_DIR}/bin"
    
    cat > "$helper_script" << 'SMRIPREP_SCRIPT'
#!/bin/bash

# ============================================================================
# SMRIPREP DOCKER HELPER SCRIPT
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_usage() {
    cat << EOF
Uso: $(basename "$0") [opzioni]

Script helper per eseguire sMRIPrep con Docker

Opzioni:
    -b, --bids-dir DIR          Directory BIDS input (richiesto)
    -o, --output-dir DIR        Directory output (richiesto)
    -p, --participant-label ID  Partecipante da processare (opzionale)
    -w, --work-dir DIR          Directory di lavoro (default: ./work)
    -f, --fs-license FILE       File licenza FreeSurfer
    -v, --version VERSION       Versione sMRIPrep (default: da \$SMRIPREP_VERSION)
    --fs-no-reconall            Salta ricostruzione FreeSurfer
    --mem MB                    Memoria massima (default: 16000)
    --n-cpus N                  Numero CPU (default: auto)
    -h, --help                  Mostra questo messaggio

Esempio:
    $(basename "$0") -b /data/bids -o /data/derivatives -p sub-01

EOF
}

BIDS_DIR=""
OUTPUT_DIR=""
PARTICIPANT=""
WORK_DIR="./work"
FS_LICENSE="${HOME}/neuroimaging/config/license.txt"
SMRIPREP_VERSION="${SMRIPREP_VERSION:-0.15.0}"
FS_NO_RECONALL=""
MEM_MB=16000
N_CPUS=$(nproc)

while [[ $# -gt 0 ]]; do
    case $1 in
        -b|--bids-dir) BIDS_DIR="$2"; shift 2 ;;
        -o|--output-dir) OUTPUT_DIR="$2"; shift 2 ;;
        -p|--participant-label) PARTICIPANT="$2"; shift 2 ;;
        -w|--work-dir) WORK_DIR="$2"; shift 2 ;;
        -f|--fs-license) FS_LICENSE="$2"; shift 2 ;;
        -v|--version) SMRIPREP_VERSION="$2"; shift 2 ;;
        --fs-no-reconall) FS_NO_RECONALL="--fs-no-reconall"; shift ;;
        --mem) MEM_MB="$2"; shift 2 ;;
        --n-cpus) N_CPUS="$2"; shift 2 ;;
        -h|--help) print_usage; exit 0 ;;
        *) echo -e "${RED}Errore: opzione sconosciuta $1${NC}"; print_usage; exit 1 ;;
    esac
done

if [ -z "$BIDS_DIR" ] || [ -z "$OUTPUT_DIR" ]; then
    echo -e "${RED}Errore: --bids-dir e --output-dir sono obbligatori${NC}"
    print_usage
    exit 1
fi

if [ ! -d "$BIDS_DIR" ]; then
    echo -e "${RED}Errore: BIDS directory non trovata: $BIDS_DIR${NC}"
    exit 1
fi

if [ ! -f "$FS_LICENSE" ]; then
    echo -e "${YELLOW}Warning: Licenza FreeSurfer non trovata in $FS_LICENSE${NC}"
    read -p "Inserisci il percorso alla licenza FreeSurfer: " FS_LICENSE
    if [ ! -f "$FS_LICENSE" ]; then
        echo -e "${RED}Errore: Licenza non valida${NC}"
        exit 1
    fi
fi

mkdir -p "$OUTPUT_DIR"
mkdir -p "$WORK_DIR"

BIDS_DIR=$(realpath "$BIDS_DIR")
OUTPUT_DIR=$(realpath "$OUTPUT_DIR")
WORK_DIR=$(realpath "$WORK_DIR")
FS_LICENSE=$(realpath "$FS_LICENSE")

echo -e "${BLUE}=== Configurazione sMRIPrep ===${NC}"
echo "BIDS Directory: $BIDS_DIR"
echo "Output Directory: $OUTPUT_DIR"
echo "Work Directory: $WORK_DIR"
echo "Participant: ${PARTICIPANT:-all}"
echo "Version: $SMRIPREP_VERSION"
echo ""

CMD="docker run --rm -it \
    -v ${BIDS_DIR}:/data:ro \
    -v ${OUTPUT_DIR}:/out \
    -v ${WORK_DIR}:/work \
    -v ${FS_LICENSE}:/opt/freesurfer/license.txt:ro \
    -v ${TEMPLATEFLOW_HOME:-$HOME/.cache/templateflow}:/home/smriprep/.cache/templateflow \
    nipreps/smriprep:${SMRIPREP_VERSION} \
    /data /out participant \
    --work-dir /work \
    --mem-mb ${MEM_MB} \
    --n-cpus ${N_CPUS} \
    --output-spaces MNI152NLin2009cAsym:res-native anat fsnative \
    ${FS_NO_RECONALL}"

if [ -n "$PARTICIPANT" ]; then
    CMD="$CMD --participant-label $PARTICIPANT"
fi

echo -e "${GREEN}Esecuzione sMRIPrep...${NC}"
echo "$CMD"
echo ""

eval $CMD

echo -e "${GREEN}✓ sMRIPrep completato!${NC}"
SMRIPREP_SCRIPT
    
    chmod +x "$helper_script"
    print_success "Script sMRIPrep helper creato: $helper_script"
}

# ============================================================================
# CREAZIONE AMBIENTE CONDA/MAMBA
# ============================================================================

create_conda_environment() {
    print_header "CREAZIONE AMBIENTE CONDA/MAMBA"
    
    local env_file="${CONFIG_DIR}/neuroimaging_env.yml"
    
    if [ ! -f "$env_file" ]; then
        # Crea file YAML di default
        cat > "$env_file" << 'EOF'
name: neuroimaging
channels:
  - conda-forge
  - defaults
dependencies:
  - python=3.10
  - pip
  
  # Neuroimaging core
  - nibabel
  - dipy
  - nilearn
  - nipype
  - nipy
  - pybids
  - nitransforms
  - nistats
  
  # Machine learning
  - scikit-learn
  - scikit-image
  - pandas
  - numpy
  - scipy
  - matplotlib
  - seaborn
  - plotly
  
  # Jupyter
  - jupyter
  - jupyterlab
  - ipython
  - ipykernel
  - ipywidgets
  - notebook
  
  # Utilities
  - dcm2niix
  - fslpy
  - mrtrix3
  - ants
  - afni
  
  # Pip packages
  - pip:
    - pydeface
    - heudiconv
    - fitlins
    - neurodocker
    - fmriprep-docker
    - templateflow
EOF
        print_message "Creato file ambiente di default: $env_file"
    fi
    
    # Installa ambiente
    if command_exists micromamba || [ -f "${CONDA_DIR}/bin/micromamba" ]; then
        local mamba_cmd="${CONDA_DIR}/bin/micromamba"
        "$mamba_cmd" env create -f "$env_file" -y
        print_success "Ambiente creato con micromamba"
    elif command_exists conda; then
        conda env create -f "$env_file" -y
        print_success "Ambiente creato con conda"
    else
        print_warning "Né conda né micromamba trovati"
        return 1
    fi
}

# ============================================================================
# ESPORTAZIONE CONTAINER
# ============================================================================

export_to_container() {
    print_header "CREAZIONE DOCKER CONTAINER"
    
    local dockerfile="${CONFIG_DIR}/Dockerfile.neuroimaging"
    
    if [ ! -f "$dockerfile" ]; then
        cat > "$dockerfile" << 'EOF'
FROM ubuntu:22.04

# Installa dipendenze
RUN apt-get update && apt-get install -y \
    wget curl git build-essential unzip tcsh \
    python3 python3-pip python3-dev python3-venv \
    libgl1-mesa-dev libglu1-mesa-dev libglw1-mesa \
    libgomp1 libjpeg62-dev libxml2-dev libxslt1-dev \
    libeigen3-dev zlib1g-dev libqt5core5a libqt5gui5 \
    libqt5widgets5 libqt5opengl5 libqt5svg5-dev \
    libopenblas-dev libfftw3-dev libnifti-dev \
    libtool automake autoconf cmake g++ gcc \
    perl xfonts-base gnome-tweak-tool \
    libjpeg62 xvfb xterm vim netpbm libxp6 \
    && rm -rf /var/lib/apt/lists/*

# Crea utente neuro
RUN useradd -m -s /bin/bash neuro && \
    mkdir -p /neuroimaging && \
    chown -R neuro:neuro /neuroimaging

USER neuro
WORKDIR /home/neuro

# Copia script di installazione
COPY --chown=neuro:neuro neuroimaging_installer.sh /home/neuro/
COPY --chown=neuro:neuro config/neuroimaging_env.yml /home/neuro/

# Esegui installazione (modalità silenziosa)
RUN bash neuroimaging_installer.sh -a -y

# Configura ambiente
ENV FSLDIR=/neuroimaging/fsl
ENV FREESURFER_HOME=/neuroimaging/freesurfer
ENV ANTSPATH=/neuroimaging/ants
ENV PATH="/neuroimaging/abin:/neuroimaging/fsl/bin:/neuroimaging/ants:/neuroimaging/mrtrix3/bin:$PATH"
ENV FS_LICENSE=/neuroimaging/config/license.txt
ENV SUBJECTS_DIR=/neuroimaging/freesurfer_subjects

# Directory di lavoro
WORKDIR /data
VOLUME /data

CMD ["/bin/bash"]
EOF
        print_message "Creato Dockerfile: $dockerfile"
    fi
    
    # Costruisci immagine
    if command_exists docker; then
        print_message "Costruzione immagine Docker..."
        docker build -f "$dockerfile" -t neuroimaging:latest .
        print_success "Immagine Docker creata: neuroimaging:latest"
        
        # Crea script per eseguire container
        cat > "${INSTALL_DIR}/run_neuroimaging_container.sh" << 'EOF'
#!/bin/bash
docker run -it --rm \
    -v $(pwd):/data \
    -v ${HOME}/neuroimaging/config/license.txt:/neuroimaging/config/license.txt \
    neuroimaging:latest
EOF
        chmod +x "${INSTALL_DIR}/run_neuroimaging_container.sh"
        print_success "Script esecuzione creato: ${INSTALL_DIR}/run_neuroimaging_container.sh"
    else
        print_error "Docker non installato"
        return 1
    fi
}

# ============================================================================
# FUNZIONI DI GESTIONE
# ============================================================================

parse_config_file() {
    local config_file="$1"
    
    if [ -f "$config_file" ]; then
        print_message "Lettura file configurazione: $config_file"
        
        # Formato semplice: software=versione
        while IFS='=' read -r key value; do
            case "$key" in
                install_*)
                    software=${key#install_}
                    if [ "${INSTALL_SOFTWARE[$software]+exists}" ]; then
                        INSTALL_SOFTWARE["$software"]=$(echo "$value" | tr '[:upper:]' '[:lower:]')
                    fi
                    ;;
                version_*)
                    software=${key#version_}
                    eval "${software^^}_VERSION=\"$value\""
                    ;;
                silent_mode)
                    SILENT_MODE=$(echo "$value" | tr '[:upper:]' '[:lower:]')
                    ;;
            esac
        done < "$config_file"
    fi
}

cleanup_error() {
    print_error "Errore durante l'installazione"
    print_message "Log disponibile in: ${LOG_DIR}/error_$(date +%Y%m%d_%H%M%S).log"
    exit 1
}

verify_installation() {
    print_header "VERIFICA INSTALLAZIONE"
    
    local verification_log="${LOG_DIR}/verification_$(date +%Y%m%d_%H%M%S).log"
    
    echo "=== Verifica installazione $(date) ===" > "$verification_log"
    
    for software in "${!INSTALL_SOFTWARE[@]}"; do
        if [ "${INSTALL_SOFTWARE[$software]}" = true ]; then
            case $software in
                fsl)
                    if [ -f "${INSTALL_DIR}/fsl/bin/fsl" ]; then
                        echo "✓ FSL: OK" | tee -a "$verification_log"
                    else
                        echo "✗ FSL: FAILED" | tee -a "$verification_log"
                    fi
                    ;;
                freesurfer)
                    if [ -f "${INSTALL_DIR}/freesurfer/bin/recon-all" ]; then
                        echo "✓ FreeSurfer: OK" | tee -a "$verification_log"
                    else
                        echo "✗ FreeSurfer: FAILED" | tee -a "$verification_log"
                    fi
                    ;;
                ants)
                    if [ -f "${INSTALL_DIR}/ants/antsRegistration" ]; then
                        echo "✓ ANTs: OK" | tee -a "$verification_log"
                    else
                        echo "✗ ANTs: FAILED" | tee -a "$verification_log"
                    fi
                    ;;
                fmriprep)
                    if command_exists docker && docker images | grep -q fmriprep; then
                        echo "✓ fMRIPrep-Docker: OK" | tee -a "$verification_log"
                    else
                        echo "✗ fMRIPrep-Docker: FAILED" | tee -a "$verification_log"
                    fi
                    ;;
                mriqc)
                    if command_exists docker && docker images | grep -q mriqc; then
                        echo "✓ MRIQC-Docker: OK" | tee -a "$verification_log"
                    else
                        echo "✗ MRIQC-Docker: FAILED" | tee -a "$verification_log"
                    fi
                    ;;
                smriprep)
                    if command_exists docker && docker images | grep -q smriprep; then
                        echo "✓ sMRIPrep-Docker: OK" | tee -a "$verification_log"
                    else
                        echo "✗ sMRIPrep-Docker: FAILED" | tee -a "$verification_log"
                    fi
                    ;;
            esac
        fi
    done
    
    print_success "Verifica completata. Log: $verification_log"
}

show_help() {
    cat << EOF
Uso: $(basename "$0") [opzioni]

Opzioni:
    -a              Installa tutto
    -f              Installa FSL
    -r              Installa FreeSurfer
    -n              Installa ANTs
    -i              Installa AFNI
    -m              Installa MRtrix3
    -c              Installa Convert3D
    -s              Installa SPM
    -t              Installa CONN
    -p              Installa fMRIPrep-Docker
    -q              Installa MRIQC-Docker
    -e              Installa sMRIPrep-Docker
    -d              Crea ambiente conda
    -g              Esporta a container Docker
    -y              Modalità silenziosa
    -u FILE         Usa file di configurazione
    -h              Mostra questo help

Esempi:
    # Installa tutto
    $(basename "$0") -a
    
    # Installa solo FSL e fMRIPrep
    $(basename "$0") -f -p
    
    # Installa suite completa NiPreps (fMRIPrep, MRIQC, sMRIPrep)
    $(basename "$0") -p -q -e
    
    # Installa da file di configurazione
    $(basename "$0") -u config.txt

EOF
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    print_header "NEUROIMAGING ENVIRONMENT INSTALLER"
    
    # Parsing argomenti
    while getopts "afnismcrtpdqeyhu:g:" opt; do
        case ${opt} in
            a) INSTALL_ALL=true ;;
            f) INSTALL_SOFTWARE["fsl"]=true ;;
            n) INSTALL_SOFTWARE["ants"]=true ;;
            i) INSTALL_SOFTWARE["afni"]=true ;;
            s) INSTALL_SOFTWARE["spm"]=true ;;
            m) INSTALL_SOFTWARE["mrtrix"]=true ;;
            c) INSTALL_SOFTWARE["c3d"]=true ;;
            r) INSTALL_SOFTWARE["freesurfer"]=true ;;
            t) INSTALL_SOFTWARE["conn"]=true ;;
            p) INSTALL_SOFTWARE["fmriprep"]=true ;;
            q) INSTALL_SOFTWARE["mriqc"]=true ;;
            e) INSTALL_SOFTWARE["smriprep"]=true ;;
            d) CREATE_CONDA_ENV=true ;;
            y) SILENT_MODE=true ;;
            u) parse_config_file "$OPTARG" ;;
            g) EXPORT_CONTAINER=true ;;
            h) show_help; exit 0 ;;
            \?) print_error "Opzione non valida"; show_help; exit 1 ;;
        esac
    done
    
    # Se -a, installa tutto
    if [ "$INSTALL_ALL" = true ]; then
        for software in "${!INSTALL_SOFTWARE[@]}"; do
            INSTALL_SOFTWARE["$software"]=true
        done
        CREATE_CONDA_ENV=true
    fi
    
    # Inizializzazione
    create_dirs
    local log_file="${LOG_DIR}/install_$(date +%Y%m%d_%H%M%S).log"
    exec > >(tee -a "$log_file") 2>&1
    
    # Installazione dipendenze
    if [ "$SKIP_DEPENDENCIES" = false ]; then
        install_system_dependencies
    fi
    
    # Installazione software
    for software in "${!INSTALL_SOFTWARE[@]}"; do
        if [ "${INSTALL_SOFTWARE[$software]}" = true ]; then
            case $software in
                fsl) install_fsl ;;
                freesurfer) install_freesurfer ;;
                ants) install_ants ;;
                afni) install_afni ;;
                mrtrix) install_mrtrix ;;
                c3d) install_c3d ;;
                conn) install_conn ;;
                micromamba) install_micromamba ;;
                fmriprep) install_fmriprep_docker ;;
                mriqc) install_mriqc_docker ;;
                smriprep) install_smriprep_docker ;;
            esac
        fi
    done
    
    # Ambiente conda
    if [ "$CREATE_CONDA_ENV" = true ]; then
        create_conda_environment
    fi
    
    # Container
    if [ "$EXPORT_CONTAINER" = true ]; then
        export_to_container
    fi
    
    # Verifica
    verify_installation
    
    # Riepilogo
    print_header "INSTALLAZIONE COMPLETATA"
    echo -e "${GREEN}${BOLD}✓ Ambiente neuroimaging configurato con successo!${NC}"
    echo ""
    echo "Install Directory: $INSTALL_DIR"
    echo "Log File: $log_file"
    echo ""
    echo "Per configurare l'ambiente:"
    echo "  source ~/.bashrc"
    echo ""
    
    if [ "$CREATE_CONDA_ENV" = true ]; then
        echo "Per attivare l'ambiente conda:"
        if [ -f "${CONDA_DIR}/bin/micromamba" ]; then
            echo "  micromamba activate neuroimaging"
        else
            echo "  conda activate neuroimaging"
        fi
        echo ""
    fi
    
    if [ "${INSTALL_SOFTWARE[fmriprep]}" = true ]; then
        echo "Per eseguire fMRIPrep:"
        echo "  ${INSTALL_DIR}/bin/run_fmriprep.sh -b <bids_dir> -o <output_dir>"
        echo ""
    fi
    
    if [ "${INSTALL_SOFTWARE[mriqc]}" = true ]; then
        echo "Per eseguire MRIQC (quality control):"
        echo "  ${INSTALL_DIR}/bin/run_mriqc.sh -b <bids_dir> -o <output_dir>"
        echo ""
    fi
    
    if [ "${INSTALL_SOFTWARE[smriprep]}" = true ]; then
        echo "Per eseguire sMRIPrep (anatomical preprocessing):"
        echo "  ${INSTALL_DIR}/bin/run_smriprep.sh -b <bids_dir> -o <output_dir>"
        echo ""
    fi
    
    if [ "$EXPORT_CONTAINER" = true ]; then
        echo "Container Docker creato:"
        echo "  ${INSTALL_DIR}/run_neuroimaging_container.sh"
    fi
}

# Avvio
main "$@"
