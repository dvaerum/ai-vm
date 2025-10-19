# AI VM

A NixOS virtual machine configured for running Claude Code and AI development tools.

## Features

- Pre-configured headless NixOS VM with development tools
- **Claude Code pre-installed** - Ready to use immediately
- Node.js, Python, Rust, and Go development environments
- Fish shell as default shell with modern CLI experience
- Passwordless SSH access with port forwarding
- Complete VM matrix: 2GB to 32GB RAM, 1 to 8 CPU cores, 20GB to 200GB storage (80 total combinations)

## Quick Start

1. **Interactive VM Manager** (Recommended):
   ```bash
   nix run
   ```
   This opens an interactive fzf menu with VM options including:
   - 🚀 Start VM (quick start)
   - 🔨 Build VM
   - 🏃 Run built VM  
   - 🔌 SSH into VM
   - 🧹 Clean build artifacts
   - ⚙️ Development shell
   - 📋 Show VM status
   - ❓ Help

2. Or run specific VM size directly:
   ```bash
   nix run .#vm                     # Default (8GB-2CPU-50GB)
   nix run .#vm-2gb-1cpu-20gb       # Minimal setup
   nix run .#vm-4gb-2cpu-50gb       # Light development
   nix run .#vm-16gb-4cpu-100gb     # Heavy development
   nix run .#vm-32gb-8cpu-200gb     # Maximum performance
   ```

3. Or build and run manually:
   ```bash
   nix build .#vm-[RAM]-[CPU]-[STORAGE]  # Any combination
   # Examples:
   nix build .#vm-8gb-4cpu-100gb    # 8GB RAM, 4 cores, 100GB
   nix build .#vm-16gb-2cpu-50gb    # 16GB RAM, 2 cores, 50GB
   ./result/bin/run-*-vm
   ```

4. SSH into the VM (from another terminal):
   ```bash
   ssh -p 2222 dennis@localhost
   # OR
   ssh -p 2222 dvv@localhost
   ```
   No password required!

## VM Configurations

### Complete VM Matrix

All combinations of RAM, CPU, and storage are available using the format: `vm-[RAM]-[CPU]-[STORAGE]`

**RAM Options**: 2gb, 4gb, 8gb, 16gb, 32gb  
**CPU Options**: 1cpu, 2cpu, 4cpu, 8cpu  
**Storage Options**: 20gb, 50gb, 100gb, 200gb  

### Popular Configurations

| Configuration | RAM | CPU | Storage | Description |
|---------------|-----|-----|---------|-------------|
| `vm-2gb-1cpu-20gb` | 2GB | 1 | 20GB | Minimal development setup |
| `vm-4gb-2cpu-50gb` | 4GB | 2 | 50GB | Standard light development |
| `vm-8gb-2cpu-50gb` | 8GB | 2 | 50GB | Standard development (default) |
| `vm-8gb-4cpu-100gb` | 8GB | 4 | 100GB | High-performance with large storage |
| `vm-16gb-4cpu-100gb` | 16GB | 4 | 100GB | AI development with large storage |
| `vm-16gb-8cpu-200gb` | 16GB | 8 | 200GB | Professional AI with max storage |
| `vm-32gb-8cpu-200gb` | 32GB | 8 | 200GB | Maximum performance configuration |

### Usage Examples by Use Case

**Minimal Development**: `2gb-1cpu-20gb`, `2gb-2cpu-20gb`  
**Light Development**: `4gb-1cpu-50gb`, `4gb-2cpu-50gb`  
**Standard Development**: `8gb-2cpu-50gb`, `8gb-4cpu-50gb`  
**AI Development**: `16gb-4cpu-100gb`, `16gb-8cpu-100gb`  
**Large-scale AI**: `32gb-4cpu-100gb`, `32gb-8cpu-200gb`  
**Memory-intensive**: `16gb-1cpu-100gb`, `32gb-2cpu-100gb`  
**CPU-intensive**: `8gb-8cpu-100gb`, `16gb-8cpu-100gb`

### Common Settings (All VMs)

- **Hostname**: ai-vm
- **Users**: dennis, dvv (no password required, auto-login enabled for dennis)
- **SSH Port**: 2222 (forwarded from host)
- **Development Ports**: 3001, 9080 (forwarded to guest 3001, 9080)

## Using Claude Code

Claude Code is pre-installed and ready to use! Simply SSH into the VM and run:

```bash
claude-code
```

No additional installation required.

## Development

Enter the development shell:
```bash
nix develop
```

This provides access to VM management tools like `nixos-rebuild` and `qemu`.

## Customization

### Creating Custom VM Sizes

1. Edit `nixos/modules/vm-sizes.nix` to add new configurations:
   ```nix
   "your-custom-size" = {
     memorySize = 12288;  # 12GB RAM
     cores = 6;           # 6 CPU cores  
     diskSize = 76800;    # 75GB storage
     description = "Your custom description";
   };
   ```
2. The VM will automatically be available as `nix run .#vm-your-custom-size`
3. All VMs are generated automatically from the vm-sizes.nix file

### Other Customizations

- Add/remove packages in `nixos/modules/packages.nix`
- Modify port forwarding in `nixos/modules/virtualisation-parameterized.nix`
- Update user configuration in `nixos/modules/users.nix`