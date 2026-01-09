#!/bin/bash
# Test completo dell'installazione neuroimaging

set -e

# Colori
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${YELLOW}🧪 Neuroimaging Installation Test Suite${NC}"
echo "=========================================="

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
        echo -e "${YELLOW}⚠${NC} Licenza FreeSurfer mancante"
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

# Test 2: Python Environment
echo -e "\n${YELLOW}2. Ambiente Python${NC}"
echo "------------------------------------------"

# Attiva ambiente se necessario
if command -v micromamba >/dev/null 2>&1; then
    eval "$(micromamba shell hook --shell bash)"
    micromamba activate neuroimaging 2>/dev/null || true
fi

test_python_package "nibabel"
test_python_package "nilearn"
test_python_package "dipy"
test_python_package "torch"
test_python_package "monai"
test_python_package "numpy"
test_python_package "scipy"

# Test 3: GPU Support
echo -e "\n${YELLOW}3. Supporto GPU${NC}"
echo "------------------------------------------"

if command -v nvidia-smi >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} NVIDIA GPU rilevata"
    nvidia-smi --query-gpu=name,memory.total --format=csv
    
    # Test PyTorch CUDA
    if python -c "import torch; print(f'PyTorch CUDA: {torch.cuda.is_available()}')" 2>/dev/null; then
        echo -e "${GREEN}✓${NC} PyTorch CUDA abilitato"
    else
        echo -e "${YELLOW}⚠${NC} PyTorch CUDA non disponibile"
    fi
else
    echo -e "${YELLOW}⚠${NC} NVIDIA GPU non rilevata (modalità CPU)"
fi

# Test 4: File System e Permessi
echo -e "\n${YELLOW}4. File System e Permessi${NC}"
echo "------------------------------------------"

test_directory "${HOME}/neuroimaging"
test_directory "${HOME}/neuroimaging/data"
test_directory "${HOME}/neuroimaging/output"

# Test scrittura
TEST_FILE="${HOME}/neuroimaging/test_write.txt"
if touch "$TEST_FILE" 2>/dev/null; then
    echo -e "${GREEN}✓${NC} Permessi scrittura OK"
    rm "$TEST_FILE"
else
    echo -e "${RED}✗${NC} Problemi permessi scrittura"
fi

# Test 5: Pipeline Specifiche
echo -e "\n${YELLOW}5. Pipeline Specifiche${NC}"
echo "------------------------------------------"

# Test MS Lesions pipeline
test_command "hd-bet"
test_python_package "lst"
test_python_package "nnunet"

# Test fMRIPrep (se installato)
if command -v fmriprep >/dev/null 2>&1; then
    echo -e "${GREEN}✓${NC} fMRIPrep disponibile"
fi

# Riepilogo
echo -e "\n${YELLOW}==========================================${NC}"
echo -e "${YELLOW}🧪 TEST COMPLETATI${NC}"
echo -e "${YELLOW}==========================================${NC}"

# Suggerimenti per problemi comuni
if [ -f "${HOME}/neuroimaging/config/license.txt" ]; then
    echo -e "\n${GREEN}✅ Configurazione base OK${NC}"
else
    echo -e "\n${YELLOW}⚠ NOTE:${NC}"
    echo "1. Per FreeSurfer: scarica license.txt da:"
    echo "   https://surfer.nmr.mgh.harvard.edu/registration.html"
    echo "2. Copiala in: ${HOME}/neuroimaging/config/license.txt"
fi

echo -e "\nPer attivare l'ambiente Python:"
echo "  micromamba activate neuroimaging"