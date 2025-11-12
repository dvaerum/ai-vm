# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NixOS-based VM builder for running Claude Code and AI development environments. Creates customizable headless VMs with parameterized hardware configurations and features.

## Architecture

### Core Components

1. **flake.nix**: Main flake with `makeVM` function for parameterized VM generation
   - `lib.makeCustomVM`: Public API for creating VMs with custom specs

2. **vm-selector.sh**: Interactive VM launcher with fzf or CLI arguments
   - Auto-detects flake location (local/remote)
   - Generates reusable `start-{VM_NAME}.sh` scripts
   - VM files stored in project dir (local) or `~/.local/share/ai-vms/` (remote)

3. **nixos/modules/**: NixOS configuration modules
   - `virtualisation-parameterized.nix`: VM parameters and features
   - `packages.nix`: Claude Code and development tools
   - `users.nix`: User setup (dennis/dvv, passwordless)
   - `networking.nix`: SSH and firewall config

### Key Features

- **Dynamic VM Generation**: All VMs built on-demand via `lib.makeCustomVM` with custom hardware specs
- **In-VM Rebuilds**: `/etc/nixos` contains editable flake config, use `rebuild` command
- **Shared Folders**: 9p/virtio sharing via `--share-rw` and `--share-ro` flags
- **Claude Auth**: Use `--share-claude-auth` flag, then run `start-claude` in VM
- **Overlay Filesystem**: Writable Nix store enabling nested VM creation

## Commands

```bash
# Interactive VM selector
nix run

# Direct launch
nix run .#default -- --ram 16 --cpu 8 --storage 100
nix run .#default -- --share-claude-auth --share-rw /path/to/dir

# Build specific VM
nix build .#vm  # Default 8GB-2CPU-50GB
./result/bin/run-ai-vm-vm
```

```bash
# Run all tests
nix flake check

# Specific test suites
nix build .#checks.x86_64-linux.integration-test
nix build .#checks.x86_64-linux.nixos-rebuild-test
nix build .#checks.x86_64-linux.unit-test
```

```bash
# SSH access
ssh -p 2222 dennis@localhost

# Inside VM
rebuild                      # Rebuild after editing /etc/nixos/configuration.nix
nix flake update /etc/nixos  # Update dependencies
```

## Implementation Details

### Dynamic VM Building
- Built on-demand via `nix build --impure --expr` using detected flake reference
- Creates `result/bin/run-{VM_NAME}-vm` binary and `{VM_NAME}.qcow2` disk

### In-VM Configuration
- `/etc/nixos` writable directory with flake config (auto-initialized with git)
- `nixos-rebuild` wrapper auto-detects flakes
- `rebuild` command handles git commits and rebuilds

### Port Forwarding
- SSH: Host 2222 → Guest 22
- Development: Host 3001 → Guest 3001, Host 9080 → Guest 9080

### Flake Detection (vm-selector.sh)
1. Path prefix in process args
2. NIX_ATTRS_JSON_FILE env var
3. Current directory flake.nix
4. Smart project path detection
5. Fallback: github:dvaerum/ai-vm

### Nested VM Support
- All VMs have writable Nix store (overlay filesystem)
- Host store mounted at `/nix/.ro-store` as binary cache
- **Without `--overlay`**: Disk-based overlay (persistent)
- **With `--overlay`**: Tmpfs-based overlay (ephemeral, faster)
- Enables building VMs inside VMs efficiently

### Additional Features
- **Audio**: PulseAudio passthrough via `--audio` flag
- **Startup Scripts**: Generated `start-{VM_NAME}.sh` with embedded config

## Configuration

- **Add packages**: Edit `nixos/modules/packages.nix` or `/etc/nixos/configuration.nix`, run `rebuild`
- **Port forwarding**: Modify `virtualisation.forwardPorts` in `virtualisation-parameterized.nix`
- **Hardware limits**: RAM max 1024GB, CPU max 128, Storage max 10TB

## Security

**WARNING: Development-focused config with empty passwords and passwordless sudo. NOT for production.**

- Empty passwords, passwordless sudo, auto-login enabled
- Firewall enabled (ports 22, 3001, 9080)
- Localhost-only access via port forwarding
- See `SECURITY.md` for hardening guide

## Testing

- **Integration tests**: `comprehensive-vm-selector-test.py`, `nixos-rebuild-test.nix`
- **Unit tests**: `tests/unit.nix`
- **Manual test**: `tests/manual-nixos-rebuild-test.sh` (run inside VM)
