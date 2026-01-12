#!/bin/bash

# ============================================================================
# NEUROIMAGING ENVIRONMENT INSTALLER
# ============================================================================

set -e  # Exit on error
trap 'cleanup_error' ERR

# Directory where this installer script resides
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Output colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# ============================================================================
# CONFIGURATION
# ============================================================================

# Directory
INSTALL_DIR="${NEUROIMAGING_DIR:-$HOME/neuroimaging}"
CONDA_DIR="${INSTALL_DIR}/micromamba"
LOG_DIR="${INSTALL_DIR}/logs"
CONFIG_DIR="${INSTALL_DIR}/config"
BACKUP_DIR="${INSTALL_DIR}/backup"

# Software versions
FSL_VERSION="6.0.7.1"
FREESURFER_VERSION="8.1.0"
ANTs_VERSION="2.6.4"
AFNI_VERSION="latest"
MRTRIX_VERSION="3.0.3"
SPM_VERSION="12"
MINICONDA_VERSION="latest"
C3D_VERSION="1.4.0"
CONN_VERSION="22.a"
FMRIPREP_VERSION="24.1.1"
MRIQC_VERSION="24.0.2"
SMRIPREP_VERSION="0.15.0"
DCM2NIIX_VERSION="1.0.20250506"
DCM2BIDS_VERSION="3.2.0"

# URL download
declare -A DOWNLOAD_URLS=(
    ["fsl"]="https://fsl.fmrib.ox.ac.uk/fsldownloads/fsl-${FSL_VERSION}-centos7_64.tar.gz"
    ["c3d"]="https://downloads.sourceforge.net/project/c3d/c3d/c3d-${C3D_VERSION}/c3d-${C3D_VERSION}-Linux-x86_64.tar.gz"
    ["dcm2niix"]="https://github.com/rordenlab/dcm2niix/releases/download/v${DCM2NIIX_VERSION}/dcm2niix_lnx.zip"
)

# Platform-specific download URLs
if command -v apt-get >/dev/null 2>&1; then
    DOWNLOAD_URLS["ants"]="https://github.com/ANTsX/ANTs/releases/download/v${ANTs_VERSION}/ants-${ANTs_VERSION}-ubuntu20.04-X64-gcc.zip"
    DOWNLOAD_URLS["dcm2bids"]="https://github.com/UNFmontreal/Dcm2Bids/releases/download/${DCM2BIDS_VERSION}/dcm2bids_debian-based_${DCM2BIDS_VERSION}.tar.gz"
    DOWNLOAD_URLS["freesurfer"]="https://surfer.nmr.mgh.harvard.edu/pub/dist/freesurfer/${FREESURFER_VERSION}/freesurfer_ubuntu22-${FREESURFER_VERSION}_amd64.deb"
elif command -v yum >/dev/null 2>&1; then
    DOWNLOAD_URLS["dcm2bids"]="https://github.com/UNFmontreal/Dcm2Bids/releases/download/${DCM2BIDS_VERSION}/dcm2bids_rhel-based_${DCM2BIDS_VERSION}.tar.gz"
    DOWNLOAD_URLS["ants"]="https://github.com/ANTsX/ANTs/releases/download/v${ANTs_VERSION}/ants-${ANTs_VERSION}-centos7-X64-gcc.zip"
    DOWNLOAD_URLS["freesurfer"]="https://surfer.nmr.mgh.harvard.edu/pub/dist/freesurfer/${FREESURFER_VERSION}/freesurfer_CentOS7-${FREESURFER_VERSION}-1.x86_64.rpm"
fi

# Flag
SILENT_MODE=false
INSTALL_ALL=false
SKIP_DEPENDENCIES=${SKIP_DEPENDENCIES:-false}
FORCE_INSTALL=false
CREATE_CONDA_ENV=false
EXPORT_CONTAINER=false

# Software to install
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
    ["dcm2niix"]=false
    ["dcm2bids"]=false
)

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

print_header() {
    echo -e "\n${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} ${BOLD}$1${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}\n"
}

print_message() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[x]${NC} $1"; }
print_debug() { [ "$DEBUG" = "true" ] && echo -e "${MAGENTA}[DEBUG]${NC} $1"; }

# Silent ptompt instructions
prompt_user() {
    if [ "$SILENT_MODE" = true ]; then
        echo "$2"  # Returns default values
    else
        read -p "$1 " response
        echo "$response"
    fi
}

# Check if command exists
command_exists() { command -v "$1" >/dev/null 2>&1; }

# Directory creation
create_dirs() {
    mkdir -p "$INSTALL_DIR" "$LOG_DIR" "$CONFIG_DIR" "$BACKUP_DIR"
    mkdir -p "$INSTALL_DIR/bin" "$INSTALL_DIR/lib" "$INSTALL_DIR/share"
}

# Backup configurations
backup_config() {
    local config_file="$1"
    if [ -f "$config_file" ]; then
        cp "$config_file" "${BACKUP_DIR}/$(basename "$config_file").bak.$(date +%Y%m%d_%H%M%S)"
    fi
}

# ============================================================================
# ONLINE VERSION CHECK
# ============================================================================

check_online_version() {
    local software=$1
    local current_version=$2

    # When running in silent mode, skip interactive online version checks
    if [ "$SILENT_MODE" = true ]; then
        return 0
    fi

    print_message "Checking ${BOLD}$software${NC}..."

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
            print_warning "Checking version not implemented for $software"
            return 0
            ;;
    esac
    
    if [ -n "$latest" ] && [ "$latest" != "$current_version" ]; then
        print_warning "New version available: $current_version → $latest"
        if [ "$SILENT_MODE" = false ]; then
            read -p "Update? (y/n): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[SsYy]$ ]]; then
                eval "${software}_version=\"$latest\""
                DOWNLOAD_URLS["$software"]=$(update_download_url "$software" "$latest")
            fi
        fi
        # Do not treat user choosing not to update as an error
        return 0
    elif [ -n "$latest" ]; then
        print_message "No update available for $software (current: $current_version)"
        return 0
    fi

    # Default to success unless a real error occurred
    return 0
}

