# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Workflow

**Use Multiple Agents When Possible**: When working on tasks that can be parallelized or benefit from concurrent investigation, use multiple agents to improve efficiency and reduce overall task completion time.

## Project Overview

This is a NixOS-based VM builder for running Claude Code and AI development environments. It uses Nix flakes to create customizable headless VMs with various hardware configurations (RAM, CPU, storage) and features (audio passthrough, shared folders, overlay filesystem).

## Architecture

### Core Components

1. **flake.nix** (lines 1-174): Main flake defining VM generation logic
   - `makeVM` function (lines 42-108): Creates VMs with parameterized hardware specs
   - `parseSize` function (lines 21-39): Converts size strings ("8gb", "2cpu") to actual values
   - Library function `makeCustomVM` (lines 119-122): Public API for creating custom VMs

2. **vm-selector.sh**: Interactive VM launcher with fzf menus or CLI arguments
   - Detects execution context (Nix store vs direct) to determine flake reference (lines 6-81)
   - Supports custom RAM/CPU/storage values beyond defaults
   - Generates reusable startup scripts (start-{VM_NAME}.sh) with embedded configuration (lines 492-560)
   - VM storage location:
     - Remote flakes (github:*): `~/.local/share/ai-vms/`
     - Local flakes: project directory

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

**Shared Folders**: Uses 9p/virtio filesystem sharing between host and guest:
- Mount tag generation (max 31 chars): combines prefix + path hash (8 chars) + basename (max 19 chars)
- Read-write shares: mounted at `/mnt/host-rw/{basename}`
- Read-only shares: mounted at `/mnt/host-ro/{basename}` with `ro` mount option
- Configured via `--share-rw` and `--share-ro` flags in vm-selector.sh

**Audio Passthrough**: PulseAudio passthrough when enabled via `--audio` flag, using QEMU's `-audiodev pa` with intel-hda emulation.

**Claude Code Authentication**: The `start-claude` command provides a wrapper to automatically handle authentication from shared folders:
- When `--share-claude-auth` flag is used, `start-claude` copies `~/.claude/.credentials.json` from `/mnt/host-ro/.claude/` to `~/.claude/` in the VM
- Automatically runs with `--dangerously-skip-permissions --permission-mode bypassPermissions` flags to bypass all permissions in VM environment
- Preserves command history and project settings by syncing the entire `.claude` directory
- Implementation in `nixos/modules/packages.nix` as `start-claude`
- Use `start-claude` for convenience with shared auth, or `claude` for normal Claude Code behavior

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
nix run .#default -- --share-claude-auth --ram 8 --cpu 4 --storage 50  # Share Claude auth from host

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

# Manual testing inside a running VM
ssh -p 2222 dennis@localhost
./tests/manual-nixos-rebuild-test.sh  # Copy to VM first, or access via shared folder
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

### Dynamic VM Building
VMs are built on-demand using `nix build --impure --expr` (vm-selector.sh:484-490):
- Fetches flake using `builtins.getFlake` with detected flake reference
- Calls `flake.lib.makeCustomVM` with user-specified parameters
- Creates VM in `result/` symlink with binary at `result/bin/run-{VM_NAME}-vm`
- qcow2 disk image created at `{VM_NAME}.qcow2` on first VM start

### NixOS Rebuild Inside VMs
- VMs include a `nixos-rebuild` wrapper that automatically uses flakes (virtualisation-parameterized.nix:122-134)
- `/etc/nixos` is a writable directory (not symlinks) initialized by activation script (lines 411-442)
- Configuration files stored in `/etc/nixos-template` and copied to `/etc/nixos` on first boot
- Git repo automatically initialized in `/etc/nixos` (required for flakes) with initial commit
- Users can run `sudo nixos-rebuild switch` without the `--flake` flag
- The wrapper detects `/etc/nixos/flake.nix` and automatically adds `--flake /etc/nixos#vmname`
- `rebuild` command is a convenience wrapper (lines 350-408) that handles git commits and rebuilds

