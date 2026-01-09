#!/bin/bash
# Test completo dell'installazione neuroimaging

set -e

# Colori
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}═══════════════════════════════════════════${NC}"
echo -e "${YELLOW} Neuroimaging Installation Test Suite${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════${NC}"

# Funzioni di test
test_command() {
    if command -v "$1" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} $1 trovato"
        return 0
    else
        echo -e "${RED}✗${NC} $1 NON trovato"
        return 1
    fi
}

test_file() {
    if [ -f "$1" ]; then
        echo -e "${GREEN}✓${NC} File: $1"
        return 0
    else
        echo -e "${RED}✗${NC} File mancante: $1"
        return 1
    fi
}

test_directory() {
    if [ -d "$1" ]; then
        echo -e "${GREEN}✓${NC} Directory: $1"
        return 0
    else
        echo -e "${RED}✗${NC} Directory mancante: $1"
        return 1
    fi
}

test_python_package() {
    if python -c "import $1" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} Python: $1"
        return 0
    else
        echo -e "${RED}✗${NC} Python: $1 mancante"
        return 1
    fi
}

test_docker_image() {
    local image=$1
    if docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "$image"; then
        local size=$(docker images --format "{{.Size}}" "$image" | head -1)
        echo -e "${GREEN}✓${NC} Docker image: $image (${size})"
        return 0
    else
        echo -e "${RED}✗${NC} Docker image: $image NON scaricata"
        return 1
    fi
}

# Test 1: Software neuroimaging
echo -e "\n${YELLOW}1. Software Neuroimaging${NC}"
echo "------------------------------------------"

# Test FSL
if test_directory "${FSLDIR:-/opt/fsl}"; then
    test_file "${FSLDIR}/bin/fsl"
    test_file "${FSLDIR}/bin/bet"
fi

# Test FreeSurfer
if test_directory "${FREESURFER_HOME:-/opt/freesurfer}"; then
    test_file "${FREESURFER_HOME}/bin/recon-all"
    if [ -f "${FS_LICENSE:-/opt/freesurfer/license.txt}" ]; then
        echo -e "${GREEN}✓${NC} Licenza FreeSurfer presente"
    else
        echo -e "${YELLOW}!${NC} Licenza FreeSurfer mancante"
    fi
fi

# Test ANTs
test_command "antsRegistration"
test_command "antsApplyTransforms"

# Test AFNI
test_command "afni"
test_command "3dTstat"

# Test MRtrix3
test_command "mrcalc"
test_command "dwi2tensor"

# Test 2: Docker e NiPreps
echo -e "\n${YELLOW}2. Docker e Suite NiPreps${NC}"
echo "------------------------------------------"

# Test Docker installato e funzionante
if test_command "docker"; then
    # Verifica che Docker sia in esecuzione
    if docker info >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} Docker daemon in esecuzione"
        
        # Test gruppi utente
        if groups | grep -q docker; then
            echo -e "${GREEN}✓${NC} Utente nel gruppo docker"
        else
            echo -e "${YELLOW}!${NC} Utente NON nel gruppo docker (richiede sudo o newgrp)"
        fi
        
        # Test immagini Docker NiPreps
        echo -e "\n${BLUE}Immagini Docker installate:${NC}"
        test_docker_image "nipreps/fmriprep" || echo -e "  ${YELLOW}→${NC} Usa: docker pull nipreps/fmriprep:24.1.1"
        test_docker_image "nipreps/mriqc" || echo -e "  ${YELLOW}→${NC} Usa: docker pull nipreps/mriqc:24.0.2"
        test_docker_image "nipreps/smriprep" || echo -e "  ${YELLOW}→${NC} Usa: docker pull nipreps/smriprep:0.15.0"
        
        # Test spazio Docker
        echo -e "\n${BLUE}Stato Docker:${NC}"
        docker system df --format "table {{.Type}}\t{{.TotalCount}}\t{{.Size}}" 2>/dev/null || true
        
    else
        echo -e "${RED}✗${NC} Docker daemon NON in esecuzione"
        echo -e "  ${YELLOW}→${NC} Avvia con: sudo systemctl start docker"
    fi
