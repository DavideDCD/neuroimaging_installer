#!/bin/bash
# Configurazione FSL personalizzata

# Directory FSL (modifica se necessario)
export FSLDIR="$HOME/fsl"

# Setup standard FSL
if [ -f "${FSLDIR}/etc/fslconf/fsl.sh" ]; then
    . "${FSLDIR}/etc/fslconf/fsl.sh"
fi

# Aggiungi al PATH
export PATH="${FSLDIR}/bin:${PATH}"

# Opzioni FSL personalizzate
export FSLOUTPUTTYPE="NIFTI_GZ"           # Output compresso
export FSL_SLICE_TIMES="interleaved"      # Per fMRI
export FSL_MULTI_LABEL_SEG="1"           # Segmentazione multi-label
export FSL_PARALLEL="1"                  # Parallel processing
export FSL_GRAPHICS="native"             # Backend grafico

# Performance tuning (modifica in base alla tua CPU)
export FSL_DEADLOCK_WARNING="0"
export FSL_FIX_AVX="1"
export FSL_FIX_SSE="1"

# GPU acceleration per alcune funzioni (se disponibile)
if command -v nvidia-smi >/dev/null 2>&1; then
    export FSL_GPU="1"
    export FSL_CUDA_LIB="/usr/local/cuda/lib64"
fi

# Debug mode (imposta a 0 per produzione)
export FSL_DEBUG="0"

# Log file location
export FSL_LOGDIR="${HOME}/fsl_logs"
mkdir -p "${FSL_LOGDIR}"

# Subject directory per analisi longitudinali
export FSL_SUBJECTS_DIR="${HOME}/fsl_subjects"
mkdir -p "${FSL_SUBJECTS_DIR}"

# Cache directory per risultati intermedi
export FSL_CACHEDIR="/tmp/fsl_cache_${USER}"
mkdir -p "${FSL_CACHEDIR}"

echo "✅ FSL configurato: ${FSLDIR}"