# ============================================================================
# SOFTWARE INSTALLATION
# ============================================================================

install_system_dependencies() {
    print_header "SYSTEM DEPENDENCIES INSTALLATION"
    
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
            netpbm gnome-tweak-tool
        
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
    
    print_success "System dependencies installed"
}

install_micromamba() {
    print_header "MICROMAMBA INSTALLATION"
    
    local mamba_url="https://micro.mamba.pm/api/micromamba/linux-64/latest"
    
    mkdir -p "$CONDA_DIR"
    cd "$CONDA_DIR"
    
    print_message "Download micromamba..."
    curl -Ls "$mamba_url" | tar -xj bin/micromamba
    
    # Initialize shell
    ./bin/micromamba shell init -p "${CONDA_DIR}/envs" -s bash
    
    # Configure environment
    echo "# Micromamba Configuration" >> ~/.bashrc
    echo "export MAMBA_ROOT_PREFIX=\"${CONDA_DIR}/envs\"" >> ~/.bashrc
    echo "export MAMBA_EXE=\"${CONDA_DIR}/bin/micromamba\"" >> ~/.bashrc
    echo 'eval "$(${MAMBA_EXE} shell hook --shell bash)"' >> ~/.bashrc
    
    # Create neuroimaging environment
    if [ -f "${CONFIG_DIR}/neuroimaging_env.yml" ]; then
        print_message "Creating environment from YAML..."
        "${CONDA_DIR}/bin/micromamba" create -f "${CONFIG_DIR}/neuroimaging_env.yml" -y
    else
        print_message "Creating base neuroimaging environment..."
        "${CONDA_DIR}/bin/micromamba" create -n neuroimaging \
            python=3.10 \
            numpy scipy pandas matplotlib seaborn \
            scikit-learn scikit-image jupyter jupyterlab \
            nibabel dipy nilearn nipype nipy \
            ipython ipykernel ipywidgets \
            pip -y
    fi

    print_success "Micromamba installed in $CONDA_DIR"
}

install_fsl() {
    print_header "FSL INSTALLATION"

    local fsl_dir="${INSTALL_DIR}/fsl"

    # Check if already installed
    if [ -d "$fsl_dir" ] && [ "$FORCE_INSTALL" = false ]; then
        print_warning "FSL already installed in $fsl_dir"
        return 0
    fi

    # Ensure bundled getfsl.sh exists
    local getfsl_script="${SCRIPT_DIR}/config/getfsl.sh"
    if [ ! -f "$getfsl_script" ]; then
        print_error "getfsl.sh not found at $getfsl_script. Please ensure config/getfsl.sh is present."
        return 1
    fi

    print_message "Installing FSL ${FSL_VERSION} using getfsl.sh into $fsl_dir..."
    sh "$getfsl_script" "$fsl_dir"

    # Setup environment
    backup_config ~/.bashrc
    echo "# FSL Configuration" >> ~/.bashrc
    echo "export FSLDIR=\"$fsl_dir\"" >> ~/.bashrc
    echo "export PATH=\"\${FSLDIR}/bin:\${PATH}\"" >> ~/.bashrc
    echo "source \${FSLDIR}/etc/fslconf/fsl.sh" >> ~/.bashrc
    echo "export FSLOUTPUTTYPE=NIFTI_GZ" >> ~/.bashrc

    # Verify installation
    if [ -f "${fsl_dir}/bin/fsl" ] || [ -f "${fsl_dir}/bin/dcm2niix" ]; then
        print_success "FSL installed in $fsl_dir"
    else
        print_error "FSL installation may have failed"
        return 1
    fi
}

install_dcm2niix() {
    print_header "dcm2niix INSTALLATION"

    local temp_zip="/tmp/dcm2niix_${DCM2NIIX_VERSION}.zip"
    local extract_dir="/tmp/dcm2niix_extract_${DCM2NIIX_VERSION}"

    print_message "Downloading dcm2niix ${DCM2NIIX_VERSION}..."
    wget --progress=bar:force "${DOWNLOAD_URLS[dcm2niix]}" -O "$temp_zip"

    print_message "Extracting dcm2niix..."
    rm -rf "$extract_dir" && mkdir -p "$extract_dir"
    unzip -o "$temp_zip" -d "$extract_dir" || true

    # Find executable
    local exe_path
    exe_path=$(find "$extract_dir" -type f -name 'dcm2niix' -perm /111 | head -n 1 || true)
    if [ -z "$exe_path" ]; then
        # Try any executable
        exe_path=$(find "$extract_dir" -type f -perm /111 | head -n 1 || true)
    fi

    if [ -z "$exe_path" ]; then
        print_error "dcm2niix executable not found in archive"
        rm -rf "$extract_dir" "$temp_zip"
        return 1
    fi

    print_message "Moving dcm2niix to /usr/bin (may require sudo)..."
    if [ -w "/usr/bin" ]; then
        mv "$exe_path" /usr/bin/dcm2niix
        chmod +x /usr/bin/dcm2niix || true
    else
        if command_exists sudo; then
            sudo mv "$exe_path" /usr/bin/dcm2niix
            sudo chmod +x /usr/bin/dcm2niix || true
        else
            print_error "Cannot write to /usr/bin and sudo not available"
            rm -rf "$extract_dir" "$temp_zip"
            return 1
        fi
    fi

    print_success "dcm2niix installed to /usr/bin/dcm2niix"

    rm -rf "$extract_dir" "$temp_zip"
}

