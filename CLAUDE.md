# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

NixOS-based VM builder for running Claude Code and AI development environments. Creates customizable headless VMs with parameterized hardware configurations and features.

## Architecture

### Core Components

1. **flake.nix**: Main flake with `makeVM` function for parameterized VM generation
   - `lib.makeCustomVM`: Public API for creating VMs with custom specs
   - `makeVM`: Internal function accepting string parameters like "8gb", "2cpu", "50gb"

2. **vm-selector.sh**: Interactive VM launcher with fzf or CLI arguments
   - Auto-detects flake location (local/remote)
   - Generates reusable `start-{VM_NAME}.sh` scripts
   - VM files stored in project dir (local) or `~/.local/share/ai-vms/` (remote)
   - Extensive security validation for shared folders

3. **nixos/modules/**: NixOS configuration modules
   - `virtualisation-parameterized.nix`: VM parameters, overlay filesystem, shared folders
   - `packages.nix`: Claude Code and development tools (Node.js, Python, Rust, Go)
   - `users.nix`: User setup (dennis/dvv, passwordless sudo, auto-login)
   - `networking.nix`: SSH and firewall config

### Key Features

- **Dynamic VM Generation**: All VMs built on-demand via `lib.makeCustomVM` with custom hardware specs
- **In-VM Rebuilds**: `/etc/nixos` contains editable flake config, use `rebuild` command
- **Shared Folders**: 9p/virtio sharing via `--share-rw` and `--share-ro` flags
- **Claude Auth**: Use `--share-claude-auth` flag, then run `start-claude` in VM
- **Overlay Filesystem**: Writable Nix store enabling nested VM creation
- **Audio Passthrough**: PulseAudio support via `--audio` flag

## Commands

### Building and Running VMs

```bash
# Interactive VM selector (recommended)
nix run

# Direct launch with parameters
nix run .#default -- --ram 16 --cpu 8 --storage 100
nix run .#default -- --share-claude-auth --share-rw /path/to/dir
nix run .#default -- --name custom-vm --audio --overlay

# Build specific VM
nix build .#vm  # Default 8GB-2CPU-50GB
./result/bin/run-ai-vm-vm
```

### Testing

```bash
# Run all tests
nix flake check

# Specific test suites
nix build .#checks.x86_64-linux.integration-test
nix build .#checks.x86_64-linux.nixos-rebuild-test
nix build .#checks.x86_64-linux.nested-vm-test
nix build .#checks.x86_64-linux.start-script-test
nix build .#checks.x86_64-linux.unit-test

# Manual tests (run inside VM)
/home/dennis/Projects/nixos-configs/ai-vm/tests/manual-nixos-rebuild-test.sh
```

### VM Usage

```bash
# SSH access
ssh -p 2222 dennis@localhost  # or dvv@localhost

# Inside VM - rebuild after configuration changes
rebuild                      # Convenience command with git commit
sudo nixos-rebuild switch    # Direct rebuild (auto-detects flakes)
nix flake update /etc/nixos  # Update dependencies

# Claude Code (when using --share-claude-auth)
start-claude  # Copies auth from host and launches Claude with bypass permissions
```

## Implementation Details

### Dynamic VM Building
- Built on-demand via `nix build --impure --expr` using detected flake reference
- Creates `result/bin/run-{VM_NAME}-vm` binary and `{VM_NAME}.qcow2` disk image
- Validates system resources (warns if >80% RAM/CPU usage)
- Checks available disk space with 20% overhead margin

### In-VM Configuration
- `/etc/nixos` writable directory with flake config (auto-initialized with git)
- Files auto-copied from templates: `flake.nix`, `configuration.nix`, `hardware-configuration.nix`, `rebuild`, `README.md`
- `nixos-rebuild` wrapper auto-detects flakes and adds `--flake /etc/nixos#${vmName}`
- `rebuild` command: handles git operations and provides helpful error messages

### Port Forwarding
- SSH: Host 2222 → Guest 22
- Development: Host 3001 → Guest 3001, Host 9080 → Guest 9080

### Flake Detection Order (vm-selector.sh)
1. Path prefix in process args (for `nix run path:...`)
2. NIX_ATTRS_JSON_FILE env var
3. Current directory flake.nix
4. Smart project path detection (./Projects/nixos-configs/ai-vm patterns)
5. Fallback: github:dvaerum/ai-vm

### Nested VM Support
- All VMs have writable Nix store (overlay filesystem)
- Host store mounted at `/nix/.ro-store` as binary cache
- **Without `--overlay`**: Disk-based overlay (persistent, default)
- **With `--overlay`**: Tmpfs-based overlay (ephemeral, faster boot)
- Enables building VMs inside VMs efficiently

### Shared Folder Security
- **Blocked directories**: /, /boot, /sys, /proc, /dev (cannot share)
- **Sensitive directories**: /root, /etc, /var, /home, /usr, /bin, /sbin, /lib, /opt (require confirmation)
- Path validation: checks for null bytes, newlines, special characters
- Symlink detection: prevents bypassing restrictions via symlinks

### Claude Code Integration
- `start-claude` wrapper script:
  - Copies `.credentials.json` from `/mnt/host-ro/.claude/`
  - Copies settings and other Claude files
  - Runs with `--dangerously-skip-permissions --permission-mode bypassPermissions`

## Configuration

- **Add packages**: Edit `nixos/modules/packages.nix` or `/etc/nixos/configuration.nix`, then run `rebuild`
- **Port forwarding**: Modify `virtualisation.forwardPorts` in `virtualisation-parameterized.nix`
- **Hardware limits**: RAM max 1024GB, CPU max 128, Storage max 10TB
- **VM naming**: Use `--name` flag to create distinct VMs with separate disk images

## Security

**WARNING: Development-focused config with empty passwords and passwordless sudo. NOT for production.**

- Empty passwords for dennis/dvv users
- Passwordless sudo for wheel group
- Auto-login enabled for convenience
- Firewall enabled (ports 22, 3001, 9080)
- Localhost-only access via port forwarding
- See `SECURITY.md` for comprehensive security documentation and hardening guide

## Testing Structure

- **Integration tests**:
  - `comprehensive-vm-selector-test.py`: Full vm-selector.sh validation
  - `nixos-rebuild-test.nix`: Tests rebuild functionality in VM
  - `nested-vm-test.nix`: Validates nested VM creation
  - `start-script-test.nix`: Tests generated startup scripts
- **Unit tests**: `tests/unit.nix` - Nix expression evaluations
- **Manual tests**: Scripts for interactive testing inside VMs