### Port Forwarding
- **SSH**: Host 2222 → Guest 22
- **Development**: Host 3001 → Guest 3001, Host 9080 → Guest 9080
- Configured in virtualisation-parameterized.nix:23-27

### VM Identity and Naming
- VMs use custom names via `--name` flag (default: "ai-vm")
- Affects hostname, qcow2 filename, and startup script names
- Name must be alphanumeric with hyphens/underscores only

### Flake Reference Detection
vm-selector.sh detects flake location through multiple methods (lines 6-81):
1. Path prefix in parent process arguments (e.g., `nix run path:...`)
2. NIX_ATTRS_JSON_FILE environment variable (from Nix)
3. Current directory flake.nix
4. Smart detection for common project paths (Projects/nixos-configs/ai-vm)
5. Fallback to github:dvaerum/ai-vm

Detection determines where VM files are created and which flake reference to use for rebuilds.

### Overlay Filesystem and Nested Virtualization
All VMs now have a writable Nix store using overlay filesystem, enabling nested VM creation (building VMs inside VMs) without additional flags.

**Implementation** (virtualisation-parameterized.nix:31-38, 61-108):
- `virtualisation.writableStore = true`: Always enabled for all VMs
- `virtualisation.writableStoreUseTmpfs = useOverlay`: Controls persistence behavior
- Host Nix store mounted at `/nix/.ro-store` via 9p (lines 63-69, 92-98)
- Writable overlay created on top of read-only host store

**Host Store Mounting** (virtualisation-parameterized.nix:63-98):
- Host's `/nix/store` shared via 9p virtio filesystem as `nix-store` tag
- Mounted at `/nix/.ro-store` with options: `trans=virtio`, `version=9p2000.L`, `msize=104857600`, `cache=loose`, `ro`
- Provides binary cache functionality - packages from host are accessible without rebuilding
- Critical for nested VM performance - avoids duplicating the entire Nix store

**Behavior**:
- **Without `--overlay` flag** (default): Disk-based overlay that persists across reboots
  - Nix store changes are saved to qcow2 disk
  - Supports building nested VMs efficiently (uses host store as binary cache)
  - Changes persist after reboot
  - Slightly slower first boot due to overlay setup
  - Host store packages available instantly via `/nix/.ro-store`

- **With `--overlay` flag**: Tmpfs-based overlay (in-memory)
  - Nix store changes stored in RAM
  - Clean state on each boot (changes lost on reboot)
  - Faster operation but uses more RAM
  - Still supports nested VMs during the session
  - Host store still mounted for binary cache access

**Nested VM Support**: All VMs can now create nested VMs (VMs inside VMs) because:
1. The Nix store is writable (via overlay filesystem)
2. The host's Nix store is mounted and accessible (binary cache)
3. Packages from the host don't need to be rebuilt - they're directly accessible

Previously this was a known issue (documented at lines 152-158 in older versions). The solution mounts the host's Nix store as a read-only binary cache, NOT by adding overlay as the fix. This approach provides efficient nested virtualization without performance penalties.

### Audio Implementation
Uses PulseAudio passthrough (not PipeWire). Creates audio group and adds users when `enableAudio = true`. VM name used for PulseAudio device naming.

### Startup Script Generation
When VMs are created via vm-selector.sh, a reusable `start-{VM_NAME}.sh` script is generated:
- Contains embedded VM configuration (RAM, CPU, storage, features)
- Documents all shared folders with mount point mappings
- Includes SSH connection instructions
- Can be run directly to restart the VM without rebuilding
- Location depends on flake type (see VM storage location above)

## Modifying VMs

### Adding New Packages
Edit `nixos/modules/packages.nix` or modify `/etc/nixos/configuration.nix` inside running VM, then run `rebuild`.

### Changing Port Forwarding
Modify `virtualisation.forwardPorts` in `nixos/modules/virtualisation-parameterized.nix:23-27`.