install_dcm2bids() {
    print_header "dcm2bids INSTALLATION"

    local temp_tgz="/tmp/dcm2bids_${DCM2BIDS_VERSION}.tar.gz"
    local extract_dir="/tmp/dcm2bids_extract_${DCM2BIDS_VERSION}"

    print_message "Downloading dcm2bids ${DCM2BIDS_VERSION}..."
    wget --progress=bar:force "${DOWNLOAD_URLS[dcm2bids]}" -O "$temp_tgz"

    rm -rf "$extract_dir" && mkdir -p "$extract_dir"
    tar -xzf "$temp_tgz" -C "$extract_dir" || true

    # Find executable
    local exe_path
    exe_path=$(find "$extract_dir" -type f -name 'dcm2bids*' -perm /111 | head -n 1 || true)
    if [ -z "$exe_path" ]; then
        exe_path=$(find "$extract_dir" -type f -perm /111 | head -n 1 || true)
    fi

    if [ -z "$exe_path" ]; then
        print_error "dcm2bids executable not found in archive"
        rm -rf "$extract_dir" "$temp_tgz"
        return 1
    fi

    print_message "Moving dcm2bids to /usr/bin (may require sudo)..."
    if [ -w "/usr/bin" ]; then
        mv "$exe_path" /usr/bin/dcm2bids
        chmod +x /usr/bin/dcm2bids || true
    else
        if command_exists sudo; then
            sudo mv "$exe_path" /usr/bin/dcm2bids
            sudo chmod +x /usr/bin/dcm2bids || true
        else
            print_error "Cannot write to /usr/bin and sudo not available"
            rm -rf "$extract_dir" "$temp_tgz"
            return 1
        fi
    fi

    print_success "dcm2bids installed to /usr/bin/dcm2bids"

    rm -rf "$extract_dir" "$temp_tgz"
}

install_freesurfer() {
    print_header "FREESURFER INSTALLATION"
    
    local fs_dir="${INSTALL_DIR}/freesurfer"
    local license_file="${CONFIG_DIR}/license.txt"
    
    if [ -d "$fs_dir" ] && [ "$FORCE_INSTALL" = false ]; then
        print_warning "FreeSurfer already installed in $fs_dir"
        return 0
    fi
    
    check_online_version "freesurfer" "$FREESURFER_VERSION"
    
    # License handling
    if [ ! -f "$license_file" ] && [ "$SILENT_MODE" = false ]; then
        print_warning "FreeSurfer requires a license"
        echo "Get it from: https://surfer.nmr.mgh.harvard.edu/registration.html"
        read -p "Paste the license content (Ctrl+D to finish):" license_content
        echo "$license_content" > "$license_file"
    elif [ "$SILENT_MODE" = true ]; then
        print_warning "Silent mode: ensure you have the file ${license_file}"
    fi
    
    # Download
    local temp_file="/tmp/freesurfer_${FREESURFER_VERSION}.tar.gz"
    print_message "Download FreeSurfer ${FREESURFER_VERSION}..."
    wget --progress=bar:force "${DOWNLOAD_URLS[freesurfer]}" -O "$temp_file"
    
    # Extraction
    mkdir -p "$fs_dir"
    tar -xzf "$temp_file" -C "$fs_dir" --strip-components=1
    
    # Configuration
    backup_config ~/.bashrc
    echo "# FreeSurfer Configuration" >> ~/.bashrc
    echo "export FREESURFER_HOME=\"$fs_dir\"" >> ~/.bashrc
    echo "export FS_LICENSE=\"$license_file\"" >> ~/.bashrc
    echo "source \${FREESURFER_HOME}/SetUpFreeSurfer.sh" >> ~/.bashrc
    
    # Setup subject directory
    export SUBJECTS_DIR="${INSTALL_DIR}/freesurfer_subjects"
    mkdir -p "$SUBJECTS_DIR"
    echo "export SUBJECTS_DIR=\"$SUBJECTS_DIR\"" >> ~/.bashrc
    
    print_success "FreeSurfer installed in $fs_dir"
    rm -f "$temp_file"
}

