#!/bin/bash

# ============================================================================
# NEUROIMAGING ENVIRONMENT INSTALLER - VERSIONE COMPLETA
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
)

# ============================================================================
# FUNZIONI UTILITY
# ============================================================================

print_header() {
    echo -e "\n${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ${BOLD}$1${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}\n"
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
# CREAZIONE AMBIENTE CONDA/MAMBA
# ============================================================================

create_conda_environment() {
    print_header "CREAZIONE AMBIENTE CONDA/MAMBA"
    
    local env_file="${CONFIG_DIR}/neuroimaging_env.yml"
    
    if [ ! -f "$env_file" ]; then
        # Crea file YAML di default
        cat > "$env_file" << EOF
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
    - https://github.com/poldracklab/fmriprep/archive/refs/heads/main.zip
    - pydeface
    - heudiconv
    - fitlins
    - neurodocker
    - neurotic
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
                # ... aggiungi altri software
            esac
        fi
    done
    
    print_success "Verifica completata. Log: $verification_log"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    print_header "NEUROIMAGING ENVIRONMENT INSTALLER"
    
    # Parsing argomenti
    while getopts "afnismcrtdyhu:g:" opt; do
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
    fi
    
    if [ "$EXPORT_CONTAINER" = true ]; then
        echo ""
        echo "Container Docker creato:"
        echo "  ${INSTALL_DIR}/run_neuroimaging_container.sh"
    fi
}

# Avvio
main "$@"