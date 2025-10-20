#!/usr/bin/env bash

set -euo pipefail

# Default options (for fzf menu)
RAM_OPTIONS=("2" "4" "8" "16" "32")
CPU_OPTIONS=("1" "2" "4" "8")
STORAGE_OPTIONS=("20" "50" "100" "200")

# Default values
DEFAULT_RAM="8"
DEFAULT_CPU="2"
DEFAULT_STORAGE="50"
DEFAULT_OVERLAY="false"

# Help function
show_help() {
    cat << EOF
VM Selector - Launch Claude Code VMs with custom configurations

Usage:
  $0 [OPTIONS]                    # Interactive mode with fzf
  $0 --ram RAM --cpu CPU --storage STORAGE [--overlay]  # Direct mode

Options:
  -r, --ram RAM         RAM size in GB (any positive integer, defaults: 2, 4, 8, 16, 32)
  -c, --cpu CPU         CPU cores (any positive integer, defaults: 1, 2, 4, 8)
  -s, --storage STORAGE Storage size in GB (any positive integer, defaults: 20, 50, 100, 200)
  -o, --overlay         Enable overlay filesystem (clean state each boot)
  --share-rw PATH       Share host directory as read-write (mounted at /mnt/host-rw/PATH in VM)
  --share-ro PATH       Share host directory as read-only (mounted at /mnt/host-ro/PATH in VM)
  -n, --name NAME       Custom VM name (affects qcow2 file and script names, default: ai-vm)
  -h, --help           Show this help

Examples:
  $0                                    # Interactive mode with default options
  $0 --ram 8 --cpu 4 --storage 100     # Standard configuration
  $0 -r 24 -c 6 -s 75 --overlay        # Custom configuration with overlay
  $0 -r 128 -c 16 -s 500               # High-end custom configuration
  $0 --ram 8 --cpu 4 --storage 100 --share-rw /home/user/projects  # With shared folder
  $0 --share-ro /etc --share-rw /tmp --ram 16 --cpu 8 --storage 200  # Multiple shares
  $0 --name "dev-env" --ram 16 --cpu 8 --storage 200  # Named VM (creates dev-env.qcow2, start-dev-env.sh)

Default options available in fzf menu, but you can type any custom value
EOF
}

# Parse command line arguments
INTERACTIVE=true
SELECTED_RAM=""
SELECTED_CPU=""
SELECTED_STORAGE=""
USE_OVERLAY="false"
SHARED_RW=()
SHARED_RO=()
VM_NAME="ai-vm"

while [[ $# -gt 0 ]]; do
    case $1 in
        -r|--ram)
            SELECTED_RAM="$2"
            INTERACTIVE=false
            shift 2
            ;;
        -c|--cpu)
            SELECTED_CPU="$2"
            INTERACTIVE=false
            shift 2
            ;;
        -s|--storage)
            SELECTED_STORAGE="$2"
            INTERACTIVE=false
            shift 2
            ;;
        -o|--overlay)
            USE_OVERLAY="true"
            shift
            ;;
        --share-rw)
            if [[ ! -d "$2" ]]; then
                echo "Error: Directory '$2' does not exist or is not accessible"
                exit 1
            fi
            SHARED_RW+=("$(realpath "$2")")
            INTERACTIVE=false
            shift 2
            ;;
        --share-ro)
            if [[ ! -d "$2" ]]; then
                echo "Error: Directory '$2' does not exist or is not accessible"
                exit 1
            fi
            SHARED_RO+=("$(realpath "$2")")
            INTERACTIVE=false
            shift 2
            ;;
        -n|--name)
            # Validate VM name (alphanumeric, hyphens, underscores only)
            if [[ ! "$2" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                echo "Error: VM name must contain only letters, numbers, hyphens, and underscores"
                exit 1
            fi
            VM_NAME="$2"
            INTERACTIVE=false
            shift 2
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate numeric input
validate_numeric() {
    local value="$1"
    local param_name="$2"

    # Check if it's a positive integer
    if [[ ! "$value" =~ ^[1-9][0-9]*$ ]]; then
        echo "Error: $param_name must be a positive integer. Got: '$value'"
        return 1
    fi

    # Add reasonable upper limits for safety
    case "$param_name" in
        "RAM")
            if [[ "$value" -gt 1024 ]]; then
                echo "Error: RAM size seems excessive (>1024GB). Got: ${value}GB"
                return 1
            fi
            ;;
        "CPU")
            if [[ "$value" -gt 128 ]]; then
                echo "Error: CPU core count seems excessive (>128 cores). Got: ${value} cores"
                return 1
            fi
            ;;
        "Storage")
            if [[ "$value" -gt 10000 ]]; then
                echo "Error: Storage size seems excessive (>10TB). Got: ${value}GB"
                return 1
            fi
            ;;
    esac

    return 0
}

