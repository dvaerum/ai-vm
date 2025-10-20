#!/usr/bin/env bash

# Generated VM startup script for: ai-vm
# Configuration: 8GB RAM, 12 CPU cores, 50GB storage
# Overlay: disabled
# Generated on: Mon Oct 20 07:21:40 PM CEST 2025

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check if VM files exist
if [[ ! -f "ai-vm.qcow2" ]]; then
    echo "Error: VM disk image 'ai-vm.qcow2' not found in current directory"
    echo "Please run this script from the directory containing the VM files"
    exit 1
fi

# VM Configuration
VM_NAME="ai-vm"
RAM_SIZE=8
CPU_CORES=12
STORAGE_SIZE=50
OVERLAY=false

echo "Starting VM: $VM_NAME"
echo "Configuration: ${RAM_SIZE}GB RAM, ${CPU_CORES} CPU cores, ${STORAGE_SIZE}GB storage"
echo "Overlay filesystem: disabled"

echo ""
echo "SSH access: ssh -p 2222 dennis@localhost"
echo "Press Ctrl+C to stop the VM"
echo ""

# Start the VM
exec "./result/bin/run-${VM_NAME}-vm"
