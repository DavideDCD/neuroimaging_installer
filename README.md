# Neuroimaging Environment Toolkit (NET)

[![Licence: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

[![Python 3.8+](https://img.shields.io/badge/python-3.8+-blue.svg)](https://www.python.org/downloads/)

[![Platform](https://img.shields.io/badge/platform-Linux%20|%20macOS-lightgrey.svg)]()

[![Docker Ready](https://img.shields.io/badge/docker-ready-blue.svg)](https://www.docker.com/)

**A complete toolkit for setting up neuroimaging processing environments with a single command**

NET automates the installation and configuration of all major neuroimaging software (FSL, FreeSurfer, ANTs, AFNI, MRtrix3, SPM) along with a Python environment optimised for advanced analysis, deep learning, and neuroscience research.

---

## Key Features

### **Automatic Installation**

- **20+ neuroimaging software packages** preconfigured

- Automatic **dependency management** for Ubuntu/Debian/CentOS

- **Silent mode** for deployment without interaction

- Automatic **version checking** and updates

### **Optimised Python Environment**

- **Micromamba** for lightweight and fast environment management

- **250+ packages** preconfigured for neuroimaging

- Full **GPU support** (CUDA, PyTorch, MONAI)

- **Reproducible environments** via YAML files

### **Containerisation**

- Preconfigured **Dockerfile** for isolated environments

- **Single command** to create containers

- Guaranteed **portability** between systems

- **Versioning** of environments

### **Advanced Version Management**

- Software version **tracking system**

- Automatic **update control**

- Detailed **reports** on installation status

- Configuration **backup/restore**

---

## Included Software

### Traditional Neuroimaging

| Software | Version | Description |

|----------|----------|-------------|

| **FSL** | 6.0.7.1 | FMRIB Software Library for MRI analysis |

| **FreeSurfer** | 7.4.1 | Brain surface reconstruction |

| **ANTs** | 2.5.3 | Advanced Normalisation Tools |

| **AFNI** | latest | Functional fMRI analysis |

| **MRtrix3** | 3.0.3 | Tractography and connectome analysis |

| **SPM** | 12 | Statistical Parametric Mapping |

| **Convert3D** | 1.4.0 | Medical image processing |

| **CONN** | 22.a | Functional connectivity analysis |

### Python Ecosystem

- **Deep Learning**: PyTorch, MONAI, nnU-Net, HD-BET

- **Data Analysis**: Nilearn, Dipy, Nibabel, Nipype

- **Visualisation**: Mayavi, PyVista, Matplotlib 3D

- **Pipeline**: fMRIPrep, MRIQC, sMRIPrep

---

## Quick Installation

### Prerequisites

- Linux system (Ubuntu 20.04+, CentOS 7+)

- 20GB free disk space

- 8GB RAM (16GB recommended)

- Internet connection

### 1. Basic Installation (Fully automatic)

# Download the script

wget https://raw.githubusercontent.com/tuorepo/neuroimaging-toolkit/main/neuroimaging_installer.sh

chmod +x neuroimaging_installer.sh

# Install EVERYTHING (-a) in silent mode (-y)

sudo ./neuroimaging_installer.sh -a -y

### 2. Selective Installation

# Only FSL and FreeSurfer

./neuroimaging_installer.sh -f -r

# Everything except SPM

./neuroimaging_installer.sh -a -y --no-spm

# Python environment only

./neuroimaging_installer.sh -d -y

# fMRIPrep-Docker only

./neuroimaging_installer.sh -p

# After installation, use the helper script

~/neuroimaging/bin/run_fmriprep.sh -b /data/bids -o /data/derivatives -p sub-01

# Install the entire NiPreps suite

./neuroimaging_installer.sh -p -q -e

# First run MRIQC for quality control

~/neuroimaging/bin/run_mriqc.sh -b /data/bids -o /data/mriqc

# Then run fMRIPrep for complete preprocessing

~/neuroimaging/bin/run_fmriprep.sh -b /data/bids -o /data/derivatives -p sub-01

# Or just sMRIPrep for anatomical

~/neuroimaging/bin/run_smriprep.sh -b /data/bids -o /data/derivatives -p sub-01

### 3. With Docker (Recommended for reproducibility)

# Build the image

docker build -t neuroimaging:latest .

# Run container

docker run -it --rm \

  -v $(pwd)/data:/data \

  -v $(pwd)/output:/output \

  neuroimaging:latest

## ADVANCED USE

## Conda/Mamba Environment Management

# Activate neuroimaging environment

micromamba activate neuroimaging

# Install additional packages

micromamba install -c conda-forge <package>

# Export environment

micromamba env export > custom_env.yml

## Update System

# Check for available updates

./update_versions.sh --check-only

# Update automatically

./update_versions.sh --auto

# Generate version report

./update_versions.sh --report

## Customisation

# Custom configuration file

cp config/template.json my_config.json

# Modify versions and settings

./neuroimaging_installer.sh -u my_config.json

# Install in custom directory

export NEUROIMAGING_DIR=/opt/my_neuro

./neuroimaging_installer.sh -a -y

## Verify Installation

After installation, run the test suite:

./tests/test_installation.sh

Expected output:

✓ FSL installed correctly

✓ FreeSurfer licence configured

✓ ANTs available in PATH

✓ Python environment working

✓ GPU detected and configured

### GPU Configuration

## Check CUDA Support

./neuroimaging_installer.sh --check-gpu

## Installation with GPU Support

# Install with CUDA 12 support

./neuroimaging_installer.sh -a -y --cuda-version 12.6

# Deep learning only (PyTorch + MONAI)

./neuroimaging_installer.sh --deep-learning --gpu

## GPU Benchmark

python tests/benchmark_gpu.py --mode full

### Troubleshooting

## Common Problems

    ‘Licence not found for FreeSurfer’

# Download licence from: https://surfer.nmr.mgh.harvard.edu/registration.html

cp ~/Downloads/license.txt config/license.txt

./neuroimaging_installer.sh --configure-freesurfer

## Insufficient disk space

# Change installation directory

export NEUROIMAGING_DIR=/big_disk/neuroimaging

## Python dependency issues

# Recreate environment from scratch

micromamba remove -n neuroimaging --all

micromamba env create -f neuroimaging_env.yml

## Logging and debugging

# Detailed installation log

./neuroimaging_installer.sh -a -y --verbose 2>&1 | tee install.log

# Specific software test

./tests/test_software.sh fsl

./tests/test_software.sh freesurfer

### Contribute

## Development Setup

# Fork and clone repository

git clone https://github.com/tuorepo/neuroimaging-toolkit.git

cd neuroimaging-toolkit

## Guidelines

    Branch naming: feature/description or fix/issue

    Commit messages: Use Conventional Commits

    Testing: Add tests for new features

    Documentation: Update README and examples

### Licence

This project is released under the MIT licence. See the LICENCE file for details.

Attributions

    FSL: University of Oxford

    FreeSurfer: MGH

    ANTs: Apache 2.0

    AFNI: NIH

### Acknowledgements

   # FSL Team - FMRIB, University of Oxford

   # FreeSurfer Team - Martinos Centre, MGH

   # ANTs Developers - University of Pennsylvania

   # The entire open-source neuroimaging community
