#!/usr/bin/env bash

set -euo pipefail

# Detect execution context and set appropriate flake reference
if [[ "${BASH_SOURCE[0]}" == /nix/store/* ]]; then
    # Running from Nix store (via nix run)
    echo "Note: Running from Nix store"

    # Check command line arguments and environment to detect the flake source
    FLAKE_REF=""
    CURRENT_DIR="$(pwd)"

    # Method 1: Use NIX_FLAKE_STORE_PATH set by our wrapper
    # This is the nix store path containing the flake (with our current code)
    if [[ -n "${NIX_FLAKE_STORE_PATH:-}" ]]; then
        if [[ -f "${NIX_FLAKE_STORE_PATH}/flake.nix" ]]; then
            FLAKE_REF="path:${NIX_FLAKE_STORE_PATH}"
            SCRIPT_DIR="${NIX_FLAKE_STORE_PATH}"
            echo "Using flake: $NIX_FLAKE_STORE_PATH"
        fi
    fi

    # Method 1b: Try to find nix run in process tree (may not work due to exec)
    if [[ -z "$FLAKE_REF" ]]; then
        PARENT_CMD=""
        for pid in $PPID $(ps -o ppid= -p $PPID 2>/dev/null) $(ps -o ppid= -p $(ps -o ppid= -p $PPID 2>/dev/null) 2>/dev/null); do
            CMD=$(ps -p $pid -o args= 2>/dev/null || echo "")
            if [[ "$CMD" == *"nix"* && "$CMD" == *"run"* ]]; then
                PARENT_CMD="$CMD"
                break
            fi
        done

        # Try path: prefix first (works for nix run path:...)
        if [[ "$PARENT_CMD" =~ path:([^[:space:]#]+) ]]; then
            EXTRACTED_PATH="${BASH_REMATCH[1]}"
            if [[ "$EXTRACTED_PATH" != /* ]]; then
                EXTRACTED_PATH="$CURRENT_DIR/$EXTRACTED_PATH"
            fi
            if [[ -f "$EXTRACTED_PATH/flake.nix" ]]; then
                FLAKE_REF="git+file://$EXTRACTED_PATH"
                SCRIPT_DIR="$EXTRACTED_PATH"
                echo "Detected path reference: $EXTRACTED_PATH"
            fi
        # Try absolute path
        elif [[ "$PARENT_CMD" =~ [[:space:]](/[^[:space:]#]+) ]]; then
            EXTRACTED_PATH="${BASH_REMATCH[1]}"
            if [[ -f "$EXTRACTED_PATH/flake.nix" ]]; then
                FLAKE_REF="git+file://$EXTRACTED_PATH"
                SCRIPT_DIR="$EXTRACTED_PATH"
                echo "Detected absolute path: $EXTRACTED_PATH"
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
    CURRENT_DIR="$(pwd)"
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    FLAKE_REF="git+file://$SCRIPT_DIR"
fi

# Default options (for fzf menu)
RAM_OPTIONS=("2" "4" "8" "16" "32")
CPU_OPTIONS=("1" "2" "4" "8")
STORAGE_OPTIONS=("20" "50" "100" "200")
RESOLUTION_OPTIONS=("1280x720 (HD)" "1920x1080 (Full HD)" "2560x1440 (2K)" "3840x2160 (4K)")

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

    # Check for null bytes using grep -z (matches null-terminated strings)
    if printf '%s' "$path" | grep -qz $'[\x00]' 2>/dev/null; then
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
    # Note: In character class, - must be first, last, or escaped
    if [[ "$path" =~ [^a-zA-Z0-9/_.\-[:space:]] ]]; then
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
    cat << 'EOF'
VM Selector - Launch Claude Code VMs with custom configurations

USAGE
  nix run .#default [OPTIONS]           Interactive mode with fzf
  nix run .#default -- --ram 8 --cpu 4  Direct mode with options

OPTIONS
  Hardware:
    -r, --ram SIZE        RAM in GB (default: 8)
    -c, --cpu COUNT       CPU cores (default: 2)
    -s, --storage SIZE    Disk in GB (default: 50)

  VM Identity:
    -n, --name NAME       VM name (default: ai-vm)
                          Affects qcow2 filename and startup script

  Features:
    -d, --desktop         Enable KDE Plasma desktop (Wayland)
    --resolution WxH      Display resolution (e.g., 1920x1080)
                          Only applies when --desktop is enabled
                          Presets: 1280x720, 1920x1080, 2560x1440, 3840x2160
    -a, --audio           Enable audio passthrough
    -o, --overlay         Ephemeral mode (clean state each boot)
    --share-claude-auth   Share ~/.claude for authentication

  Port Forwarding:
    -p, --port HOST:GUEST Add port forward (can be repeated)
    --ssh-port PORT       SSH port on host (default: 2222)
    --no-default-ports    Don't include default dev ports (3001, 9080)

  Host Integration:
    --share-rw PATH       Share directory read-write
                          Mounted at /mnt/host-rw/<dirname> in VM
    --share-ro PATH       Share directory read-only
                          Mounted at /mnt/host-ro/<dirname> in VM

  Help:
    -h, --help            Show this help

SECURITY NOTES
  Blocked directories (cannot be shared):
    /  /boot  /sys  /proc  /dev

  Sensitive directories (require confirmation):
    /root  /etc  /var  /home  /usr  /bin  /sbin  /lib  /opt

  Best practices:
    ✓ Share specific project directories
    ✓ Use /tmp for temporary file exchange
    ✗ Avoid sharing entire /home or system directories

EXAMPLES
  # Interactive mode
  nix run .#default

  # Basic configuration
  nix run .#default -- --ram 8 --cpu 4 --storage 100

  # Desktop VM with audio
  nix run .#default -- --ram 16 --cpu 8 --storage 200 --desktop --audio

  # Desktop VM with specific resolution
  nix run .#default -- --ram 16 --cpu 8 --desktop --resolution 2560x1440

  # Named VM
  nix run .#default -- --name dev-vm --ram 16 --cpu 8

  # With shared folders
  nix run .#default -- --share-rw ~/projects --share-claude-auth

  # Custom port forwarding
  nix run .#default -- --ssh-port 2223 -p 8080:80 -p 5432:5432

  # Minimal ports (SSH only, no default dev ports)
  nix run .#default -- --no-default-ports

  # High-end configuration
  nix run .#default -- -r 64 -c 16 -s 500 --desktop

  # Ephemeral VM (no persistent changes)
  nix run .#default -- --ram 8 --cpu 4 --overlay

NOTES
  - In interactive mode, fzf lets you select or type custom values
  - VM disk images are stored in the current directory (local flake)
    or ~/.local/share/ai-vms/ (remote flake)
  - Use start-<name>.sh to restart a previously built VM
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
ENABLE_DESKTOP="false"
SHARE_CLAUDE_AUTH="false"
RESOLUTION=""  # Empty means auto-detect/default

# Port forwarding configuration
# Default ports: SSH (2222→22), dev servers (3001→3001, 9080→9080)
SSH_PORT="2222"
PORT_MAPPINGS=()  # Array of "host:guest" strings
USE_DEFAULT_PORTS="true"

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
        -d|--desktop)
            ENABLE_DESKTOP="true"
            shift
            ;;
        --resolution)
            # Validate resolution format (WIDTHxHEIGHT)
            if [[ ! "$2" =~ ^[0-9]+x[0-9]+$ ]]; then
                echo "Error: Resolution must be in format WIDTHxHEIGHT (e.g., 1920x1080)"
                exit 1
            fi
            RESOLUTION="$2"
            shift 2
            ;;
        --share-claude-auth)
            SHARE_CLAUDE_AUTH="true"
            shift
            ;;
        -p|--port)
            # Validate port mapping format (host:guest)
            if [[ ! "$2" =~ ^[0-9]+:[0-9]+$ ]]; then
                echo "Error: Port mapping must be in format HOST:GUEST (e.g., 8080:80)"
                exit 1
            fi
            PORT_MAPPINGS+=("$2")
            INTERACTIVE=false
            shift 2
            ;;
        --ssh-port)
            # Validate SSH port
            if [[ ! "$2" =~ ^[0-9]+$ ]]; then
                echo "Error: SSH port must be a number"
                exit 1
            fi
            SSH_PORT="$2"
            INTERACTIVE=false
            shift 2
            ;;
        --no-default-ports)
            USE_DEFAULT_PORTS="false"
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

# Validate port number
validate_port() {
    local port="$1"
    local port_type="$2"  # "host" or "guest"

    # Check valid range (1-65535)
    if [[ "$port" -lt 1 || "$port" -gt 65535 ]]; then
        echo "Error: Port $port is out of valid range (1-65535)"
        return 1
    fi

    # Warn about privileged ports on host
    if [[ "$port_type" == "host" && "$port" -lt 1024 ]]; then
        echo "Warning: Host port $port is a privileged port (<1024)"
        echo "You may need root permissions to bind to this port."
        if [[ "$INTERACTIVE" == "true" ]]; then
            read -p "Continue anyway? [y/N]: " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                return 1
            fi
        fi
    fi

    return 0
}

# Check if a host port is already in use
check_port_in_use() {
    local port="$1"

    if command -v ss >/dev/null 2>&1; then
        if ss -tuln | grep -q ":${port} "; then
            echo "Warning: Host port $port appears to be in use"
            if [[ "$INTERACTIVE" == "true" ]]; then
                read -p "Continue anyway? [y/N]: " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    return 1
                fi
            else
                echo "Proceeding anyway (non-interactive mode)"
            fi
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tuln | grep -q ":${port} "; then
            echo "Warning: Host port $port appears to be in use"
            if [[ "$INTERACTIVE" == "true" ]]; then
                read -p "Continue anyway? [y/N]: " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    return 1
                fi
            else
                echo "Proceeding anyway (non-interactive mode)"
            fi
        fi
    fi

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

    # Ask about display mode (terminal vs desktop)
    display_options=("Terminal mode (headless, SSH access)" "Desktop mode (KDE Plasma graphical environment)")
    display_choice=$(printf "%s\n" "${display_options[@]}" | fzf --prompt="Display mode: " --height=20%)
    if [[ -z "$display_choice" ]]; then
        echo "Cancelled."
        exit 0
    fi

    if [[ "$display_choice" == *"Desktop mode"* ]]; then
        ENABLE_DESKTOP="true"

        # Ask about resolution for desktop mode
        resolution_options=("Auto (default)" "${RESOLUTION_OPTIONS[@]}" "Custom resolution")
        resolution_choice=$(printf "%s\n" "${resolution_options[@]}" | fzf --prompt="Display resolution: " --height=20%)
        if [[ -z "$resolution_choice" ]]; then
            echo "Cancelled."
            exit 0
        fi

        case "$resolution_choice" in
            "Auto (default)")
                RESOLUTION=""
                ;;
            "Custom resolution")
                while true; do
                    read -p "Enter resolution (WIDTHxHEIGHT, e.g., 1920x1080): " custom_res
                    if [[ -z "$custom_res" ]]; then
                        echo "Using auto resolution."
                        RESOLUTION=""
                        break
                    fi
                    if [[ ! "$custom_res" =~ ^[0-9]+x[0-9]+$ ]]; then
                        echo "Invalid format. Use WIDTHxHEIGHT (e.g., 1920x1080)"
                        continue
                    fi
                    RESOLUTION="$custom_res"
                    break
                done
                ;;
            *)
                # Extract just the resolution part (e.g., "1920x1080" from "1920x1080 (Full HD)")
                RESOLUTION="${resolution_choice%% *}"
                ;;
        esac
    else
        ENABLE_DESKTOP="false"
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

    # Ask about Claude Code authentication sharing
    if [[ -d "$HOME/.claude" ]]; then
        claude_options=("Don't share Claude auth (will need to login in VM)" "Share Claude auth from host (no re-login)")
        claude_choice=$(printf "%s\n" "${claude_options[@]}" | fzf --prompt="Claude Code auth: " --height=20%)
        if [[ -z "$claude_choice" ]]; then
            echo "Cancelled."
            exit 0
        fi

        if [[ "$claude_choice" == *"Share Claude auth"* ]]; then
            SHARE_CLAUDE_AUTH="true"
            echo "Will share: $HOME/.claude (read-only)"
        fi
    fi

    # Ask about port configuration
    port_options=("Use default ports (SSH:2222, 3001, 9080)" "Customize ports")
    port_choice=$(printf "%s\n" "${port_options[@]}" | fzf --prompt="Port forwarding: " --height=20%)
    if [[ -z "$port_choice" ]]; then
        echo "Cancelled."
        exit 0
    fi

    if [[ "$port_choice" == "Customize ports" ]]; then
        echo ""
        echo "Port forwarding configuration:"
        echo "Default ports: SSH (2222→22), dev servers (3001→3001, 9080→9080)"
        echo ""

        # Ask about SSH port
        read -p "SSH host port [2222]: " custom_ssh_port
        if [[ -n "$custom_ssh_port" ]]; then
            if [[ ! "$custom_ssh_port" =~ ^[0-9]+$ ]]; then
                echo "Invalid port number. Using default 2222."
            else
                SSH_PORT="$custom_ssh_port"
            fi
        fi

        # Ask about default dev ports
        read -p "Include default dev ports 3001 and 9080? [Y/n]: " include_defaults
        if [[ "$include_defaults" =~ ^[Nn]$ ]]; then
            USE_DEFAULT_PORTS="false"
        fi

        # Ask for additional ports
        echo ""
        echo "Add custom port mappings (format: HOST:GUEST, e.g., 8080:80)"
        while true; do
            read -p "Add port mapping (or press Enter to finish): " port_mapping
            if [[ -z "$port_mapping" ]]; then
                break
            fi
            if [[ ! "$port_mapping" =~ ^[0-9]+:[0-9]+$ ]]; then
                echo "Invalid format. Use HOST:GUEST (e.g., 8080:80)"
                continue
            fi
            PORT_MAPPINGS+=("$port_mapping")
            echo "Added: $port_mapping"
        done
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

# Set desktop status for display
if [[ "$ENABLE_DESKTOP" == "true" ]]; then
    if [[ -n "$RESOLUTION" ]]; then
        desktop_status="KDE Plasma ($RESOLUTION)"
    else
        desktop_status="KDE Plasma (auto)"
    fi
else
    desktop_status="terminal"
fi

# Handle Claude Code authentication sharing
if [[ "$SHARE_CLAUDE_AUTH" == "true" ]]; then
    CLAUDE_DIR="$HOME/.claude"

    if [[ -d "$CLAUDE_DIR" ]]; then
        echo "Sharing Claude Code authentication from: $CLAUDE_DIR"

        # Copy .claude.json settings file into .claude/ directory so it gets shared
        # This allows the VM to access the host's Claude settings (theme, tips history, etc.)
        if [[ -f "$HOME/.claude.json" ]]; then
            cp "$HOME/.claude.json" "$CLAUDE_DIR/.settings.json"
            echo "Copied host Claude settings for VM access"
        fi

        SHARED_RO+=("$CLAUDE_DIR")
    else
        echo "Warning: --share-claude-auth specified but $CLAUDE_DIR not found"
        echo "Claude Code may not be authenticated on this host."
        read -p "Continue without Claude auth? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Cancelled."
            exit 0
        fi
    fi
fi

# Generate shared folders summary
shared_summary=""
if [[ ${#SHARED_RW[@]} -gt 0 ]]; then
    shared_summary+=", RW shares: ${#SHARED_RW[@]}"
fi
if [[ ${#SHARED_RO[@]} -gt 0 ]]; then
    shared_summary+=", RO shares: ${#SHARED_RO[@]}"
fi

# Build final port mappings list
FINAL_PORTS=()

# Always include SSH
FINAL_PORTS+=("${SSH_PORT}:22")

# Add default dev ports unless disabled
if [[ "$USE_DEFAULT_PORTS" == "true" ]]; then
    FINAL_PORTS+=("3001:3001")
    FINAL_PORTS+=("9080:9080")
fi

# Add custom port mappings
for mapping in "${PORT_MAPPINGS[@]}"; do
    FINAL_PORTS+=("$mapping")
done

# Validate all ports
echo "Validating port configuration..."
for mapping in "${FINAL_PORTS[@]}"; do
    host_port="${mapping%%:*}"
    guest_port="${mapping##*:}"

    if ! validate_port "$host_port" "host"; then
        exit 1
    fi
    if ! validate_port "$guest_port" "guest"; then
        exit 1
    fi
    if ! check_port_in_use "$host_port"; then
        exit 1
    fi
done

# Generate port summary for display
port_summary=""
for mapping in "${FINAL_PORTS[@]}"; do
    host_port="${mapping%%:*}"
    guest_port="${mapping##*:}"
    if [[ -n "$port_summary" ]]; then
        port_summary+=", "
    fi
    port_summary+="${host_port}→${guest_port}"
done

# Check system resource capacity before building
check_system_resources "$selected_ram" "$selected_cpu" "$selected_storage"

# Run selected VM
echo "Starting VM: ${selected_ram}GB RAM, ${selected_cpu} CPU cores, ${selected_storage}GB storage"
echo "Display: $desktop_status, Audio: $audio_status, Overlay: $overlay_status$shared_summary"
echo "Ports: $port_summary"

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

# Convert port mappings to Nix list of attrsets format
# Format: [ { host = 2222; guest = 22; } { host = 3001; guest = 3001; } ]
ports_list="["
for mapping in "${FINAL_PORTS[@]}"; do
    host_port="${mapping%%:*}"
    guest_port="${mapping##*:}"
    ports_list+="{ host = $host_port; guest = $guest_port; } "
done
ports_list+="]"

# Create a dedicated VM directory for better organization
# Remote flakes (github:) go to ~/.local/share/ai-vms
# Local flakes (path:, git+file://) use current directory
if [[ "$FLAKE_REF" == github:* ]]; then
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
    # For local flakes, use the current working directory (where user ran the command)
    VM_DIR="$CURRENT_DIR"

    # Validate current directory exists and is writable
    if [[ ! -d "$VM_DIR" ]]; then
        echo "Error: Current directory does not exist: $VM_DIR"
        exit 1
    fi

    if [[ ! -w "$VM_DIR" ]]; then
        echo "Error: Current directory is not writable: $VM_DIR"
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

# Format resolution for Nix (null if empty, string otherwise)
if [[ -n "$RESOLUTION" ]]; then
    resolution_nix="\"$RESOLUTION\""
else
    resolution_nix="null"
fi

if ! nix build --impure --expr "
    let
      flake = builtins.getFlake \"$FLAKE_REF\";
      pkgs = flake.inputs.nixpkgs.legacyPackages.\${builtins.currentSystem};
    in
      flake.lib.\${builtins.currentSystem}.makeCustomVM $selected_ram $selected_cpu $selected_storage $overlay_flag $rw_list $ro_list \"$VM_NAME\" $ENABLE_AUDIO $ENABLE_DESKTOP $ports_list $resolution_nix
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
# Display: $desktop_status, Audio: $audio_status, Overlay: $overlay_status$shared_summary
# Ports: $port_summary
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
DESKTOP=$ENABLE_DESKTOP

echo "Starting VM: \$VM_NAME"
echo "Configuration: \${RAM_SIZE}GB RAM, \${CPU_CORES} CPU cores, \${STORAGE_SIZE}GB storage"
echo "Display: $desktop_status"
echo "Audio passthrough: $audio_status"
echo "Overlay filesystem: $overlay_status"
echo "Port forwarding: $port_summary"
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
    cat >> "start-${VM_NAME}.sh" << EOF

echo ""
echo "SSH access: ssh -p $SSH_PORT dennis@localhost"
echo "Press Ctrl+C to stop the VM"
echo ""

# Start the VM
exec "\$SCRIPT_DIR/result/bin/run-${VM_NAME}-vm"
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