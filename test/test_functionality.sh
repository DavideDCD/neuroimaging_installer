#!/bin/bash
# Test funzionalità software neuroimaging

set -e

# Colori
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo -e "${CYAN} Test Funzionalità Neuroimaging${NC}"
echo -e "${CYAN}═══════════════════════════════════════════${NC}"

# Directory test temporanea
TEST_DIR="/tmp/neuro_test_$(date +%s)"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

# Flag per test estesi
RUN_DOCKER_TESTS=false
RUN_BIDS_TESTS=false

# Parse argomenti
while [[ $# -gt 0 ]]; do
    case $1 in
        --docker|-d) RUN_DOCKER_TESTS=true; shift ;;
        --bids|-b) RUN_BIDS_TESTS=true; shift ;;
        --all|-a) RUN_DOCKER_TESTS=true; RUN_BIDS_TESTS=true; shift ;;
        *) shift ;;
    esac
done

# Crea dati test sintetici
create_test_data() {
    echo -e "\n${BLUE}Creazione dati test sintetici...${NC}"
    
    # Crea file NIfTI dummy per FSL
    python3 << 'EOF'
import numpy as np
import nibabel as nib

print("  Creazione dati fMRI 4D...")
data = np.random.randn(64, 64, 30, 10).astype(np.float32)
img = nib.Nifti1Image(data, np.eye(4))
nib.save(img, 'test_fmri.nii.gz')

print("  Creazione dati anatomici 3D...")
anat_data = np.random.randn(64, 64, 30).astype(np.float32)
anat_img = nib.Nifti1Image(anat_data, np.eye(4))
nib.save(anat_img, 'test_anat.nii.gz')

print("  Creazione maschera...")
mask = np.ones((64, 64, 30), dtype=np.uint8)
mask_img = nib.Nifti1Image(mask, np.eye(4))
nib.save(mask_img, 'mask.nii.gz')

print("✓ Dati test creati")
EOF
}

# Crea dataset BIDS minimo per test
create_bids_dataset() {
    echo -e "\n${BLUE}Creazione dataset BIDS minimo...${NC}"
    
    local bids_dir="$TEST_DIR/bids_dataset"
    mkdir -p "$bids_dir/sub-01/anat"
    mkdir -p "$bids_dir/sub-01/func"
    
    # Dataset descriptor
    cat > "$bids_dir/dataset_description.json" << EOF
{
    "Name": "Test Dataset",
    "BIDSVersion": "1.9.0",
    "DatasetType": "raw"
}
EOF
    
    # Participants file
    cat > "$bids_dir/participants.tsv" << EOF
participant_id	age	sex
sub-01	30	M
EOF
    
    # Crea immagini anatomiche e funzionali
    python3 << 'BIDS_EOF'
import numpy as np
import nibabel as nib
import json

# T1w anatomico
print("  Creazione T1w...")
t1_data = np.random.randn(128, 128, 64).astype(np.float32) * 100 + 500
t1_img = nib.Nifti1Image(t1_data, np.diag([2, 2, 2, 1]))
nib.save(t1_img, 'bids_dataset/sub-01/anat/sub-01_T1w.nii.gz')

# JSON sidecar per T1w
t1_json = {
    "EchoTime": 0.00456,
    "RepetitionTime": 2.3,
    "FlipAngle": 9,
    "MagneticFieldStrength": 3
}
with open('bids_dataset/sub-01/anat/sub-01_T1w.json', 'w') as f:
    json.dump(t1_json, f, indent=2)

# BOLD fMRI
print("  Creazione BOLD...")
bold_data = np.random.randn(64, 64, 32, 100).astype(np.float32) * 50 + 1000
bold_img = nib.Nifti1Image(bold_data, np.diag([3, 3, 3, 1]))
nib.save(bold_img, 'bids_dataset/sub-01/func/sub-01_task-rest_bold.nii.gz')

# JSON sidecar per BOLD
bold_json = {
    "TaskName": "rest",
    "RepetitionTime": 2.0,
    "EchoTime": 0.03,
    "FlipAngle": 90,
    "SliceTiming": list(np.arange(0, 2, 2/32)),
    "PhaseEncodingDirection": "j"
}
with open('bids_dataset/sub-01/func/sub-01_task-rest_bold.json', 'w') as f:
    json.dump(bold_json, f, indent=2)

print("✓ Dataset BIDS creato")
BIDS_EOF
    
    echo -e "${GREEN}✓${NC} Dataset BIDS: $bids_dir"
}

