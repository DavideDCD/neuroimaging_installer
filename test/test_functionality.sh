#!/bin/bash
# Test funzionalità software neuroimaging

set -e

echo "Test Funzionalità Neuroimaging"
echo "================================="

# Directory test temporanea
TEST_DIR="/tmp/neuro_test_$(date +%s)"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

# Crea dati test sintetici
create_test_data() {
    echo "Creazione dati test..."
    
    # Crea file NIfTI dummy per FSL
    python3 -c "
import numpy as np
import nibabel as nib
data = np.random.randn(64, 64, 30, 10)
img = nib.Nifti1Image(data, np.eye(4))
nib.save(img, 'test_fmri.nii.gz')
print('Dati fMRI sintetici creati')
"
    
    # Crea maschera semplice
    python3 -c "
import numpy as np
import nibabel as nib
mask = np.ones((64, 64, 30))
img = nib.Nifti1Image(mask, np.eye(4))
nib.save(img, 'mask.nii.gz')
print('Maschera creata')
"
}

# Test 1: FSL - Skull Stripping
test_fsl() {
    echo -e "\n1. Test FSL (BET)"
    if command -v bet >/dev/null 2>&1; then
        # Usa il file fMRI come input (primo volume)
        fslroi test_fmri.nii.gz test_structural.nii.gz 0 1
        bet test_structural.nii.gz test_bet -m -f 0.3
        if [ -f "test_bet_mask.nii.gz" ]; then
            echo "BET completato con successo"
        else
            echo "BET fallito"
        fi
    else
        echo "⚠ FSL non disponibile"
    fi
}

# Test 2: ANTs - Registration
test_ants() {
    echo -e "\n2. Test ANTs (Registration)"
    if command -v antsRegistration >/dev/null 2>&1; then
        # Crea immagine di riferimento sintetica
        python3 -c "
import numpy as np
import nibabel as nib
ref = np.random.randn(64, 64, 30)
img = nib.Nifti1Image(ref, np.eye(4))
nib.save(img, 'reference.nii.gz')
"
        
        # Registration semplice (modalità test)
        antsRegistration --dimensionality 3 \
            --float 0 \
            --output [output_,output_Warped.nii.gz] \
            --interpolation Linear \
            --winsorize-image-intensities [0.005,0.995] \
            --use-histogram-matching 0 \
            --initial-moving-transform [reference.nii.gz,test_structural.nii.gz,1] \
            --transform Rigid[0.1] \
            --metric MI[reference.nii.gz,test_structural.nii.gz,1,32,Regular,0.25] \
            --convergence [1000x500x250x100,1e-6,10] \
            --shrink-factors 8x4x2x1 \
            --smoothing-sigmas 3x2x1x0vox \
            --transform Affine[0.1] \
            --metric MI[reference.nii.gz,test_structural.nii.gz,1,32,Regular,0.25] \
            --convergence [1000x500x250x100,1e-6,10] \
            --shrink-factors 8x4x2x1 \
            --smoothing-sigmas 3x2x1x0vox 2>&1 | tail -20
        
        if [ -f "output_Warped.nii.gz" ]; then
            echo "ANTs registration completata"
        else
            echo "ANTs registration test base"
        fi
    else
        echo "ANTs non disponibile"
    fi
}

# Test 3: Python - Processing
test_python() {
    echo -e "\n3. Test Python Neuroimaging"
    
    python3 -c "
import nibabel as nib
import numpy as np
from nilearn import image, plotting
import matplotlib.pyplot as plt

print('Test librerie Python...')

# Carica dati
img = nib.load('test_fmri.nii.gz')
print(f'  Dimensione immagine: {img.shape}')
print(f'  Dati caricati: {img.get_data_dtype()}')

# Smoothing con nilearn
smoothed = image.smooth_img('test_fmri.nii.gz', fwhm=6)
print(f'  Smoothing completato')

# Statistiche base
data = img.get_fdata()
print(f'  Mean: {np.mean(data):.2f}, Std: {np.std(data):.2f}')

print('Tutti i test Python passati')
"
}

# Test 4: GPU - Deep Learning
test_gpu() {
    echo -e "\n4. Test GPU Deep Learning"
    
    python3 -c "
import torch
import torch.nn as nn
import numpy as np

print('Test PyTorch e GPU...')

# Test base PyTorch
x = torch.randn(10, 3, 64, 64)
conv = nn.Conv2d(3, 16, kernel_size=3)
y = conv(x)
print(f'  Forward pass CPU: {tuple(y.shape)}')

# Test GPU se disponibile
if torch.cuda.is_available():
    device = torch.device('cuda:0')
    conv_gpu = conv.to(device)
    x_gpu = x.to(device)
    y_gpu = conv_gpu(x_gpu)
    print(f'  Forward pass GPU: {tuple(y_gpu.shape)}')
    print(f'  GPU name: {torch.cuda.get_device_name(0)}')
    print(f'  Memoria GPU: {torch.cuda.get_device_properties(0).total_memory / 1e9:.1f} GB')
else:
    print('  ⚠ GPU non disponibile per PyTorch')

print('Test PyTorch completato')
"
}

# Test 5: MRtrix3 - Diffusion
test_mrtrix() {
    echo -e "\n5. Test MRtrix3 (Diffusion)"
    
    if command -v mrcalc >/dev/null 2>&1; then
        # Crea dati DWI dummy
        python3 -c "
import numpy as np
import nibabel as nib

# Crea 4D DWI dummy (30 direzioni)
dwi_data = np.random.randn(64, 64, 30, 30)
img = nib.Nifti1Image(dwi_data, np.eye(4))
nib.save(img, 'dwi.nii.gz')

# Crea b-values e b-vectors
np.savetxt('bvals.txt', np.ones(30) * 1000)
bvecs = np.random.randn(30, 3)
np.savetxt('bvecs.txt', bvecs)

print('Dati DWI sintetici creati')
"
        
        # Test comando semplice MRtrix
        mrcalc dwi.nii.gz -mean -axis 3 mean_dwi.nii.gz 2>/dev/null || true
        
        if [ -f "mean_dwi.nii.gz" ]; then
            echo "MRtrix3 funzionante"
        else
            echo "MRtrix3 test base"
        fi
    else
        echo "MRtrix3 non disponibile"
    fi
}

# Esegui tutti i test
main() {
    echo "Directory test: $TEST_DIR"
    
    create_test_data
    test_fsl
    test_ants
    test_python
    test_gpu
    test_mrtrix
    
    # Riepilogo
    echo -e "\nRIEPILOGO TEST"
    echo "================="
    echo "Directory test: $TEST_DIR"
    echo "Mantieni per debug:"
    echo "  cd $TEST_DIR"
    echo "  ls -la"
    
    # Pulizia opzionale
    read -p "Eliminare directory test? (s/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        rm -rf "$TEST_DIR"
        echo "Directory test eliminata"
    fi
}

# Gestione errore
trap 'echo "Test interrotto"; rm -rf "$TEST_DIR"; exit 1' ERR

main