### Adjusting Hardware Limits
Validation limits in vm-selector.sh (lines 223-256):
- RAM: max 1024GB (validated in `validate_numeric` function)
- CPU: max 128 cores
- Storage: max 10TB (10000GB)

Values can be any positive integer within these limits, not just the preset options shown in fzf menus.

## Security Considerations

**IMPORTANT: This VM configuration prioritizes development convenience over security.**

The default configuration is **NOT suitable for production environments or network-exposed systems** without hardening. See `SECURITY.md` for comprehensive security documentation.

### Default Security Posture (Development-Focused)

**Authentication & Access:**
- Empty passwords for all users (`hashedPassword = ""`)
- Passwordless sudo for wheel group (`wheelNeedsPassword = false`)
- SSH permits empty passwords (`PermitEmptyPasswords = true`)
- Auto-login enabled for console access
- **Risk Level: HIGH** - Anyone with network access can gain root privileges

**Network Security:**
- Firewall enabled with minimal necessary ports (22, 3001, 9080)
- Port forwarding: host:2222 → guest:22 (SSH)
- **Mitigation: VMs accessible only via localhost port forwarding**

**Shared Folders:**
- 9p/virtio filesystem sharing between host and guest
- Read-write shares can modify host files
- Read-only shares use `ro` mount option
- **Risk Level: MEDIUM** - Malicious code in VM can access shared host directories

### Security Trade-offs for Development

These security relaxations are intentional for development convenience:

1. **No Authentication Barriers**: Rapid VM access without password prompts
2. **Passwordless Sudo**: Seamless system configuration changes
3. **Firewall with Essential Ports**: Allow development servers while maintaining basic protection
4. **Writable /etc/nixos**: Easy configuration management and rebuilds
5. **Auto-login**: Immediate console access (only from host QEMU)

### When to Harden

Apply security hardening (see `SECURITY.md`) when:
- Exposing SSH to LAN or internet
- Running untrusted code inside VMs
- Sharing VMs with other users
- Using VMs in less-trusted networks
- Long-running production-like workloads

### Quick Hardening Checklist

For network-exposed or production use:
- [ ] Generate and set strong user passwords (`mkpasswd -m sha-512`)
- [ ] Add SSH public keys to `openssh.authorizedKeys.keys`
- [ ] Disable password authentication (`PasswordAuthentication = false`)
- [ ] Enable sudo password requirement (`wheelNeedsPassword = true`)
- [ ] Review firewall rules (already enabled - verify allowed ports)
- [ ] Disable auto-login (`services.getty.autologinUser = null`)
- [ ] Minimize or remove shared folders
- [ ] Enable audit logging
- [ ] Review and remove unnecessary user accounts

**Full hardening guide:** See `/home/dennis/ai-vm/SECURITY.md`

### Security Documentation Files

- **SECURITY.md**: Comprehensive security documentation with threat model, hardening guide, and best practices
- **Generated VM Configuration**: Security comments in `/etc/nixos/configuration.nix` inside VMs
- **Module Comments**: Security considerations documented in `nixos/modules/users.nix` and `networking.nix`

## Testing Strategy

### Automated Tests
Integration tests (tests/integration/):
- `comprehensive-vm-selector-test.py`: Python-based pytest suite for VM selector
- `nixos-rebuild-test.nix`: Validates nixos-rebuild functionality inside VMs
- `vm-nixos-config-test.py`: Tests NixOS configuration generation

Unit tests (tests/unit.nix):
- Nix expression validation
- Module structure testing

### Manual Testing
- `tests/manual-nixos-rebuild-test.sh`: Interactive test script for verifying:
  - /etc/nixos directory setup and permissions
  - Configuration file presence and writability
  - Git repository initialization
  - nixos-rebuild wrapper functionality
  - Configuration modification and rebuild workflow

Run inside a VM via: `ssh -p 2222 dennis@localhost`, then copy or mount the test script.
