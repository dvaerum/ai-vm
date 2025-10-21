#!/usr/bin/env bash

set -euo pipefail

# Detect execution context and set appropriate flake reference
if [[ "${BASH_SOURCE[0]}" == /nix/store/* ]]; then
    # Running from Nix store (via nix run)
    echo "Note: Running from Nix store"

    # Check command line arguments and environment to detect the flake source
    FLAKE_REF=""
    CURRENT_DIR="$(pwd)"

    # Method 1: Check for path: prefix in process arguments (works for nix run path:...)
    if ps -p $PPID -o args= 2>/dev/null | grep -q "path:"; then
        # Extract the path from the parent command
        PARENT_CMD=$(ps -p $PPID -o args= 2>/dev/null || echo "")
        if [[ "$PARENT_CMD" =~ path:([^[:space:]]+) ]]; then
            EXTRACTED_PATH="${BASH_REMATCH[1]}"
            # Convert relative path to absolute
            if [[ "$EXTRACTED_PATH" != /* ]]; then
                EXTRACTED_PATH="$CURRENT_DIR/$EXTRACTED_PATH"
            fi
            if [[ -f "$EXTRACTED_PATH/flake.nix" ]]; then
                FLAKE_REF="git+file://$EXTRACTED_PATH"
                SCRIPT_DIR="$EXTRACTED_PATH"
                echo "Detected path reference: $EXTRACTED_PATH"
            fi
        fi
    fi

    # Method 2: Try to extract flake reference from Nix environment
    if [[ -z "$FLAKE_REF" && -n "${NIX_ATTRS_JSON_FILE:-}" ]] && command -v jq >/dev/null 2>&1; then
        FLAKE_REF=$(jq -r '.flakeRef // empty' "${NIX_ATTRS_JSON_FILE}" 2>/dev/null || echo "")
        if [[ -n "$FLAKE_REF" ]]; then
            echo "Detected flake reference from environment: $FLAKE_REF"
        fi
    fi

    # Method 3: Check if current directory has the flake
    if [[ -z "$FLAKE_REF" && -f "$CURRENT_DIR/flake.nix" ]]; then
        FLAKE_REF="git+file://$CURRENT_DIR"
        SCRIPT_DIR="$CURRENT_DIR"
        echo "Using local flake in current directory: $CURRENT_DIR"
    fi

    # Method 3.5: Smart detection for Projects/nixos-configs/ai-vm pattern
    if [[ -z "$FLAKE_REF" ]]; then
        # Check common project locations relative to current directory
        for possible_path in \
            "$CURRENT_DIR/Projects/nixos-configs/ai-vm" \
            "$CURRENT_DIR/../nixos-configs/ai-vm" \
            "$CURRENT_DIR/nixos-configs/ai-vm"; do
            if [[ -f "$possible_path/flake.nix" ]]; then
                FLAKE_REF="git+file://$possible_path"
                SCRIPT_DIR="$possible_path"
                echo "Detected ai-vm project at: $possible_path"
                break
            fi
        done
    fi

    # Method 4: Default to github reference as fallback
    if [[ -z "$FLAKE_REF" ]]; then
        FLAKE_REF="github:dvaerum/ai-vm"
        SCRIPT_DIR="$CURRENT_DIR"
        echo "Using remote flake reference: $FLAKE_REF"
        echo "Working directory: $SCRIPT_DIR"
    fi

    # Extract directory from flake reference if it's a local path
    if [[ "$FLAKE_REF" == git+file://* ]]; then
        SCRIPT_DIR="${FLAKE_REF#git+file://}"
        echo "Using local flake: $FLAKE_REF"
        echo "Working directory: $SCRIPT_DIR"
    fi
else
    # Direct script execution
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    FLAKE_REF="git+file://$SCRIPT_DIR"
fi

# Default options (for fzf menu)
RAM_OPTIONS=("2" "4" "8" "16" "32")
CPU_OPTIONS=("1" "2" "4" "8")
STORAGE_OPTIONS=("20" "50" "100" "200")

# Default values
DEFAULT_RAM="8"
DEFAULT_CPU="2"
DEFAULT_STORAGE="50"
DEFAULT_OVERLAY="false"

# Security: Shared folder restrictions
# These directories are completely blocked from being shared due to severe security risks
BLOCKED_DIRS=(
    "/"           # Root filesystem - sharing would expose entire system
    "/boot"       # Boot files - tampering could prevent system boot
    "/sys"        # Kernel/system interface - should never be modified
    "/proc"       # Process/kernel information - runtime kernel interface
    "/dev"        # Device files - direct hardware access
)

# These directories require explicit user confirmation due to security implications
SENSITIVE_DIRS=(
    "/root"       # Root user home - contains sensitive system administrator files
    "/etc"        # System configuration - contains passwords, system settings
    "/var"        # Variable data - includes logs, databases, system state
    "/home"       # All user home directories - potentially exposes multiple users' data
    "/usr"        # System binaries - modification could compromise system integrity
    "/bin"        # Essential binaries - critical system commands
    "/sbin"       # System binaries - administrative commands
    "/lib"        # System libraries - tampering could break system
    "/lib64"      # System libraries (64-bit)
    "/opt"        # Optional software - may contain sensitive application data
)

# Security: Validate path doesn't contain characters that could break Nix expressions
# or cause security issues. Allows: alphanumeric, /, _, -, ., space
validate_path_security() {
    local path="$1"

    # Check for null bytes (potential security issue)
    if [[ "$path" == *$'\0'* ]]; then
        echo "Error: Path contains null bytes - potential security issue"
        return 1
    fi

    # Check for newlines (could break Nix expressions)
    if [[ "$path" == *$'\n'* ]]; then
        echo "Error: Path contains newlines - not allowed"
        return 1
    fi

    # Check for characters that could break Nix string literals: " $ ` \
    if [[ "$path" =~ [\"\$\`\\] ]]; then
        echo "Error: Path contains special characters that could break Nix expressions: \" \$ \` \\"
        echo "Path: $path"
        return 1
    fi

    # Warn about unusual characters (but don't block)
    if [[ "$path" =~ [^a-zA-Z0-9/_.\-\ ] ]]; then
        echo "Warning: Path contains unusual characters. This may cause issues."
        echo "Path: $path"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
    fi

    return 0
}

# Security: Check if path is a symlink to a sensitive directory
# This prevents bypassing restrictions via symlinks
check_symlink_target() {
    local path="$1"

    if [[ -L "$path" ]]; then
        local target=$(readlink -f "$path")
        echo "Warning: '$path' is a symlink to '$target'"

        # Check if target is sensitive
        for sensitive in "${BLOCKED_DIRS[@]}" "${SENSITIVE_DIRS[@]}"; do
            if [[ "$target" == "$sensitive" ]] || [[ "$target" == "$sensitive"/* ]]; then
                echo "Warning: Symlink target '$target' is in sensitive directory '$sensitive'"
                return 1
            fi
        done
    fi

    return 0
}

# Security: Validate shared directory is not in restricted locations
validate_shared_directory() {
    local path="$1"
    local share_type="$2"  # "read-write" or "read-only"

    # First check path security (special characters, etc.)
    if ! validate_path_security "$path"; then
        return 1
    fi

    # Check if path is a symlink to sensitive location
    if ! check_symlink_target "$path"; then
        echo "Error: Cannot share symlinks to sensitive directories"
        return 1
    fi

    # Get absolute path for comparison (should already be absolute from realpath)
    local abs_path="$path"

    # Check against completely blocked directories
    for blocked in "${BLOCKED_DIRS[@]}"; do
        if [[ "$abs_path" == "$blocked" ]]; then
            echo "╔════════════════════════════════════════════════════════════════════════╗"
            echo "║ SECURITY ERROR: Cannot share '$abs_path'                                "
            echo "║                                                                          "
            echo "║ This directory is critical to system operation and is blocked from      "
            echo "║ being shared for security reasons.                                      "
            echo "║                                                                          "
            echo "║ Sharing this directory could:                                           "
            echo "║   - Compromise system integrity                                         "
            echo "║   - Allow unauthorized system access                                    "
            echo "║   - Prevent system from booting                                         "
            echo "║                                                                          "
            echo "║ Safe alternatives:                                                      "
            echo "║   - Share specific subdirectories (e.g., /home/user/projects)          "
            echo "║   - Share /tmp for temporary file exchange                             "
            echo "║   - Create a dedicated directory for VM sharing                        "
            echo "╚════════════════════════════════════════════════════════════════════════╝"
            return 1
        fi
    done

    # Check against sensitive directories that require confirmation
    for sensitive in "${SENSITIVE_DIRS[@]}"; do
        if [[ "$abs_path" == "$sensitive" ]] || [[ "$abs_path" == "$sensitive"/* ]]; then
            echo "╔════════════════════════════════════════════════════════════════════════╗"
            echo "║ SECURITY WARNING: Sharing '$abs_path'                                   "
            echo "║                                                                          "
            echo "║ This directory contains sensitive system or user data.                  "
            echo "║                                                                          "
            if [[ "$share_type" == "read-write" ]]; then
                echo "║ Sharing as READ-WRITE means the VM can:                                "
                echo "║   - Modify system configurations                                       "
                echo "║   - Delete or corrupt important files                                  "
                echo "║   - Potentially compromise host system security                        "
            else
                echo "║ Sharing as READ-ONLY means the VM can:                                 "
                echo "║   - Read sensitive configuration files                                 "
                echo "║   - Access passwords or secrets (e.g., /etc/shadow, ssh keys)         "
                echo "║   - View private user data                                             "
            fi
            echo "║                                                                          "
            echo "║ Safer alternatives:                                                     "
            echo "║   - Share only specific subdirectories you need                        "
            echo "║   - Copy files to a dedicated sharing directory                        "
            echo "║   - Use /tmp for temporary file exchange                               "
            echo "╚════════════════════════════════════════════════════════════════════════╝"
            echo ""
            read -p "Are you absolutely sure you want to share this directory? (yes/NO): " -r confirmation

            # Require explicit "yes" (case-sensitive for security)
            if [[ "$confirmation" != "yes" ]]; then
                echo "Cancelled. Directory not shared."
                return 1
            fi

            echo "WARNING: Proceeding with sensitive directory sharing. Use at your own risk."
            return 0
        fi
    done

    # Path is safe
    return 0
}

# Help function
show_help() {
    cat << EOF
VM Selector - Launch Claude Code VMs with custom configurations

Usage:
  $0 [OPTIONS]                    # Interactive mode with fzf
  $0 --ram RAM --cpu CPU --storage STORAGE [--overlay]  # Direct mode

Options:
  # Hardware Configuration
  -r, --ram RAM         RAM size in GB (any positive integer, defaults: 2, 4, 8, 16, 32)
  -c, --cpu CPU         CPU cores (any positive integer, defaults: 1, 2, 4, 8)
  -s, --storage STORAGE Storage size in GB (any positive integer, defaults: 20, 50, 100, 200)

  # VM Identity
  -n, --name NAME       Custom VM name (affects qcow2 file and script names, default: ai-vm)

  # Features & Capabilities
  -a, --audio           Enable audio passthrough (microphone input + audio output)
  -o, --overlay         Enable overlay filesystem (clean state each boot)

  # Host Integration (Security Notes Below)
  --share-rw PATH       Share host directory as read-write (mounted at /mnt/host-rw/PATH in VM)
  --share-ro PATH       Share host directory as read-only (mounted at /mnt/host-ro/PATH in VM)

  # Help
  -h, --help           Show this help

Security Notes for Shared Folders:
  WARNING: Shared folders can expose sensitive data or allow VMs to modify host files

  Blocked directories (cannot be shared):
    /, /boot, /sys, /proc, /dev

  Sensitive directories (require confirmation):
    /root, /etc, /var, /home, /usr, /bin, /sbin, /lib, /lib64, /opt

  Safe sharing practices:
    ✓ Share specific project directories (e.g., /home/user/projects/myproject)
    ✓ Share /tmp for temporary file exchange
    ✓ Create dedicated directories for VM sharing
    ✗ Avoid sharing entire /home or system directories
    ✗ Avoid read-write access to sensitive directories

Examples:
  # Basic Usage
  $0                                    # Interactive mode with default options
  $0 --ram 8 --cpu 4 --storage 100     # Basic custom configuration

  # Named VMs
  $0 --name "dev-env" --ram 16 --cpu 8 --storage 200  # Named VM (creates dev-env.qcow2, start-dev-env.sh)

  # With Features
  $0 --ram 16 --cpu 8 --storage 200 --audio  # VM with audio passthrough
  $0 -r 24 -c 6 -s 75 --overlay        # Custom configuration with overlay filesystem

  # Host Integration (Safe Examples)
  $0 --ram 8 --cpu 4 --storage 100 --share-rw /home/user/projects  # Safe: specific project directory
  $0 --share-ro /home/user/docs --share-rw /tmp --ram 16 --cpu 8 --storage 200  # Safe: docs (RO) + temp (RW)

  # Host Integration (Examples Requiring Confirmation)
  $0 --share-ro /etc --ram 8 --cpu 4 --storage 100  # Requires confirmation: system config access

  # High-End Configuration
  $0 -r 128 -c 16 -s 500               # High-performance VM

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
ENABLE_AUDIO="false"

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
            resolved_path="$(realpath "$2")"
            if ! validate_shared_directory "$resolved_path" "read-write"; then
                echo "Error: Security validation failed for shared directory"
                exit 1
            fi
            SHARED_RW+=("$resolved_path")
            INTERACTIVE=false
            shift 2
            ;;
        --share-ro)
            if [[ ! -d "$2" ]]; then
                echo "Error: Directory '$2' does not exist or is not accessible"
                exit 1
            fi
            resolved_path="$(realpath "$2")"
            if ! validate_shared_directory "$resolved_path" "read-only"; then
                echo "Error: Security validation failed for shared directory"
                exit 1
            fi
            SHARED_RO+=("$resolved_path")
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
        -a|--audio)
            ENABLE_AUDIO="true"
            shift
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

# Check system resource capacity
check_system_resources() {
    local requested_ram="$1"
    local requested_cpu="$2"
    local requested_storage="$3"

    # Check available RAM (convert to GB)
    if command -v free >/dev/null 2>&1; then
        local total_ram_kb=$(free -k | awk '/^Mem:/ {print $2}')
        local total_ram_gb=$((total_ram_kb / 1024 / 1024))
        local ram_threshold=$((total_ram_gb * 80 / 100))

        if [[ "$requested_ram" -gt "$ram_threshold" ]]; then
            echo ""
            echo "Warning: Requested RAM (${requested_ram}GB) exceeds 80% of system RAM (${total_ram_gb}GB)"
            echo "System RAM: ${total_ram_gb}GB | Threshold (80%): ${ram_threshold}GB | Requested: ${requested_ram}GB"
            echo "This may cause system instability or swapping."
            echo ""

            # In interactive mode, ask for confirmation
            if [[ "$INTERACTIVE" == "true" ]]; then
                read -p "Continue anyway? [y/N]: " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    echo "Cancelled."
                    exit 0
                fi
            else
                echo "Proceeding anyway (non-interactive mode)"
            fi
        fi
    fi

    # Check available CPU cores
    if command -v nproc >/dev/null 2>&1; then
        local total_cpus=$(nproc)
        local cpu_threshold=$((total_cpus * 80 / 100))
        # Ensure threshold is at least 1
        [[ "$cpu_threshold" -lt 1 ]] && cpu_threshold=1

        if [[ "$requested_cpu" -gt "$cpu_threshold" ]]; then
            echo ""
            echo "Warning: Requested CPU cores ($requested_cpu) exceeds 80% of system CPUs ($total_cpus)"
            echo "System CPUs: $total_cpus | Threshold (80%): $cpu_threshold | Requested: $requested_cpu"
            echo "This may cause performance degradation on the host system."
            echo ""

            # In interactive mode, ask for confirmation
            if [[ "$INTERACTIVE" == "true" ]]; then
                read -p "Continue anyway? [y/N]: " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    echo "Cancelled."
                    exit 0
                fi
            else
                echo "Proceeding anyway (non-interactive mode)"
            fi
        fi
    fi

    # Check available disk space at target location
    # Note: We don't know the exact location yet, so we'll check this later
    # after VM_DIR is determined
}

# Check available disk space for VM storage
check_disk_space() {
    local vm_dir="$1"
    local requested_storage_gb="$2"

    if command -v df >/dev/null 2>&1; then
        # Get available space in KB and convert to GB
        local available_kb=$(df -k "$vm_dir" | awk 'NR==2 {print $4}')
        local available_gb=$((available_kb / 1024 / 1024))

        # Add 20% overhead for qcow2 metadata and safety margin
        local required_gb=$((requested_storage_gb * 120 / 100))

        if [[ "$available_gb" -lt "$required_gb" ]]; then
            echo ""
            echo "Error: Insufficient disk space in $vm_dir"
            echo "Available: ${available_gb}GB | Required (with 20% overhead): ${required_gb}GB | VM storage: ${requested_storage_gb}GB"
            echo ""
            echo "Free up disk space or choose a smaller storage size."
            return 1
        fi

        # Warn if using more than 80% of available space
        local space_threshold=$((available_gb * 80 / 100))
        if [[ "$requested_storage_gb" -gt "$space_threshold" ]]; then
            echo ""
            echo "Warning: Requested storage (${requested_storage_gb}GB) will use >80% of available disk space (${available_gb}GB)"
            echo ""

            # In interactive mode, ask for confirmation
            if [[ "$INTERACTIVE" == "true" ]]; then
                read -p "Continue anyway? [y/N]: " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    echo "Cancelled."
                    return 1
                fi
            else
                echo "Proceeding anyway (non-interactive mode)"
            fi
        fi
    fi

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

    # Ask about audio passthrough
    audio_options=("No audio passthrough" "Enable audio passthrough (microphone + speakers)")
    audio_choice=$(printf "%s\n" "${audio_options[@]}" | fzf --prompt="Audio: " --height=20%)
    if [[ -z "$audio_choice" ]]; then
        echo "Cancelled."
        exit 0
    fi

    if [[ "$audio_choice" == *"Enable audio"* ]]; then
        ENABLE_AUDIO="true"
    else
        ENABLE_AUDIO="false"
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
            resolved_rw_path="$(realpath "$rw_path")"
            if ! validate_shared_directory "$resolved_rw_path" "read-write"; then
                echo "Skipping directory due to security validation failure."
                continue
            fi
            SHARED_RW+=("$resolved_rw_path")
            echo "Added: $resolved_rw_path (read-write)"
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
            resolved_ro_path="$(realpath "$ro_path")"
            if ! validate_shared_directory "$resolved_ro_path" "read-only"; then
                echo "Skipping directory due to security validation failure."
                continue
            fi
            SHARED_RO+=("$resolved_ro_path")
            echo "Added: $resolved_ro_path (read-only)"
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

# Set audio status for display
if [[ "$ENABLE_AUDIO" == "true" ]]; then
    audio_status="enabled"
else
    audio_status="disabled"
fi

# Generate shared folders summary
shared_summary=""
if [[ ${#SHARED_RW[@]} -gt 0 ]]; then
    shared_summary+=", RW shares: ${#SHARED_RW[@]}"
fi
if [[ ${#SHARED_RO[@]} -gt 0 ]]; then
    shared_summary+=", RO shares: ${#SHARED_RO[@]}"
fi

# Check system resource capacity before building
check_system_resources "$selected_ram" "$selected_cpu" "$selected_storage"

# Run selected VM
echo "Starting VM: ${selected_ram}GB RAM, ${selected_cpu} CPU cores, ${selected_storage}GB storage, overlay: $overlay_status, audio: $audio_status$shared_summary"

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

# Create a dedicated VM directory for better organization
if [[ "$FLAKE_REF" == github:* ]] || [[ "$FLAKE_REF" == git+* && "$FLAKE_REF" != git+file://* ]]; then
    # For remote flakes, create VMs in a dedicated directory
    VM_DIR="$HOME/.local/share/ai-vms"

    # Validate VM_DIR is not a symlink (TOCTOU protection)
    if [[ -L "$VM_DIR" ]]; then
        echo "Error: VM directory '$VM_DIR' is a symbolic link, which is not allowed for security reasons."
        echo "Please remove the symlink and let this script create a real directory."
        exit 1
    fi

    # Create directory with proper error handling
    if ! mkdir -p "$VM_DIR" 2>/dev/null; then
        echo "Error: Failed to create VM directory: $VM_DIR"
        echo "Check permissions and ensure parent directory exists."
        exit 1
    fi

    # Validate directory was created successfully and is writable
    if [[ ! -d "$VM_DIR" ]]; then
        echo "Error: Failed to create VM directory: $VM_DIR"
        exit 1
    fi

    if [[ ! -w "$VM_DIR" ]]; then
        echo "Error: VM directory is not writable: $VM_DIR"
        echo "Current permissions: $(ls -ld "$VM_DIR" 2>/dev/null || echo "unknown")"
        exit 1
    fi

    cd "$VM_DIR" || {
        echo "Error: Failed to change to VM directory: $VM_DIR"
        exit 1
    }
    echo "VM files will be created in: $VM_DIR"
else
    # For local flakes, use the project directory
    VM_DIR="$SCRIPT_DIR"

    # Validate local directory exists and is writable
    if [[ ! -d "$VM_DIR" ]]; then
        echo "Error: Local flake directory does not exist: $VM_DIR"
        exit 1
    fi

    if [[ ! -w "$VM_DIR" ]]; then
        echo "Error: Local flake directory is not writable: $VM_DIR"
        echo "Current permissions: $(ls -ld "$VM_DIR" 2>/dev/null || echo "unknown")"
        exit 1
    fi

    cd "$VM_DIR" || {
        echo "Error: Failed to change to directory: $VM_DIR"
        exit 1
    }
fi

# Check disk space availability at VM directory
if ! check_disk_space "$VM_DIR" "$selected_storage"; then
    exit 1
fi

# Build and run custom VM using nix build
echo "Building VM with Nix..."

if ! nix build --impure --expr "
    let
      flake = builtins.getFlake \"$FLAKE_REF\";
      pkgs = flake.inputs.nixpkgs.legacyPackages.\${builtins.currentSystem};
    in
      flake.lib.\${builtins.currentSystem}.makeCustomVM $selected_ram $selected_cpu $selected_storage $overlay_flag $rw_list $ro_list \"$VM_NAME\" $ENABLE_AUDIO
"; then
    echo ""
    echo "Error: Nix build failed!"
    echo ""
    echo "Possible causes:"
    echo "  - Flake reference is invalid or inaccessible: $FLAKE_REF"
    echo "  - Network issues (if using remote flake)"
    echo "  - Insufficient disk space"
    echo "  - Nix evaluation error in VM configuration"
    echo ""
    echo "Troubleshooting steps:"
    echo "  1. Check flake reference: nix flake show \"$FLAKE_REF\""
    echo "  2. Check disk space: df -h"
    echo "  3. Try with verbose output: nix build --impure --show-trace --expr '...'"
    echo ""
    exit 1
fi

# Validate that the result symlink exists
if [[ ! -L "result" ]]; then
    echo "Error: Nix build succeeded but 'result' symlink was not created"
    echo "This is unexpected. The build may have partially failed."
    exit 1
fi

# Validate that result points to a valid directory
if [[ ! -d "result" ]]; then
    echo "Error: 'result' symlink exists but does not point to a valid directory"
    echo "Target: $(readlink result 2>/dev/null || echo "unknown")"
    exit 1
fi

# Validate that the VM binary exists
VM_BINARY="result/bin/run-${VM_NAME}-vm"
if [[ ! -f "$VM_BINARY" ]]; then
    echo "Error: VM binary not found at expected location: $VM_BINARY"
    echo "Available files in result/bin/:"
    ls -la result/bin/ 2>/dev/null || echo "  (directory not accessible)"
    exit 1
fi

# Validate that the VM binary is executable
if [[ ! -x "$VM_BINARY" ]]; then
    echo "Error: VM binary is not executable: $VM_BINARY"
    echo "Permissions: $(ls -l "$VM_BINARY" 2>/dev/null || echo "unknown")"
    exit 1
fi

echo "✓ VM built successfully"

# Create reusable bash script
STARTUP_SCRIPT="start-${VM_NAME}.sh"

# Check if startup script already exists
if [[ -f "$STARTUP_SCRIPT" ]]; then
    echo ""
    echo "Warning: Startup script '$STARTUP_SCRIPT' already exists in $VM_DIR"
    echo "This will overwrite the existing script."
    echo ""

    # In interactive mode, ask for confirmation
    if [[ "$INTERACTIVE" == "true" ]]; then
        read -p "Overwrite existing startup script? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Cancelled. VM was built but startup script was not updated."
            echo "You can still run the VM with: ./result/bin/run-${VM_NAME}-vm"
            exit 0
        fi
    else
        # In non-interactive mode, show warning and proceed
        echo "Proceeding with overwrite (use interactive mode to confirm)"
    fi
fi

echo "Creating startup script: $STARTUP_SCRIPT"

# Generate the VM startup script content
cat > "$STARTUP_SCRIPT" << EOF
#!/usr/bin/env bash

# Generated VM startup script for: $VM_NAME
# Configuration: ${selected_ram}GB RAM, ${selected_cpu} CPU cores, ${selected_storage}GB storage
# Overlay: $overlay_status, Audio: $audio_status$shared_summary
# Generated on: $(date)
# VM Directory: $VM_DIR

set -euo pipefail

SCRIPT_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)"
cd "\$SCRIPT_DIR"

# Note: The VM was built from flake: $FLAKE_REF

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
AUDIO=$ENABLE_AUDIO

echo "Starting VM: \$VM_NAME"
echo "Configuration: \${RAM_SIZE}GB RAM, \${CPU_CORES} CPU cores, \${STORAGE_SIZE}GB storage"
echo "Overlay filesystem: $overlay_status"
echo "Audio passthrough: $audio_status"
EOF

    # Add shared folder information to script
    if [[ ${#SHARED_RW[@]} -gt 0 ]]; then
        echo "echo \"Read-write shared folders:\"" >> "start-${VM_NAME}.sh"
        for path in "${SHARED_RW[@]}"; do
            echo "echo \"  Host: $path → VM: /mnt/host-rw/$(basename "$path")\"" >> "start-${VM_NAME}.sh"
        done
    fi

    if [[ ${#SHARED_RO[@]} -gt 0 ]]; then
        echo "echo \"Read-only shared folders:\"" >> "start-${VM_NAME}.sh"
        for path in "${SHARED_RO[@]}"; do
            echo "echo \"  Host: $path → VM: /mnt/host-ro/$(basename "$path") (read-only)\"" >> "start-${VM_NAME}.sh"
        done
    fi

    # Add VM execution command
    cat >> "start-${VM_NAME}.sh" << 'EOF'

echo ""
echo "SSH access: ssh -p 2222 dennis@localhost"
echo "Press Ctrl+C to stop the VM"
echo ""

# Start the VM
exec "$SCRIPT_DIR/result/bin/run-${VM_NAME}-vm"
EOF

chmod +x "start-${VM_NAME}.sh"

echo "Created files in $VM_DIR:"
echo "  - ${VM_NAME}.qcow2 (will be created when VM starts)"
echo "  - start-${VM_NAME}.sh (executable startup script)"
echo ""

# For remote execution, create a convenient symlink in the current directory
if [[ "$VM_DIR" != "$(pwd)" ]]; then
    CURRENT_DIR="$(pwd)"
    if [[ ! -e "$CURRENT_DIR/start-${VM_NAME}.sh" ]]; then
        ln -sf "$VM_DIR/start-${VM_NAME}.sh" "$CURRENT_DIR/start-${VM_NAME}.sh"
        echo "Created convenience symlink: $CURRENT_DIR/start-${VM_NAME}.sh"
        echo ""
    fi
    echo "To restart this VM later:"
    echo "  ./start-${VM_NAME}.sh (via symlink)"
    echo "  cd $VM_DIR && ./start-${VM_NAME}.sh (direct)"
    echo "  $VM_DIR/start-${VM_NAME}.sh (full path)"
else
    echo "To restart this VM later, run: ./start-${VM_NAME}.sh"
fi
echo ""
echo "Starting VM now..."
exec "./result/bin/run-${VM_NAME}-vm"