else
    echo -e "${RED}✗${NC} Docker non installato"
fi

# Test script helper NiPreps
echo -e "\n${BLUE}Script helper NiPreps:${NC}"
test_file "${HOME}/neuroimaging/bin/run_fmriprep.sh"
test_file "${HOME}/neuroimaging/bin/run_mriqc.sh"
test_file "${HOME}/neuroimaging/bin/run_smriprep.sh"

# Test 3: Python Environment
echo -e "\n${YELLOW}3. Ambiente Python${NC}"
echo "------------------------------------------"

# Attiva ambiente se necessario
if command -v micromamba >/dev/null 2>&1; then
    eval "$(micromamba shell hook --shell bash)" 2>/dev/null || true
    micromamba activate neuroimaging 2>/dev/null || true
fi

# Pacchetti base neuroimaging
test_python_package "nibabel"
test_python_package "nilearn"
test_python_package "dipy"
test_python_package "nipype"

# NiPreps related
test_python_package "bids" || test_python_package "pybids"
test_python_package "templateflow"

# Deep learning
test_python_package "torch"
test_python_package "numpy"
test_python_package "scipy"

# Test 4: GPU Support
echo -e "\n${YELLOW}4. Supporto GPU${NC}"
echo "------------------------------------------"

if command -v nvidia-smi >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} NVIDIA GPU rilevata"
    nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
    
    # Test PyTorch CUDA
    if python -c "import torch; assert torch.cuda.is_available(); print(f'CUDA version: {torch.version.cuda}')" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} PyTorch CUDA abilitato"
    else
        echo -e "${YELLOW}-${NC} PyTorch CUDA non disponibile"
    fi
    
    # Test NVIDIA Docker (per fMRIPrep con GPU)
    if docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} NVIDIA Docker runtime configurato"
    else
        echo -e "${YELLOW}!${NC} NVIDIA Docker runtime non disponibile"
        echo -e "  ${YELLOW}→${NC} Per GPU in Docker: https://github.com/NVIDIA/nvidia-docker"
    fi
else
    echo -e "${YELLOW}-${NC} NVIDIA GPU non rilevata (modalità CPU)"
fi

# Test 5: File System e Permessi
echo -e "\n${YELLOW}5. File System e Configurazione${NC}"
echo "------------------------------------------"

test_directory "${HOME}/neuroimaging"
test_directory "${HOME}/neuroimaging/config"
test_directory "${HOME}/neuroimaging/logs"

# Test TemplateFlow
if [ -n "$TEMPLATEFLOW_HOME" ]; then
    test_directory "$TEMPLATEFLOW_HOME"
else
    echo -e "${YELLOW}!${NC} TEMPLATEFLOW_HOME non configurato"
fi

# Test scrittura
TEST_FILE="${HOME}/neuroimaging/test_write_$$_.txt"
if touch "$TEST_FILE" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Permessi scrittura OK"
    rm "$TEST_FILE"
else
    echo -e "${RED}✗${NC} Problemi permessi scrittura"
fi

# Test 6: Pipeline Specifiche
echo -e "\n${YELLOW}6. Pipeline Specifiche${NC}"
echo "------------------------------------------"

# Test MS Lesions pipeline
test_python_package "HD_BET" && echo -e "${GREEN}✓${NC} HD-BET disponibile"
test_python_package "nnunet" && echo -e "${GREEN}✓${NC} nnU-Net disponibile"

# Test 7: Configurazione ambiente
echo -e "\n${YELLOW}7. Variabili d'Ambiente${NC}"
echo "------------------------------------------"

check_env_var() {
    if [ -n "${!1}" ]; then
        echo -e "${GREEN}✓${NC} $1=${!1}"
    else
        echo -e "${YELLOW}!${NC} $1 non configurata"
    fi
}

check_env_var "FSLDIR"
check_env_var "FREESURFER_HOME"
check_env_var "ANTSPATH"
check_env_var "TEMPLATEFLOW_HOME"
check_env_var "FMRIPREP_VERSION"
check_env_var "MRIQC_VERSION"