# Interactive mode with fzf
if [[ "$INTERACTIVE" == "true" ]]; then
    # Check if fzf is available
    if ! command -v fzf &> /dev/null; then
        echo "Error: fzf is not installed. Use command line arguments instead."
        show_help
        exit 1
    fi

    # Select RAM (allow custom input)
    # Note: fzf returns exit code 1 when typing custom values, so we need to handle that
    fzf_output=$(printf "%s\n" "${RAM_OPTIONS[@]}" | fzf --prompt="Select or type RAM (GB): " --print-query --height=20% || true)
    selected_ram=$(echo "$fzf_output" | tail -1)
    [[ -z "$selected_ram" ]] && selected_ram=$(echo "$fzf_output" | head -1)
    if [[ -z "$selected_ram" ]]; then
        echo "Cancelled."
        exit 0
    fi
    if ! validate_numeric "$selected_ram" "RAM"; then
        exit 1
    fi

    # Select CPU cores (allow custom input)
    # Note: fzf returns exit code 1 when typing custom values, so we need to handle that
    fzf_output=$(printf "%s\n" "${CPU_OPTIONS[@]}" | fzf --prompt="Select or type CPU cores: " --print-query --height=20% || true)
    selected_cpu=$(echo "$fzf_output" | tail -1)
    [[ -z "$selected_cpu" ]] && selected_cpu=$(echo "$fzf_output" | head -1)
    if [[ -z "$selected_cpu" ]]; then
        echo "Cancelled."
        exit 0
    fi
    if ! validate_numeric "$selected_cpu" "CPU"; then
        exit 1
    fi

    # Select storage (allow custom input)
    fzf_output=$(printf "%s\n" "${STORAGE_OPTIONS[@]}" | fzf --prompt="Select or type storage (GB): " --print-query --height=20% || true)
    selected_storage=$(echo "$fzf_output" | tail -1)
    [[ -z "$selected_storage" ]] && selected_storage=$(echo "$fzf_output" | head -1)
    if [[ -z "$selected_storage" ]]; then
        echo "Cancelled."
        exit 0
    fi
    if ! validate_numeric "$selected_storage" "Storage"; then
        exit 1
    fi

    # Show overlay filesystem menu
    overlay_options=("No overlay (faster startup, changes persist)" "With overlay (slower startup, clean state each boot)")
    selected_overlay=$(printf "%s\n" "${overlay_options[@]}" | fzf --prompt="Nix store overlay: " --height=20%)
    if [[ -z "$selected_overlay" ]]; then
        echo "Cancelled."
        exit 0
    fi

    if [[ "$selected_overlay" == *"With overlay"* ]]; then
        USE_OVERLAY="true"
    else
        USE_OVERLAY="false"
    fi

    # Ask about shared folders
    share_options=("No shared folders" "Add shared folders")
    share_choice=$(printf "%s\n" "${share_options[@]}" | fzf --prompt="Shared folders: " --height=20%)
    if [[ -z "$share_choice" ]]; then
        echo "Cancelled."
        exit 0
    fi

    if [[ "$share_choice" == "Add shared folders" ]]; then
        echo "Adding shared folders (enter empty path to finish each type):"

        echo "Read-write shared folders:"
        while true; do
            read -p "Enter host directory path for read-write sharing (or press Enter to skip): " rw_path
            if [[ -z "$rw_path" ]]; then
                break
            fi
            if [[ ! -d "$rw_path" ]]; then
                echo "Warning: Directory '$rw_path' does not exist or is not accessible. Skipping."
                continue
            fi
            SHARED_RW+=("$(realpath "$rw_path")")
            echo "Added: $rw_path (read-write)"
        done

        echo "Read-only shared folders:"
        while true; do
            read -p "Enter host directory path for read-only sharing (or press Enter to finish): " ro_path
            if [[ -z "$ro_path" ]]; then
                break
            fi
            if [[ ! -d "$ro_path" ]]; then
                echo "Warning: Directory '$ro_path' does not exist or is not accessible. Skipping."
                continue
            fi
            SHARED_RO+=("$(realpath "$ro_path")")
            echo "Added: $ro_path (read-only)"
        done
    fi

    # Ask for VM name
    name_options=("Use default name (ai-vm)" "Specify custom name")
    name_choice=$(printf "%s\n" "${name_options[@]}" | fzf --prompt="VM name: " --height=20%)
    if [[ -z "$name_choice" ]]; then
        echo "Cancelled."
        exit 0
    fi

    if [[ "$name_choice" == "Specify custom name" ]]; then
        while true; do
            read -p "Enter VM name (letters, numbers, hyphens, underscores only): " custom_name
            if [[ -z "$custom_name" ]]; then
                echo "VM name cannot be empty."
                continue
            fi
            if [[ ! "$custom_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                echo "Error: VM name must contain only letters, numbers, hyphens, and underscores"
                continue
            fi
            VM_NAME="$custom_name"
            break
        done
    fi
else
    # Direct mode - validate all required parameters
    if [[ -z "$SELECTED_RAM" || -z "$SELECTED_CPU" || -z "$SELECTED_STORAGE" ]]; then
        echo "Error: In direct mode, --ram, --cpu, and --storage are required."
        show_help
        exit 1
    fi

    # Validate parameters
    if ! validate_numeric "$SELECTED_RAM" "RAM"; then
        exit 1
    fi

    if ! validate_numeric "$SELECTED_CPU" "CPU"; then
        exit 1
    fi

    if ! validate_numeric "$SELECTED_STORAGE" "Storage"; then
        exit 1
    fi

    selected_ram="$SELECTED_RAM"
    selected_cpu="$SELECTED_CPU"
    selected_storage="$SELECTED_STORAGE"
fi

# Set overlay status for display
if [[ "$USE_OVERLAY" == "true" ]]; then
    overlay_status="enabled"
else
    overlay_status="disabled"
fi

# Generate shared folders summary
shared_summary=""
if [[ ${#SHARED_RW[@]} -gt 0 ]]; then
    shared_summary+=", RW shares: ${#SHARED_RW[@]}"
fi
if [[ ${#SHARED_RO[@]} -gt 0 ]]; then
    shared_summary+=", RO shares: ${#SHARED_RO[@]}"
fi

# Run selected VM
echo "Starting VM: ${selected_ram}GB RAM, ${selected_cpu} CPU cores, ${selected_storage}GB storage with overlay: $overlay_status$shared_summary"

# Always build custom VM on-demand
echo "Building VM configuration..."
if [[ "$USE_OVERLAY" == "true" ]]; then
    overlay_flag="true"
else
    overlay_flag="false"
fi

# Convert arrays to Nix list format
rw_list="["
for path in "${SHARED_RW[@]}"; do
    rw_list+="\"$path\" "
done
rw_list+="]"

ro_list="["
for path in "${SHARED_RO[@]}"; do
    ro_list+="\"$path\" "
done
ro_list+="]"

# Build and run custom VM using nix build
nix build --impure --expr "
    let
      flake = builtins.getFlake \"git+file://$(pwd)\";
      pkgs = flake.inputs.nixpkgs.legacyPackages.\${builtins.currentSystem};
    in
      flake.lib.\${builtins.currentSystem}.makeCustomVM $selected_ram $selected_cpu $selected_storage $overlay_flag $rw_list $ro_list \"$VM_NAME\"
"

# Create reusable bash script
echo "Creating startup script: start-${VM_NAME}.sh"

# Generate the VM startup script content
cat > "start-${VM_NAME}.sh" << EOF
#!/usr/bin/env bash

# Generated VM startup script for: $VM_NAME
# Configuration: ${selected_ram}GB RAM, ${selected_cpu} CPU cores, ${selected_storage}GB storage
# Overlay: $overlay_status$shared_summary
# Generated on: $(date)

set -euo pipefail

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
cd "\$SCRIPT_DIR"

# Check if VM files exist
if [[ ! -f "${VM_NAME}.qcow2" ]]; then
    echo "Error: VM disk image '${VM_NAME}.qcow2' not found in current directory"
    echo "Please run this script from the directory containing the VM files"
    exit 1
fi

# VM Configuration
VM_NAME="$VM_NAME"
RAM_SIZE=$selected_ram
CPU_CORES=$selected_cpu
STORAGE_SIZE=$selected_storage
OVERLAY=$overlay_flag

echo "Starting VM: \$VM_NAME"
echo "Configuration: \${RAM_SIZE}GB RAM, \${CPU_CORES} CPU cores, \${STORAGE_SIZE}GB storage"
echo "Overlay filesystem: $overlay_status"
EOF

    # Add shared folder information to script
    if [[ ${#SHARED_RW[@]} -gt 0 ]]; then
        echo "echo \"Read-write shared folders:\"" >> "start-${VM_NAME}.sh"
        for path in "${SHARED_RW[@]}"; do
            echo "echo \"  Host: $path → VM: /mnt/host-rw$path\"" >> "start-${VM_NAME}.sh"
        done
    fi

    if [[ ${#SHARED_RO[@]} -gt 0 ]]; then
        echo "echo \"Read-only shared folders:\"" >> "start-${VM_NAME}.sh"
        for path in "${SHARED_RO[@]}"; do
            echo "echo \"  Host: $path → VM: /mnt/host-ro$path (read-only)\"" >> "start-${VM_NAME}.sh"
        done
    fi

    # Add VM execution command
    cat >> "start-${VM_NAME}.sh" << 'EOF'

echo ""
echo "SSH access: ssh -p 2222 dennis@localhost"
echo "Press Ctrl+C to stop the VM"
echo ""

# Start the VM
exec "./result/bin/run-${VM_NAME}-vm"
EOF

chmod +x "start-${VM_NAME}.sh"

echo "Created files:"
echo "  - ${VM_NAME}.qcow2 (will be created when VM starts)"
echo "  - start-${VM_NAME}.sh (executable startup script)"
echo ""
echo "To restart this VM later, run: ./start-${VM_NAME}.sh"
echo ""
echo "Starting VM now..."
exec "./result/bin/run-${VM_NAME}-vm"