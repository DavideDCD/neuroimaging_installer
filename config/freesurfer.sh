#!/bin/bash
# Configurazione FreeSurfer personalizzata

# Directory FreeSurfer
export FREESURFER_HOME="/opt/freesurfer"

# File licenza (MODIFICA QUESTA RIGA!)
export FS_LICENSE="${FREESURFER_HOME}/license.txt"
# OPPURE se in altra posizione:
# export FS_LICENSE="${HOME}/neuroimaging/config/license.txt"

# Verifica licenza
if [ ! -f "$FS_LICENSE" ]; then
    echo "⚠ ATTENZIONE: File licenza FreeSurfer non trovato!"
    echo "Scaricalo da: https://surfer.nmr.mgh.harvard.edu/registration.html"
    echo "E copialo in: $FS_LICENSE"
    # Non bloccare, ma avvisa
fi

# Setup standard FreeSurfer
if [ -f "${FREESURFER_HOME}/SetUpFreeSurfer.sh" ]; then
    . "${FREESURFER_HOME}/SetUpFreeSurfer.sh"
fi

# Directory soggetti
export SUBJECTS_DIR="${HOME}/freesurfer_subjects"
mkdir -p "${SUBJECTS_DIR}"

# Directory temporanea (molto importante per performance)
export TMPDIR="/tmp/freesurfer_${USER}"
mkdir -p "${TMPDIR}"

# Opzioni FreeSurfer personalizzate
export FS_FLOAT="1"                      # Usa calcoli in floating point
export FS_OVERRIDE="0"                   # Non sovrascrivere risultati esistenti
export FS_SKIP_VOL="0"                   # Non saltare volume check
export FS_FAST="1"                       # Modalità fast per recon-all
export FS_NUM_THREADS="$(nproc)"         # Usa tutti i core disponibili

# Opzioni specifiche per recon-all
export FS_RECON_ALL_OPTS="-qcache -measure thickness -measure curv -measure area -measure volume"
export FS_SURF_SMOOTH="10"               # Smoothing superficie
export FS_VOL_SMOOTH="5"                 # Smoothing volume

# Opzioni QA/QC
export FS_QA_MODE="1"                    # Abilita controllo qualità
export FS_QA_DIR="${SUBJECTS_DIR}/qa"
mkdir -p "${FS_QA_DIR}"

# Parallel processing per mris_volsmooth
export FS_PARALLEL="1"

# GPU acceleration (se supportato)
if command -v nvidia-smi >/dev/null 2>&1; then
    export FS_CUDA="1"
    # Specifica GPU da usare (0-based index)
    export FS_CUDA_DEVICE="0"
fi

# Debug e logging
export FS_DEBUG="0"
export FS_LOGDIR="${HOME}/freesurfer_logs"
mkdir -p "${FS_LOGDIR}"

# Cache per riutilizzo atlanti
export FS_CACHE_DIR="${HOME}/.freesurfer_cache"
mkdir -p "${FS_CACHE_DIR}"

echo "✅ FreeSurfer configurato: ${FREESURFER_HOME}"
echo "📁 Subject directory: ${SUBJECTS_DIR}"