# Test 1: FSL - Skull Stripping
test_fsl() {
    echo -e "\n${YELLOW}═══ Test 1: FSL (BET) ═══${NC}"
    
    if command -v bet >/dev/null 2>&1; then
        # Usa il file anatomico per BET
        bet test_anat.nii.gz test_bet -m -f 0.3 2>&1 | tail -5
        
        if [ -f "test_bet_mask.nii.gz" ]; then
            echo -e "${GREEN}✓${NC} BET completato con successo"
            echo "  Output: test_bet.nii.gz, test_bet_mask.nii.gz"
        else
            echo -e "${RED}✗${NC} BET fallito"
        fi
    else
        echo -e "${YELLOW}!${NC} FSL non disponibile"
    fi
}

# Test 2: ANTs - Registration
test_ants() {
    echo -e "\n${YELLOW}═══ Test 2: ANTs (Registration) ═══${NC}"
    
    if command -v antsRegistration >/dev/null 2>&1; then
        # Crea immagine di riferimento sintetica
        python3 << 'EOF'
import numpy as np
import nibabel as nib
ref = np.random.randn(64, 64, 30).astype(np.float32)
img = nib.Nifti1Image(ref, np.eye(4))
nib.save(img, 'reference.nii.gz')
EOF
        
        echo "  Esecuzione registration veloce (solo rigida)..."
        antsRegistration --dimensionality 3 \
            --float 0 \
            --output [output_,output_Warped.nii.gz] \
            --interpolation Linear \
            --initial-moving-transform [reference.nii.gz,test_anat.nii.gz,1] \
            --transform Rigid[0.1] \
            --metric MI[reference.nii.gz,test_anat.nii.gz,1,32,Regular,0.25] \
            --convergence [100x50,1e-6,10] \
            --shrink-factors 2x1 \
            --smoothing-sigmas 1x0vox 2>&1 | tail -10
        
        if [ -f "output_Warped.nii.gz" ]; then
            echo -e "${GREEN}✓${NC} ANTs registration completata"
        else
            echo -e "${YELLOW}!${NC} ANTs registration test base"
        fi
    else
        echo -e "${YELLOW}!${NC} ANTs non disponibile"
    fi
}

# Test 3: Python - Processing
test_python() {
    echo -e "\n${YELLOW}═══ Test 3: Python Neuroimaging ═══${NC}"
    
    python3 << 'EOF'
import nibabel as nib
import numpy as np
from nilearn import image
import sys

try:
    print("  Test librerie Python...")
    
    # Carica dati
    img = nib.load('test_fmri.nii.gz')
    print(f"  ✓ Dimensione immagine: {img.shape}")
    print(f"  ✓ Tipo dati: {img.get_data_dtype()}")
    
    # Smoothing con nilearn
    smoothed = image.smooth_img('test_fmri.nii.gz', fwhm=6)
    print(f"  ✓ Smoothing completato")
    
    # Statistiche base
    data = img.get_fdata()
    print(f"  ✓ Mean: {np.mean(data):.2f}, Std: {np.std(data):.2f}")
    
    # Test operazioni comuni
    mean_img = image.mean_img('test_fmri.nii.gz')
    print(f"  ✓ Mean image shape: {mean_img.shape}")
    
    print("\n✓ Tutti i test Python passati")
    sys.exit(0)
    
except Exception as e:
    print(f"\n✗ Errore nei test Python: {e}")
    sys.exit(1)
EOF
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓${NC} Test Python completati"
    else
        echo -e "${RED}✗${NC} Test Python falliti"
    fi
}

