#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

show_help() {
    cat << EOF
Claude Code VM Manager

Usage: $0 <command>

Commands:
    build       Build the VM
    run         Run the VM
    ssh         SSH into the running VM
    clean       Clean build artifacts
    help        Show this help

Examples:
    $0 build    # Build the VM
    $0 run      # Start the VM
    $0 ssh      # Connect to VM via SSH

Note: You can also run 'nix run' to start the VM directly
EOF
}

build_vm() {
    echo "Building Claude Code VM..."
    nix build .#vm
    echo "VM built successfully!"
}

run_vm() {
    if [[ ! -d "result" ]]; then
        echo "VM not built yet. Building now..."
        build_vm
    fi

    echo "Starting Claude Code VM..."
    echo "Use Ctrl+C to stop the VM"
    echo "SSH access: ssh -p 2222 claude@localhost (password: claude)"
    ./result/bin/run-*-vm
}

ssh_vm() {
    echo "Connecting to Claude Code VM..."
    ssh -p 2222 claude@localhost
}

clean_vm() {
    echo "Cleaning build artifacts..."
    rm -rf result
    echo "Clean complete!"
}

case "${1:-help}" in
    build)
        build_vm
        ;;
    run)
        run_vm
        ;;
    ssh)
        ssh_vm
        ;;
    clean)
        clean_vm
        ;;
    help|*)
        show_help
        ;;
esac