# Test 8: Test funzionale rapido (opzionale)
echo -e "\n${YELLOW}8. Test Funzionali Rapidi${NC}"
echo "------------------------------------------"

RUN_FUNCTIONAL_TESTS=false
if [ "$1" = "--functional" ] || [ "$1" = "-f" ]; then
    RUN_FUNCTIONAL_TESTS=true
fi

if [ "$RUN_FUNCTIONAL_TESTS" = true ]; then
    echo -e "${BLUE}Esecuzione test funzionali...${NC}"
    
    # Test Docker con dati dummy
    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        echo -e "\n${BLUE}Test fMRIPrep --version:${NC}"
        docker run --rm nipreps/fmriprep:latest --version 2>/dev/null || \
            echo -e "${YELLOW}!${NC} Immagine fMRIPrep non disponibile"
        
        echo -e "\n${BLUE}Test MRIQC --version:${NC}"
        docker run --rm nipreps/mriqc:latest --version 2>/dev/null || \
            echo -e "${YELLOW}!${NC} Immagine MRIQC non disponibile"
    fi
else
    echo -e "${BLUE}Salta test funzionali (usa --functional per eseguirli)${NC}"
fi

# Riepilogo finale
echo -e "\n${YELLOW}═══════════════════════════════════════════${NC}"
echo -e "${YELLOW} RIEPILOGO TEST${NC}"
echo -e "${YELLOW}═══════════════════════════════════════════${NC}"

# Conta problemi
WARNINGS=0
ERRORS=0

# Controlla elementi critici
if ! command -v docker >/dev/null 2>&1; then
    ((ERRORS++))
    echo -e "${RED}✗${NC} Docker non installato (CRITICO per NiPreps)"
fi

if ! [ -f "${HOME}/neuroimaging/config/license.txt" ]; then
    ((WARNINGS++))
    echo -e "${YELLOW}!${NC} Licenza FreeSurfer mancante"
fi

if ! docker images | grep -q "nipreps/fmriprep"; then
    ((WARNINGS++))
    echo -e "${YELLOW}!${NC} Immagine fMRIPrep non scaricata"
fi

echo ""
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ INSTALLAZIONE COMPLETA E FUNZIONANTE${NC}"
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ Installazione OK con $WARNINGS avvisi${NC}"
else
    echo -e "${RED}✗ Problemi critici rilevati: $ERRORS${NC}"
fi

# Suggerimenti
if [ $WARNINGS -gt 0 ] || [ $ERRORS -gt 0 ]; then
    echo -e "\n${BLUE}AZIONI SUGGERITE:${NC}"
    
    if ! command -v docker >/dev/null 2>&1; then
        echo "1. Installa Docker: ./neuroimaging_installer.sh -p"
    fi
    
    if ! [ -f "${HOME}/neuroimaging/config/license.txt" ]; then
        echo "2. Scarica licenza FreeSurfer da:"
        echo "   https://surfer.nmr.mgh.harvard.edu/registration.html"
        echo "   Salvala in: ${HOME}/neuroimaging/config/license.txt"
    fi
    
    if ! docker images | grep -q "nipreps/fmriprep"; then
        echo "3. Scarica immagini Docker:"
        echo "   docker pull nipreps/fmriprep:24.1.1"
        echo "   docker pull nipreps/mriqc:24.0.2"
        echo "   docker pull nipreps/smriprep:0.15.0"
    fi
    
    if ! groups | grep -q docker; then
        echo "4. Aggiungi utente al gruppo docker:"
        echo "   sudo usermod -aG docker \$USER"
        echo "   Poi riavvia la sessione o esegui: newgrp docker"
    fi
fi

echo -e "\n${BLUE}Per attivare l'ambiente Python:${NC}"
echo "  micromamba activate neuroimaging"

echo -e "\n${BLUE}Per test più approfonditi:${NC}"
echo "  $0 --functional"
echo "  ./test_functionality.sh"