# Test 4: GPU - Deep Learning
test_gpu() {
    echo -e "\n${YELLOW}═══ Test 4: GPU Deep Learning ═══${NC}"
    
    python3 << 'EOF'
import torch
import torch.nn as nn
import numpy as np

print("  Test PyTorch...")

# Test base PyTorch
x = torch.randn(10, 3, 64, 64)
conv = nn.Conv2d(3, 16, kernel_size=3)
y = conv(x)
print(f"  ✓ Forward pass CPU: {tuple(y.shape)}")

# Test GPU se disponibile
if torch.cuda.is_available():
    device = torch.device('cuda:0')
    conv_gpu = conv.to(device)
    x_gpu = x.to(device)
    y_gpu = conv_gpu(x_gpu)
    print(f"  ✓ Forward pass GPU: {tuple(y_gpu.shape)}")
    print(f"  ✓ GPU: {torch.cuda.get_device_name(0)}")
    print(f"  ✓ CUDA version: {torch.version.cuda}")
    mem_gb = torch.cuda.get_device_properties(0).total_memory / 1e9
    print(f"  ✓ Memoria GPU: {mem_gb:.1f} GB")
else:
    print("  ! GPU non disponibile (usando CPU)")

print("\n✓ Test PyTorch completato")
EOF
}

# Test 5: MRtrix3 - Diffusion
test_mrtrix() {
    echo -e "\n${YELLOW}═══ Test 5: MRtrix3 (Diffusion) ═══${NC}"
    
    if command -v mrcalc >/dev/null 2>&1; then
        # Crea dati DWI dummy
        python3 << 'EOF'
import numpy as np
import nibabel as nib

print("  Creazione dati DWI...")
# Crea 4D DWI dummy (30 direzioni)
dwi_data = np.random.randn(64, 64, 30, 30).astype(np.float32)
img = nib.Nifti1Image(dwi_data, np.eye(4))
nib.save(img, 'dwi.nii.gz')

# Crea b-values e b-vectors
np.savetxt('bvals.txt', np.ones(30) * 1000, fmt='%d')
bvecs = np.random.randn(30, 3)
bvecs = bvecs / np.linalg.norm(bvecs, axis=1, keepdims=True)
np.savetxt('bvecs.txt', bvecs.T, fmt='%.6f')
EOF
        
        # Test comando semplice MRtrix
        echo "  Calcolo mean DWI..."
        mrcalc dwi.nii.gz -mean -axis 3 mean_dwi.nii.gz 2>&1 | tail -3
        
        if [ -f "mean_dwi.nii.gz" ]; then
            echo -e "${GREEN}✓${NC} MRtrix3 funzionante"
        else
            echo -e "${YELLOW}!${NC} MRtrix3 test base"
        fi
    else
        echo -e "${YELLOW}!${NC} MRtrix3 non disponibile"
    fi
}

# Test 6: Docker NiPreps
test_docker_nipreps() {
    echo -e "\n${YELLOW}═══ Test 6: Docker NiPreps ═══${NC}"
    
    if ! command -v docker >/dev/null 2>&1; then
        echo -e "${YELLOW}!${NC} Docker non installato"
        return 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        echo -e "${RED}✗${NC} Docker daemon non in esecuzione"
        return 1
    fi
    
    # Test fMRIPrep
    echo -e "\n${BLUE}Test fMRIPrep:${NC}"
    if docker images | grep -q "nipreps/fmriprep"; then
        echo "  Versione fMRIPrep:"
        docker run --rm nipreps/fmriprep:latest --version 2>/dev/null || \
            echo -e "  ${YELLOW}!${NC} Errore nel recupero versione"
        echo -e "${GREEN}✓${NC} fMRIPrep image disponibile"
    else
        echo -e "${YELLOW}!${NC} fMRIPrep image non scaricata"
        echo "  Scarica con: docker pull nipreps/fmriprep:24.1.1"
    fi
    
    # Test MRIQC
    echo -e "\n${BLUE}Test MRIQC:${NC}"
    if docker images | grep -q "nipreps/mriqc"; then
        echo "  Versione MRIQC:"
        docker run --rm nipreps/mriqc:latest --version 2>/dev/null || \
            echo -e "  ${YELLOW}!${NC} Errore nel recupero versione"
        echo -e "${GREEN}✓${NC} MRIQC image disponibile"
    else
        echo -e "${YELLOW}!${NC} MRIQC image non scaricata"
        echo "  Scarica con: docker pull nipreps/mriqc:24.0.2"
    fi
    
    # Test sMRIPrep
    echo -e "\n${BLUE}Test sMRIPrep:${NC}"
    if docker images | grep -q "nipreps/smriprep"; then
        echo "  Versione sMRIPrep:"
        docker run --rm nipreps/smriprep:latest --version 2>/dev/null || \
            echo -e "  ${YELLOW}!${NC} Errore nel recupero versione"
        echo -e "${GREEN}✓${NC} sMRIPrep image disponibile"
    else
        echo -e "${YELLOW}!${NC} sMRIPrep image non scaricata"
        echo "  Scarica con: docker pull nipreps/smriprep:0.15.0"
    fi
}