install_ants() {
    print_header "ANTs INSTALLATION"
    
    local ants_dir="${INSTALL_DIR}/ants"
    
    check_online_version "ants" "$ANTs_VERSION"
    
    # Download
    local url="${DOWNLOAD_URLS[ants]}"
    local temp_file
    if echo "$url" | grep -qi "\.zip"; then
        temp_file="/tmp/ants_${ANTs_VERSION}.zip"
    else
        temp_file="/tmp/ants_${ANTs_VERSION}.tar.gz"
    fi
    print_message "Download ANTs ${ANTs_VERSION}..."
    wget --progress=bar:force "$url" -O "$temp_file"

    # Extraction (handle .zip and tar.gz)
    if echo "$temp_file" | grep -qi "\.zip"; then
        # Download directly into the target dir to avoid double-copying large archives
        mkdir -p "$ants_dir"
        local local_zip="${ants_dir}/ants_${ANTs_VERSION}.zip"
        mv "$temp_file" "$local_zip" 2>/dev/null || true
        # If wget wrote to temp_file path (outside ants_dir), move it into ants_dir
        if [ ! -f "$local_zip" ] && [ -f "$temp_file" ]; then
            mv "$temp_file" "$local_zip" || true
        fi
        unzip -o "$local_zip" -d "$ants_dir" || true
        # If archive created a single top-level directory, normalize contents
        # Normalize if the archive created a single top-level directory.
        # Consider only directories (ignore the zip file itself or other files).
        mapfile -t subdirs < <(find "$ants_dir" -mindepth 1 -maxdepth 1 -type d -print)
        if [ "${#subdirs[@]}" -eq 1 ]; then
            mv "${subdirs[0]}"/* "$ants_dir" 2>/dev/null || true
            rmdir "${subdirs[0]}" 2>/dev/null || true
        fi
        rm -f "$local_zip"
    else
        mkdir -p "$ants_dir"
        tar -xzf "$temp_file" -C "$ants_dir" --strip-components=1
    fi
    
    # Configuration
    backup_config ~/.bashrc
    echo "# ANTs Configuration" >> ~/.bashrc
    echo "export ANTSPATH=\"$ants_dir/bin\"" >> ~/.bashrc
    echo "export PATH=\"\${ANTSPATH}:\${PATH}\"" >> ~/.bashrc
    
    # Verify installation (check common locations for antsRegistration)
    if [ -x "${ants_dir}/antsRegistration" ] || [ -x "${ants_dir}/bin/antsRegistration" ]; then
        print_success "ANTs installed in $ants_dir"
    else
        print_error "ANTs installation failed"
        return 1
    fi
    
    rm -f "$temp_file"
}

install_afni() {
    print_header "AFNI INSTALLATION"

    check_online_version "afni" "$AFNI_VERSION"
    
    # AFNI specific dependencies installation
    print_message "Installing AFNI dependencies..."
    if command_exists apt-get; then
        sudo apt-get install -y \
            libxpm4 libxmu6 libxt6 \
            libmotif-common libmotif-dev \
            libglu1-mesa-dev libglw1-mesa-dev \
            libxm4 libxpm-dev libxt-dev \
            libxi6 libxinerama1
    fi

    # Install R (optional but useful)
    if ! command_exists R; then
        print_message "Installing R for AFNI..."
        if command_exists apt-get; then
            sudo apt-get install -y r-base r-base-dev
        fi
    fi

    # Install AFNI
    print_message "Installing AFNI..."
    cd /tmp
    curl -O https://afni.nimh.nih.gov/pub/dist/bin/linux_openmp_64/@update.afni.binaries
    tcsh @update.afni.binaries -package linux_openmp_64 -do_extras -bindir "${INSTALL_DIR}/abin"

    # Configuration
    backup_config ~/.bashrc
    echo "# AFNI Configuration" >> ~/.bashrc
    echo "export PATH=\"${INSTALL_DIR}/abin:\$PATH\"" >> ~/.bashrc
    echo "export AFNI_PLUGINPATH=\"${INSTALL_DIR}/abin\"" >> ~/.bashrc

    print_success "AFNI installed"
}

install_mrtrix() {
    print_header "MRtrix3 INSTALLATION"

    local mrtrix_dir="${INSTALL_DIR}/mrtrix3"
    
    check_online_version "mrtrix" "$MRTRIX_VERSION"
    
    # Clone or update
    if [ -d "$mrtrix_dir" ]; then
        print_message "Updating MRtrix3..."
        cd "$mrtrix_dir"
        git pull
    else
        print_message "Cloning MRtrix3..."
        git clone https://github.com/MRtrix3/mrtrix3.git "$mrtrix_dir"
        cd "$mrtrix_dir"
    fi

    # Configure and compile
    print_message "Configuring and compiling..."
    ./configure
    ./build -parallel $(nproc)

    # Configuration
    backup_config ~/.bashrc
    echo "# MRtrix3 Configuration" >> ~/.bashrc
    echo "export PATH=\"${mrtrix_dir}/bin:\$PATH\"" >> ~/.bashrc
    
    print_success "MRtrix3 installed in $mrtrix_dir"
}

install_c3d() {
    print_header "Convert3D INSTALLATION"
    
    local c3d_dir="${INSTALL_DIR}/c3d"
    local temp_file="/tmp/c3d_${C3D_VERSION}.tar.gz"
    
    print_message "Download Convert3D ${C3D_VERSION}..."
    wget --progress=bar:force "${DOWNLOAD_URLS[c3d]}" -O "$temp_file"
    
    mkdir -p "$c3d_dir"
    tar -xzf "$temp_file" -C "$c3d_dir" --strip-components=1
    
    backup_config ~/.bashrc
    echo "# Convert3D Configuration" >> ~/.bashrc
    echo "export PATH=\"${c3d_dir}/bin:\$PATH\"" >> ~/.bashrc
    
    print_success "Convert3D installed in $c3d_dir"
    rm -f "$temp_file"
}

install_conn() {
    print_header "CONN INSTALLATION"
    
    local conn_dir="${INSTALL_DIR}/conn"
    local conn_url="https://www.linode.com/static/images/products/one-click-apps/conn_standalone.zip"
    
    print_message "Download CONN..."
    wget --progress=bar:force "$conn_url" -O /tmp/conn.zip
    
    mkdir -p "$conn_dir"
    unzip /tmp/conn.zip -d "$conn_dir"
    
    # Richiede MATLAB
    if command_exists matlab; then
        print_message "Adding CONN to MATLAB path..."
        echo "addpath('$conn_dir'); savepath;" > /tmp/conn_setup.m
        matlab -batch "run('/tmp/conn_setup.m')"
    fi

    print_success "CONN installed in $conn_dir"
    rm -f /tmp/conn.zip
}

# ============================================================================
# DOCKER INSTALLATION
# ============================================================================

install_docker() {
    print_header "DOCKER INSTALLATION"
    
    if command_exists apt-get; then
        # Ubuntu/Debian
        print_message "Installing Docker on Ubuntu/Debian..."
        
        # Remove old versions
        sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
        
        # Install dependencies
        sudo apt-get update
        sudo apt-get install -y \
            ca-certificates \
            curl \
            gnupg \
            lsb-release

        # Add Docker repository
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
            sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        
        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
            $(lsb_release -cs) stable" | \
            sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        # Install Docker
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        
    elif command_exists yum; then
        # CentOS/RHEL
        print_message "Installing Docker on CentOS/RHEL..."
        sudo yum install -y yum-utils
        sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        sudo yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        
    elif command_exists dnf; then
        # Fedora
        print_message "Installing Docker on Fedora..."
        sudo dnf -y install dnf-plugins-core
        sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
        sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    fi

    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Verifica installazione
    if docker --version >/dev/null 2>&1; then
        print_success "Docker installed correctly"
        docker --version
    else
        print_error "Docker installation failed"
        return 1
    fi
}

# ============================================================================
# FMRIPREP-DOCKER INSTALLATION
# ============================================================================

install_fmriprep_docker() {
    print_header "FMRIPREP-DOCKER CONFIGURATION"

    # Verify Docker
    if ! command_exists docker; then
        print_error "Docker not found. Installing Docker..."
        install_docker
    fi

    # Verify that Docker is running
    if ! docker info >/dev/null 2>&1; then
        print_warning "Docker is not running. Starting Docker..."
        sudo systemctl start docker
        sleep 3
        if ! docker info >/dev/null 2>&1; then
            print_error "Docker cannot be started. Start it manually with: sudo systemctl start docker"
            return 1
        fi
    fi

    # Add user to docker group if necessary
    if ! groups | grep -q docker; then
        print_warning "Adding user to docker group..."
        sudo usermod -aG docker "$USER"
        print_warning "IMPORTANT: Restart the session to apply the changes to the docker group"
        print_warning "Or execute: newgrp docker"
    fi

    # Install fmriprep-docker via pip in the conda environment
    print_message "Fmriprep-docker wrapper installation..."
    if [ -f "${CONDA_DIR}/bin/micromamba" ]; then
        "${CONDA_DIR}/bin/micromamba" run -n neuroimaging pip install fmriprep-docker
    elif command_exists conda; then
        conda run -n neuroimaging pip install fmriprep-docker
    else
        pip install --user fmriprep-docker
    fi

    # Pre-download fMRIPrep docker image (optional but recommended)
    local fmriprep_version="${FMRIPREP_VERSION}"
    
    if [ "$SILENT_MODE" = false ]; then
        read -p "Download the Docker image of fMRIPrep ${fmriprep_version}? (s/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Ss]$ ]]; then
            print_message "Download fMRIPrep image ${fmriprep_version}... (this may take time)"
            docker pull nipreps/fmriprep:${fmriprep_version}
            print_success "fMRIPrep image downloaded"
        fi
    fi

    # Create directory for TemplateFlow
    local templateflow_dir="${INSTALL_DIR}/templateflow"
    mkdir -p "$templateflow_dir"
    
    # Environment variables configuration
    backup_config ~/.bashrc
    echo "" >> ~/.bashrc
    echo "# fMRIPrep Configuration" >> ~/.bashrc
    echo "export TEMPLATEFLOW_HOME=\"${templateflow_dir}\"" >> ~/.bashrc
    echo "export FMRIPREP_VERSION=\"${fmriprep_version}\"" >> ~/.bashrc
    
    # Create helper script for fMRIPrep
    create_fmriprep_helper_script
    
    print_success "fMRIPrep-Docker configured"
    print_message "Versione: ${fmriprep_version}"
    print_message "TemplateFlow: ${templateflow_dir}"
    print_message "Script helper: ${INSTALL_DIR}/bin/run_fmriprep.sh"
}

install_mriqc_docker() {
    print_header "MRIQC-DOCKER CONFIGURATION"
    
    # Verifica Docker
    if ! command_exists docker; then
        print_error "Docker not found. Installing Docker..."
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
        read -p "Download the Docker image of MRIQC ${mriqc_version}? (y/n): " -n 1 -r
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
    
    print_success "MRIQC-Docker configured"
    print_message "Versione: ${mriqc_version}"
    print_message "Script helper: ${INSTALL_DIR}/bin/run_mriqc.sh"
}

install_smriprep_docker() {
    print_header "sMRIPrep-DOCKER CONFIGURATION"
    
    # Verifica Docker
    if ! command_exists docker; then
        print_error "Docker not found. Installing Docker..."
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
        read -p "Download the Docker image of sMRIPrep ${smriprep_version}? (y/n): " -n 1 -r
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
    
    print_success "sMRIPrep-Docker configured"
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

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_usage() {
    cat << EOF
Use: $(basename "$0") [options]

Helper script to run fMRIPrep with Docker

Options:
    -b, --bids-dir DIR          BIDS input directory (required)
    -o, --output-dir DIR        Output directory (required)
    -p, --participant-label ID  Participant (optional)
    -w, --work-dir DIR          Working directory (default: ./work)
    -f, --fs-license FILE       FreeSurfer license file
    -v, --version VERSION       fMRIPrep version (default: from \$FMRIPREP_VERSION)
    --skip-bids-validation      Skip BIDS validation
    --fs-no-reconall            Skip FreeSurfer reconstruction
    --use-aroma                 Use ICA-AROMA for denoising
    --mem MB                    Maximum memory (default: 16000)
    --n-cpus N                  Number of CPUs (default: auto)
    -h, --help                  Show this help message

Example:
    $(basename "$0") -b /data/bids -o /data/derivatives -p sub-01

EOF
}

# Default values
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

# Verify required parameters
if [ -z "$BIDS_DIR" ] || [ -z "$OUTPUT_DIR" ]; then
    echo -e "${RED}Error: --bids-dir and --output-dir are required${NC}"
    print_usage
    exit 1
fi

# Verify directory existence
if [ ! -d "$BIDS_DIR" ]; then
    echo -e "${RED}Error: BIDS directory not found: $BIDS_DIR${NC}"
    exit 1
fi

# Verify FreeSurfer license
if [ ! -f "$FS_LICENSE" ]; then
    echo -e "${YELLOW}Warning: FreeSurfer license not found in $FS_LICENSE${NC}"
    echo "Get it from: https://surfer.nmr.mgh.harvard.edu/registration.html"
    read -p "Enter the path to the FreeSurfer license file: " FS_LICENSE
    if [ ! -f "$FS_LICENSE" ]; then
        echo -e "${RED}Error: Invalid license file${NC}"
        exit 1
    fi
fi

# Create output and work directories if they don't exist
mkdir -p "$OUTPUT_DIR"
mkdir -p "$WORK_DIR"

# Convert relative paths to absolute paths
BIDS_DIR=$(realpath "$BIDS_DIR")
OUTPUT_DIR=$(realpath "$OUTPUT_DIR")
WORK_DIR=$(realpath "$WORK_DIR")
FS_LICENSE=$(realpath "$FS_LICENSE")

# Build command
echo -e "${BLUE}=== fMRIPrep Configuration ===${NC}"
echo "BIDS Directory: $BIDS_DIR"
echo "Output Directory: $OUTPUT_DIR"
echo "Work Directory: $WORK_DIR"
echo "Participant: ${PARTICIPANT:-all}"
echo "Version: $FMRIPREP_VERSION"
echo "Memory: ${MEM_MB} MB"
echo "CPUs: $N_CPUS"
echo ""

# Base command
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

# Add participant if specified
if [ -n "$PARTICIPANT" ]; then
    CMD="$CMD --participant-label $PARTICIPANT"
fi

echo -e "${GREEN}Running fMRIPrep...${NC}"
echo "$CMD"
echo ""

# Esegui
eval $CMD

echo -e "${GREEN}fMRIPrep completed!${NC}"
FMRIPREP_SCRIPT
    
    chmod +x "$helper_script"

    print_success "Script helper created: $helper_script"
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
Use: $(basename "$0") [options]

Helper script to run MRIQC with Docker

Options:
    -b, --bids-dir DIR          BIDS input directory (required)
    -o, --output-dir DIR        Output directory (required)
    -p, --participant-label ID  Participant to process (optional)
    -w, --work-dir DIR          Working directory (default: ./work)
    -v, --version VERSION       MRIQC version (default: from \$MRIQC_VERSION)
    --modality TYPE             Modality: T1w, bold, T2w (default: all)
    --mem MB                    Max Memory (default: 16000)
    --n-cpus N                  Number of CPUs (default: auto)
    -h, --help                  Show this message

Example:
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
        *) echo -e "${RED}Error: unknown option $1${NC}"; print_usage; exit 1 ;;
    esac
done

if [ -z "$BIDS_DIR" ] || [ -z "$OUTPUT_DIR" ]; then
    echo -e "${RED}Error: --bids-dir and --output-dir are required${NC}"
    print_usage
    exit 1
fi

if [ ! -d "$BIDS_DIR" ]; then
    echo -e "${RED}Error: BIDS directory not found: $BIDS_DIR${NC}"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
mkdir -p "$WORK_DIR"

BIDS_DIR=$(realpath "$BIDS_DIR")
OUTPUT_DIR=$(realpath "$OUTPUT_DIR")
WORK_DIR=$(realpath "$WORK_DIR")

echo -e "${BLUE}=== Configuration MRIQC ===${NC}"
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

echo -e "${GREEN}Running MRIQC...${NC}"
echo "$CMD"
echo ""

eval $CMD

echo -e "${GREEN}MRIQC completed!${NC}"
echo -e "${BLUE}Report available in: ${OUTPUT_DIR}${NC}"
MRIQC_SCRIPT
    
    chmod +x "$helper_script"
    print_success "Script MRIQC helper created: $helper_script"
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
Usage: $(basename "$0") [options]

Helper script to run sMRIPrep with Docker

Options:
    -b, --bids-dir DIR          Directory BIDS input (required)
    -o, --output-dir DIR        Directory output (required)
    -p, --participant-label ID  Participant (optional)
    -w, --work-dir DIR          Working directory (default: ./work)
    -f, --fs-license FILE       FreeSurfer license file
    -v, --version VERSION       sMRIPrep version (default: from \$SMRIPREP_VERSION)
    --fs-no-reconall            Skip FreeSurfer reconstruction
    --mem MB                    Max memory (default: 16000)
    --n-cpus N                  Number of CPUs (default: auto)

    -h, --help                  Show this message

Example:
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
        *) echo -e "${RED}Error: unknown option $1${NC}"; print_usage; exit 1 ;;
    esac
done

if [ -z "$BIDS_DIR" ] || [ -z "$OUTPUT_DIR" ]; then
    echo -e "${RED}Error: --bids-dir and --output-dir are required${NC}"
    print_usage
    exit 1
fi

if [ ! -d "$BIDS_DIR" ]; then
    echo -e "${RED}Error: BIDS directory not found: $BIDS_DIR${NC}"
    exit 1
fi

if [ ! -f "$FS_LICENSE" ]; then
    echo -e "${YELLOW}Warning: FreeSurfer license not found in $FS_LICENSE${NC}"
    read -p "Insert FreeSurfer license path: " FS_LICENSE
    if [ ! -f "$FS_LICENSE" ]; then
        echo -e "${RED}Error: Not valid FreeSurfer license${NC}"
        exit 1
    fi
fi

mkdir -p "$OUTPUT_DIR"
mkdir -p "$WORK_DIR"

BIDS_DIR=$(realpath "$BIDS_DIR")
OUTPUT_DIR=$(realpath "$OUTPUT_DIR")
WORK_DIR=$(realpath "$WORK_DIR")
FS_LICENSE=$(realpath "$FS_LICENSE")

echo -e "${BLUE}=== sMRIPrep Configuration ===${NC}"
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

echo -e "${GREEN}Running sMRIPrep...${NC}"
echo "$CMD"
echo ""

eval $CMD

echo -e "${GREEN}sMRIPrep completed!${NC}"
SMRIPREP_SCRIPT
    
    chmod +x "$helper_script"
    print_success "sMRIPrep helper script created in: $helper_script"
}

# ============================================================================
# CONDA/MAMBA ENVIRONMENT CREATION
# ============================================================================

create_conda_environment() {
    print_header "CONDA/MAMBA ENVIRONMENT CREATION"
    
    local env_file="${CONFIG_DIR}/neuroimaging_env.yml"
    
    if [ ! -f "$env_file" ]; then
        # Create default YAML file
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
        print_message "Created default environment file: $env_file"
    fi

    # Install environment
    if command_exists micromamba || [ -f "${CONDA_DIR}/bin/micromamba" ]; then
        local mamba_cmd="${CONDA_DIR}/bin/micromamba"
        "$mamba_cmd" env create -f "$env_file" -y
        print_success "Micromamba environment created"
    elif command_exists conda; then
        conda env create -f "$env_file" -y
        print_success "Conda environment created"
    else
        print_warning "Conda/Micromamba not found. Installing Miniconda..."
        return 1
    fi
}

# ============================================================================
# EXPORT DOCKER CONTAINER
# ============================================================================

export_to_container() {
    print_header "CREATING DOCKER CONTAINER"
    
    local dockerfile="${CONFIG_DIR}/Dockerfile.neuroimaging"
    
    if [ ! -f "$dockerfile" ]; then
        cat > "$dockerfile" << 'EOF'
FROM ubuntu:22.04

# Install dependencies
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
    libjpeg62 xvfb xterm vim netpbm \
    && rm -rf /var/lib/apt/lists/*

# Create user neuro
RUN useradd -m -s /bin/bash neuro && \
    mkdir -p /neuroimaging && \
    chown -R neuro:neuro /neuroimaging

USER neuro
WORKDIR /home/neuro

# Copy installation script
COPY --chown=neuro:neuro neuroimaging_installer.sh /home/neuro/
COPY --chown=neuro:neuro config/neuroimaging_env.yml /home/neuro/

# Run installation (silent mode)
RUN bash neuroimaging_installer.sh -a -y

# Environment variables
ENV FSLDIR=/neuroimaging/fsl
ENV FREESURFER_HOME=/neuroimaging/freesurfer
ENV ANTSPATH=/neuroimaging/ants
ENV PATH="/neuroimaging/abin:/neuroimaging/fsl/bin:/neuroimaging/ants:/neuroimaging/mrtrix3/bin:$PATH"
ENV FS_LICENSE=/neuroimaging/config/license.txt
ENV SUBJECTS_DIR=/neuroimaging/freesurfer_subjects

# Working directory
WORKDIR /data
VOLUME /data

CMD ["/bin/bash"]
EOF
        print_message "Created Dockerfile: $dockerfile"
    fi

    # Build image
    if command_exists docker; then
        print_message "Building Docker image..."
        docker build -f "$dockerfile" -t neuroimaging:latest .
        print_success "Docker image created: neuroimaging:latest"
        # Create script for running container
        cat > "${INSTALL_DIR}/run_neuroimaging_container.sh" << 'EOF'
#!/bin/bash
docker run -it --rm \
    -v $(pwd):/data \
    -v ${HOME}/neuroimaging/config/license.txt:/neuroimaging/config/license.txt \
    neuroimaging:latest
EOF
        chmod +x "${INSTALL_DIR}/run_neuroimaging_container.sh"
        print_success "Script created: ${INSTALL_DIR}/run_neuroimaging_container.sh"
    else
        print_error "Docker not installed. Cannot create container."
        return 1
    fi
}

# ============================================================================
# FUNZIONI DI GESTIONE
# ============================================================================

parse_config_file() {
    local config_file="$1"
    
    if [ -f "$config_file" ]; then
        print_message "Reading configuration file: $config_file"
        
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
    print_error "Error during installation. Cleaning up..."
    print_message "Check Log file in: ${LOG_DIR}/error_$(date +%Y%m%d_%H%M%S).log"
    exit 1
}

verify_installation() {
    print_header "CHECK INSTALLATION"
    
    local verification_log="${LOG_DIR}/verification_$(date +%Y%m%d_%H%M%S).log"
    
    echo "=== Installation check $(date) ===" > "$verification_log"
    
    for software in "${!INSTALL_SOFTWARE[@]}"; do
        if [ "${INSTALL_SOFTWARE[$software]}" = true ]; then
            case $software in
                fsl)
                    if [ -f "${INSTALL_DIR}/fsl/bin/fsl" ]; then
                        echo "FSL: OK" | tee -a "$verification_log"
                    else
                        echo "FSL: FAILED" | tee -a "$verification_log"
                    fi
                    ;;
                freesurfer)
                    if [ -f "${INSTALL_DIR}/freesurfer/bin/recon-all" ]; then
                        echo "FreeSurfer: OK" | tee -a "$verification_log"
                    else
                        echo "FreeSurfer: FAILED" | tee -a "$verification_log"
                    fi
                    ;;
                ants)
                    if [ -x "${INSTALL_DIR}/ants/antsRegistration" ] || [ -x "${INSTALL_DIR}/ants/bin/antsRegistration" ] || command_exists antsRegistration; then
                        echo "ANTs: OK" | tee -a "$verification_log"
                    else
                        echo "ANTs: FAILED" | tee -a "$verification_log"
                    fi
                    ;;
                dcm2niix)
                    if [ -f "/usr/bin/dcm2niix" ] || command_exists dcm2niix; then
                        echo "dcm2niix: OK" | tee -a "$verification_log"
                    else
                        echo "dcm2niix: FAILED" | tee -a "$verification_log"
                    fi
                    ;;
                dcm2bids)
                    if [ -f "/usr/bin/dcm2bids" ] || command_exists dcm2bids; then
                        echo "dcm2bids: OK" | tee -a "$verification_log"
                    else
                        echo "dcm2bids: FAILED" | tee -a "$verification_log"
                    fi
                    ;;
                fmriprep)
                    if command_exists docker && docker images | grep -q fmriprep; then
                        echo "fMRIPrep-Docker: OK" | tee -a "$verification_log"
                    else
                        echo "fMRIPrep-Docker: FAILED" | tee -a "$verification_log"
                    fi
                    ;;
                mriqc)
                    if command_exists docker && docker images | grep -q mriqc; then
                        echo "MRIQC-Docker: OK" | tee -a "$verification_log"
                    else
                        echo "MRIQC-Docker: FAILED" | tee -a "$verification_log"
                    fi
                    ;;
                smriprep)
                    if command_exists docker && docker images | grep -q smriprep; then
                        echo "sMRIPrep-Docker: OK" | tee -a "$verification_log"
                    else
                        echo "sMRIPrep-Docker: FAILED" | tee -a "$verification_log"
                    fi
                    ;;
            esac
        fi
    done

    print_success "Checking completed. Log: $verification_log"
}

show_help() {
    cat << EOF
Use: $(basename "$0") [options]

Options:
    -a              Install all software
    -f              Install FSL
    -r              Install FreeSurfer
    -n              Install ANTs
    -i              Install AFNI
    -m              Install MRtrix3
    -c              Install Convert3D
    -s              Install SPM
    -t              Install CONN
    -p              Install fMRIPrep-Docker
    -q              Install MRIQC-Docker
    -e              Install sMRIPrep-Docker
    -z              Install dcm2niix
    -b              Install dcm2bids
    -d              Create conda environment
    -g              Export to Docker container
    -y              Silent mode
    -u FILE         Use configuration file
    -h              Show this help

Examples:
    # Install all software
    $(basename "$0") -a

    # Install only FSL and fMRIPrep
    $(basename "$0") -f -p

    # Install complete NiPreps suite (fMRIPrep, MRIQC, sMRIPrep)
    $(basename "$0") -p -q -e

    # Install from configuration file
    $(basename "$0") -u config.txt

EOF
}

# ============================================================================
# MAIN FUNCTION
# ============================================================================

main() {
    print_header "NEUROIMAGING ENVIRONMENT INSTALLER"
    
    # Parsing argoments
    while getopts "afnismcrtpdqeyzbhu:g:" opt; do
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
            z) INSTALL_SOFTWARE["dcm2niix"]=true ;;
            b) INSTALL_SOFTWARE["dcm2bids"]=true ;;
            d) CREATE_CONDA_ENV=true ;;
            y) SILENT_MODE=true ;;
            u) parse_config_file "$OPTARG" ;;
            g) EXPORT_CONTAINER=true ;;
            h) show_help; exit 0 ;;
            \?) print_error "not a valid option"; show_help; exit 1 ;;
        esac
    done
    
    # If -a, install all software
    if [ "$INSTALL_ALL" = true ]; then
        for software in "${!INSTALL_SOFTWARE[@]}"; do
            INSTALL_SOFTWARE["$software"]=true
        done
        CREATE_CONDA_ENV=true
    fi

    # Check if any software/action was selected
    local any_selected=false
    for s in "${!INSTALL_SOFTWARE[@]}"; do
        if [ "${INSTALL_SOFTWARE[$s]}" = true ]; then
            any_selected=true
            break
        fi
    done
    
    # Also treat conda/container creation as a selected action
    if [ "$CREATE_CONDA_ENV" = true ] || [ "$EXPORT_CONTAINER" = true ]; then
        any_selected=true
    fi

    # If nothing selected, show help and exit
    if [ "$any_selected" = false ]; then
        print_warning "No software/action selected. Showing help and exiting."
        show_help
        exit 0
    fi
    
    # Initial setup
    create_dirs
    local log_file="${LOG_DIR}/install_$(date +%Y%m%d_%H%M%S).log"
    exec > >(tee -a "$log_file") 2>&1

    # Install system dependencies if needed
    if [ "$SKIP_DEPENDENCIES" = false ]; then
        install_system_dependencies
    fi

    # Software installation
    for software in "${!INSTALL_SOFTWARE[@]}"; do
        if [ "${INSTALL_SOFTWARE[$software]}" = true ]; then
            case $software in
                fsl) install_fsl ;;
                freesurfer) install_freesurfer ;;
                ants) install_ants ;;
                afni) install_afni ;;
                mrtrix) install_mrtrix ;;
                c3d) install_c3d ;;
                dcm2niix) install_dcm2niix ;;
                dcm2bids) install_dcm2bids ;;
                conn) install_conn ;;
                micromamba) install_micromamba ;;
                fmriprep) install_fmriprep_docker ;;
                mriqc) install_mriqc_docker ;;
                smriprep) install_smriprep_docker ;;
            esac
        fi
    done
    
    # Conda environment
    if [ "$CREATE_CONDA_ENV" = true ]; then
        create_conda_environment
    fi
    
    # Container
    if [ "$EXPORT_CONTAINER" = true ]; then
        export_to_container
    fi
    
    # Verify installation
    verify_installation
    
    # Summary
    print_header "INSTALLATION COMPLETED"
    echo -e "${GREEN}${BOLD}Neuroimaging environment configured successfully!${NC}"
    echo ""
    echo "Install Directory: $INSTALL_DIR"
    echo "Log File: $log_file"
    echo ""
    echo "To configure the environment:"
    echo "  source ~/.bashrc"
    echo ""
    
    if [ "$CREATE_CONDA_ENV" = true ]; then
        echo "To activate the conda environment:"
        if [ -f "${CONDA_DIR}/bin/micromamba" ]; then
            echo "  micromamba activate neuroimaging"
        else
            echo "  conda activate neuroimaging"
        fi
        echo ""
    fi
    
    if [ "${INSTALL_SOFTWARE[fmriprep]}" = true ]; then
        echo "To run fMRIPrep:"
        echo "  ${INSTALL_DIR}/bin/run_fmriprep.sh -b <bids_dir> -o <output_dir>"
        echo ""
    fi
    
    if [ "${INSTALL_SOFTWARE[mriqc]}" = true ]; then
        echo "To run MRIQC (quality control):"
        echo "  ${INSTALL_DIR}/bin/run_mriqc.sh -b <bids_dir> -o <output_dir>"
        echo ""
    fi
    
    if [ "${INSTALL_SOFTWARE[smriprep]}" = true ]; then
        echo "To run sMRIPrep (anatomical preprocessing):"
        echo "  ${INSTALL_DIR}/bin/run_smriprep.sh -b <bids_dir> -o <output_dir>"
        echo ""
    fi
    
    if [ "$EXPORT_CONTAINER" = true ]; then
        echo "Docker container created:"
        echo "  ${INSTALL_DIR}/run_neuroimaging_container.sh"
    fi
}

# Run
main "$@"
