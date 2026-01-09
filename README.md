# Neuroimaging Environment Toolkit (NET)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.8+](https://img.shields.io/badge/python-3.8+-blue.svg)](https://www.python.org/downloads/)
[![Platform](https://img.shields.io/badge/platform-Linux%20|%20macOS-lightgrey.svg)]()
[![Docker Ready](https://img.shields.io/badge/docker-ready-blue.svg)](https://www.docker.com/)

**Un toolkit completo per configurare ambienti di elaborazione neuroimaging con un solo comando**

NET automatizza l'installazione e la configurazione di tutti i principali software di neuroimaging (FSL, FreeSurfer, ANTs, AFNI, MRtrix3, SPM) insieme a un ambiente Python ottimizzato per analisi avanzate, deep learning e ricerca in neuroscienze.

---

## Caratteristiche Principali

### **Installazione Automatica**
- **20+ software neuroimaging** preconfigurati
- **Gestione dipendenze** automatica per Ubuntu/Debian/CentOS
- **Modalità silenziosa** per deployment senza interazione
- **Verifica versioni** e aggiornamenti automatici

### **Ambiente Python Ottimizzato**
- **Micromamba** per gestione ambienti leggera e veloce
- **250+ pacchetti** preconfigurati per neuroimaging
- **Supporto GPU** completo (CUDA, PyTorch, MONAI)
- **Ambienti riproducibili** tramite file YAML

### **Containerizzazione**
- **Dockerfile** preconfigurato per ambienti isolati
- **Singolo comando** per creare container
- **Portabilità** garantita tra sistemi
- **Versionamento** degli ambienti

### **Gestione Versioni Avanzata**
- **Sistema di tracking** versioni software
- **Controllo aggiornamenti** automatico
- **Report dettagliati** dello stato installazione
- **Backup/Ripristino** configurazioni

---

## Software Inclusi

### Neuroimaging Tradizionale
| Software | Versione | Descrizione |
|----------|----------|-------------|
| **FSL** | 6.0.7.1 | FMRIB Software Library per analisi MRI |
| **FreeSurfer** | 7.4.1 | Ricostruzione superficie cerebrale |
| **ANTs** | 2.5.3 | Advanced Normalization Tools |
| **AFNI** | latest | Analisi fMRI funzionale |
| **MRtrix3** | 3.0.3 | Trattografia e analisi connectoma |
| **SPM** | 12 | Statistical Parametric Mapping |
| **Convert3D** | 1.4.0 | Elaborazione immagini medicali |
| **CONN** | 22.a | Analisi connettività funzionale |

### Python Ecosystem
- **Deep Learning**: PyTorch, MONAI, nnU-Net, HD-BET
- **Analisi dati**: Nilearn, Dipy, Nibabel, Nipype
- **Visualizzazione**: Mayavi, PyVista, Matplotlib 3D
- **Pipeline**: fMRIPrep, MRIQC, sMRIPrep

---

## Installazione Rapida

### Prerequisiti
- Sistema Linux (Ubuntu 20.04+, CentOS 7+)
- 20GB spazio disco libero
- 8GB RAM (16GB raccomandati)
- Connessione internet

### 1. Installazione Base (Tutto automatico)

# Download dello script
wget https://raw.githubusercontent.com/tuorepo/neuroimaging-toolkit/main/neuroimaging_installer.sh
chmod +x neuroimaging_installer.sh

# Installa TUTTO (-a) in modalità silenziosa (-y)
sudo ./neuroimaging_installer.sh -a -y

### 2. Installazione Selettiva
# Solo FSL e FreeSurfer
./neuroimaging_installer.sh -f -r

# Tutto tranne SPM
./neuroimaging_installer.sh -a -y --no-spm

# Solo ambiente Python
./neuroimaging_installer.sh -d -y

# Solo fMRIPrep-Docker
./neuroimaging_installer.sh -p

# Dopo l'installazione, usa lo script helper
~/neuroimaging/bin/run_fmriprep.sh -b /data/bids -o /data/derivatives -p sub-01

# Installa l'intera suite NiPreps
./neuroimaging_installer.sh -p -q -e

# Prima esegui MRIQC per quality control
~/neuroimaging/bin/run_mriqc.sh -b /data/bids -o /data/mriqc

# Poi esegui fMRIPrep per preprocessing completo
~/neuroimaging/bin/run_fmriprep.sh -b /data/bids -o /data/derivatives -p sub-01

# Oppure solo sMRIPrep per anatomical
~/neuroimaging/bin/run_smriprep.sh -b /data/bids -o /data/derivatives -p sub-01

### 3. Con Docker (Consigliato per riproducibilità)
# Build dell'immagine
docker build -t neuroimaging:latest .

# Esegui container
docker run -it --rm \
  -v $(pwd)/data:/data \
  -v $(pwd)/output:/output \
  neuroimaging:latest

## UTILIZZO AVANZATO

## Gestione Ambienti Conda/Mamba
# Attiva ambiente neuroimaging
micromamba activate neuroimaging

# Installa pacchetti aggiuntivi
micromamba install -c conda-forge <package>

# Esporta ambiente
micromamba env export > custom_env.yml

## Sistema di Aggiornamento
# Controlla aggiornamenti disponibili
./update_versions.sh --check-only

# Aggiorna automaticamente
./update_versions.sh --auto

# Genera report versioni
./update_versions.sh --report

## Personalizzazione

# File configurazione personalizzata
cp config/template.json my_config.json

# Modifica versioni e impostazioni
./neuroimaging_installer.sh -u my_config.json

# Installa in directory custom
export NEUROIMAGING_DIR=/opt/my_neuro
./neuroimaging_installer.sh -a -y

## Verifica Installazione
Dopo l'installazione, esegui il test suite:
./tests/test_installation.sh

Output atteso:

✓ FSL installato correttamente
✓ FreeSurfer licenza configurata
✓ ANTs disponibile nel PATH
✓ Ambiente Python funzionante
✓ GPU rilevata e configurata

### Configurazione GPU

## Verifica Supporto CUDA
./neuroimaging_installer.sh --check-gpu

## Installazione con GPU Support

# Installa con supporto CUDA 12
./neuroimaging_installer.sh -a -y --cuda-version 12.6

# Solo deep learning (PyTorch + MONAI)
./neuroimaging_installer.sh --deep-learning --gpu

## Benchmark GPU
python tests/benchmark_gpu.py --mode full

### Risoluzione Problemi

## Problemi Comuni

    "License not found for FreeSurfer"

# Scarica licenza da: https://surfer.nmr.mgh.harvard.edu/registration.html
cp ~/Downloads/license.txt config/license.txt
./neuroimaging_installer.sh --configure-freesurfer

## Spazio disco insufficiente

# Cambia directory installazione
export NEUROIMAGING_DIR=/big_disk/neuroimaging
./neuroimaging_installer.sh --minimal

## Problemi dipendenze Python

# Ricrea ambiente da zero
micromamba remove -n neuroimaging --all
micromamba env create -f neuroimaging_env.yml

## Log e Debug

# Log dettagliato installazione
./neuroimaging_installer.sh -a -y --verbose 2>&1 | tee install.log

# Test specifico software
./tests/test_software.sh fsl
./tests/test_software.sh freesurfer

### Contribuire

## Setup Sviluppo

# Fork e clone repository
git clone https://github.com/tuorepo/neuroimaging-toolkit.git
cd neuroimaging-toolkit

## Linee Guida

    Branch naming: feature/descrizione o fix/issue

    Commit messages: Usa Conventional Commits

    Testing: Aggiungi test per nuove funzionalità

    Documentazione: Aggiorna README e esempi

### Licenza

Questo progetto è rilasciato sotto licenza MIT. Vedi il file LICENSE per dettagli.
Attribuzioni

    FSL: University of Oxford

    FreeSurfer: MGH

    ANTs: Apache 2.0

    AFNI: NIH

### Ringraziamenti

   # FSL Team - FMRIB, University of Oxford

   # FreeSurfer Team - Martinos Center, MGH

   # ANTs Developers - University of Pennsylvania

   # Tutta la comunità neuroimaging open-source