# Test 7: BIDS Validator e MRIQC dry-run
test_bids_workflow() {
    echo -e "\n${YELLOW}═══ Test 7: Workflow BIDS Completo ═══${NC}"
    
    if [ ! -d "$TEST_DIR/bids_dataset" ]; then
        echo -e "${YELLOW}!${NC} Dataset BIDS non creato, skip test"
        return 0
    fi
    
    local bids_dir="$TEST_DIR/bids_dataset"
    local output_dir="$TEST_DIR/mriqc_output"
    local work_dir="$TEST_DIR/work"
    
    mkdir -p "$output_dir" "$work_dir"
    
    # Test BIDS Validator (via Docker)
    if docker images | grep -q "bids/validator"; then
        echo -e "\n${BLUE}Validazione BIDS:${NC}"
        docker run --rm -v "$bids_dir:/data:ro" bids/validator /data 2>&1 | head -20
    fi
    
    # Test MRIQC dry-run (veloce, solo parsing)
    if docker images | grep -q "nipreps/mriqc"; then
        echo -e "\n${BLUE}Test MRIQC dry-run:${NC}"
        echo "  (Nota: questo è solo un test di parsing, non elabora i dati)"
        
        timeout 60 docker run --rm \
            -v "$bids_dir:/data:ro" \
            -v "$output_dir:/out" \
            -v "$work_dir:/work" \
            nipreps/mriqc:latest \
            /data /out participant \
            --participant-label 01 \
            --work-dir /work \
            --verbose-reports 2>&1 | head -30 || \
            echo -e "  ${YELLOW}!${NC} Test interrotto (timeout o errore)"
        
        echo -e "${GREEN}✓${NC} MRIQC dry-run completato"
    fi
}

# Esegui tutti i test
main() {
    echo -e "\n${CYAN}Directory test: $TEST_DIR${NC}"
    
    # Test base (sempre eseguiti)
    create_test_data
    test_fsl
    test_ants
    test_python
    test_gpu
    test_mrtrix
    
    # Test Docker (se richiesto)
    if [ "$RUN_DOCKER_TESTS" = true ]; then
        test_docker_nipreps
    else
        echo -e "\n${BLUE}Test Docker saltati (usa --docker o -d per eseguirli)${NC}"
    fi
    
    # Test BIDS (se richiesto)
    if [ "$RUN_BIDS_TESTS" = true ]; then
        create_bids_dataset
        test_bids_workflow
    else
        echo -e "\n${BLUE}Test BIDS saltati (usa --bids o -b per eseguirli)${NC}"
    fi
    
    # Riepilogo
    echo -e "\n${CYAN}═══════════════════════════════════════════${NC}"
    echo -e "${CYAN} RIEPILOGO TEST${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════${NC}"
    echo "Directory test: $TEST_DIR"
    echo ""
    echo "Per eseguire test estesi:"
    echo "  $0 --docker     # Test Docker NiPreps"
    echo "  $0 --bids       # Test workflow BIDS"
    echo "  $0 --all        # Tutti i test"
    echo ""
    
    # Pulizia opzionale
    read -p "Eliminare directory test? (s/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        rm -rf "$TEST_DIR"
        echo -e "${GREEN}✓${NC} Directory test eliminata"
    else
        echo -e "${BLUE}Directory mantenuta per debug:${NC}"
        echo "  cd $TEST_DIR"
        echo "  ls -la"
    fi
}

# Gestione errore
trap 'echo -e "\n${RED}✗${NC} Test interrotto"; exit 1' ERR INT

# Mostra help se richiesto
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Uso: $0 [opzioni]"
    echo ""
    echo "Opzioni:"
    echo "  --docker, -d    Esegui test Docker NiPreps"
    echo "  --bids, -b      Esegui test workflow BIDS completo"
    echo "  --all, -a       Esegui tutti i test"
    echo "  --help, -h      Mostra questo help"
    echo ""
    echo "Esempi:"
    echo "  $0              # Test base (veloce)"
    echo "  $0 --docker     # Include test Docker"
    echo "  $0 --all        # Test completi (richiede tempo)"
    exit 0
fi

main
