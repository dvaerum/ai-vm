# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a NixOS-based VM builder for running Claude Code and AI development environments. It uses Nix flakes to create customizable headless VMs with various hardware configurations (RAM, CPU, storage) and features (audio passthrough, shared folders, overlay filesystem).

## Architecture

### Core Components

1. **flake.nix** (lines 1-174): Main flake defining VM generation logic
   - `makeVM` function (lines 42-108): Creates VMs with parameterized hardware specs
   - `parseSize` function (lines 21-39): Converts size strings ("8gb", "2cpu") to actual values
   - Library function `makeCustomVM` (lines 119-122): Public API for creating custom VMs

2. **vm-selector.sh**: Interactive VM launcher with fzf menus or CLI arguments
   - Detects execution context (Nix store vs direct) to determine flake reference
   - Supports custom RAM/CPU/storage values beyond defaults
   - Generates reusable startup scripts (start-{VM_NAME}.sh)
   - Creates VMs in `~/.local/share/ai-vms` for remote flakes, project directory for local

3. **NixOS Module Structure** (nixos/modules/):
   - `virtualisation-parameterized.nix`: Core VM configuration with parameters
   - `packages.nix`: System packages including Claude Code, development tools
   - `users.nix`: User configuration (dennis, dvv) with passwordless access
   - `networking.nix`: Network and SSH configuration

### Key Design Patterns

**Parameterized VM Generation**: All VMs are generated dynamically from the `makeVM` function, not pre-defined. The flake uses `lib.makeCustomVM` to build VMs on-demand with any hardware configuration.

**In-VM Configuration Management**: Each VM gets a complete flake-based NixOS configuration in `/etc/nixos/` with:
- `flake.nix`: VM-specific configuration
- `configuration.nix`: Editable system configuration
- `hardware-configuration.nix`: Auto-generated hardware settings
- `rebuild` command: Wrapper for `nixos-rebuild switch --flake .#vmname`

**Shared Folders**: Uses 9p/virtio with mount tag generation (max 31 chars) combining path hash and basename. Read-only folders enforced via mount options.

**Audio Passthrough**: PulseAudio passthrough when enabled via `--audio` flag, using QEMU's `-audiodev pa` with intel-hda emulation.

## Common Development Commands

### Building and Running VMs

```bash
# Interactive VM selector (recommended)
nix run

# Direct launch with specific config
nix run .#default -- --ram 16 --cpu 8 --storage 100

# Custom VM with features
nix run .#default -- -r 8 -c 4 -s 50 --audio --overlay
nix run .#default -- --name myvm --ram 16 --cpu 4 --storage 200
nix run .#default -- --share-rw /path/to/dir --ram 8 --cpu 2 --storage 50

# Build VM manually
nix build .#vm  # Default 8GB-2CPU-50GB
./result/bin/run-ai-vm-vm

# Development shell
nix develop
```

### Testing

```bash
# Run all tests
nix flake check

# Run specific tests
nix build .#checks.x86_64-linux.integration-test      # VM selector integration tests
nix build .#checks.x86_64-linux.nixos-rebuild-test    # nixos-rebuild functionality test
nix build .#checks.x86_64-linux.unit-test              # Unit tests
```

### VM Management

```bash
# SSH into running VM
ssh -p 2222 dennis@localhost

# Inside VM: rebuild configuration after editing /etc/nixos/configuration.nix
sudo nixos-rebuild switch    # Automatically uses flakes
rebuild                      # Convenience wrapper

# Update flake inputs inside VM
nix flake update /etc/nixos

# Check flake before rebuilding
nix flake check /etc/nixos
```

## Important Implementation Details

### NixOS Rebuild Inside VMs
- VMs include a `nixos-rebuild` wrapper that automatically uses flakes (virtualisation-parameterized.nix:121-134)
- `/etc/nixos` is a writable directory (not symlinks) initialized by activation script (lines 394-425)
- Configuration files stored in `/etc/nixos-template` and copied to `/etc/nixos` on first boot
- Git repo automatically initialized in `/etc/nixos` (required for flakes)
- Users can run `sudo nixos-rebuild switch` without the `--flake` flag
- The wrapper detects `/etc/nixos/flake.nix` and automatically adds `--flake /etc/nixos#vmname`
- `rebuild` command is a convenience wrapper that handles git commits and rebuilds

### Port Forwarding
- **SSH**: Host 2222 → Guest 22
- **Development**: Host 3001 → Guest 3001, Host 9080 → Guest 9080
- Configured in virtualisation-parameterized.nix:23-27

### VM Identity and Naming
- VMs use custom names via `--name` flag (default: "ai-vm")
- Affects hostname, qcow2 filename, and startup script names
- Name must be alphanumeric with hyphens/underscores only

### Flake Reference Detection
vm-selector.sh detects flake location through multiple methods:
1. Path prefix in parent process arguments
2. NIX_ATTRS_JSON_FILE environment variable
3. Current directory flake.nix
4. Smart detection for common project paths
5. Fallback to github:dvaerum/ai-vm

### Overlay Filesystem
When `--overlay` is enabled, sets `virtualisation.writableStore = true`, making Nix store writable via overlay. Slower startup but clean state on each boot.

### Audio Implementation
Uses PulseAudio passthrough (not PipeWire). Creates audio group and adds users when `enableAudio = true`. VM name used for PulseAudio device naming.

## Modifying VMs

### Adding New Packages
Edit `nixos/modules/packages.nix` or modify `/etc/nixos/configuration.nix` inside running VM, then run `rebuild`.

### Changing Port Forwarding
Modify `virtualisation.forwardPorts` in `nixos/modules/virtualisation-parameterized.nix:23-27`.

### Adjusting Hardware Limits
Validation limits in vm-selector.sh:
- RAM: max 1024GB
- CPU: max 128 cores
- Storage: max 10TB (10000GB)

## Testing Strategy

Integration tests (tests/integration/):
- Python-based tests using pytest
- Comprehensive VM selector testing
- NixOS configuration validation

Unit tests (tests/unit.nix):
- Nix expression validation
- Module structure testing
