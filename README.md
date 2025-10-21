# AI VM

A NixOS virtual machine configured for running Claude Code and AI development tools.

---

**SECURITY WARNING:** This VM is configured for **local development with convenience over security**. Default configuration uses empty passwords, passwordless sudo, and minimal authentication. **NOT suitable for production or network-exposed environments** without hardening. See [SECURITY.md](SECURITY.md) for comprehensive security documentation and hardening guide.

**Quick Security Status:**
- Authentication: None (empty passwords) - HIGH RISK
- Firewall: Enabled (ports 22, 3001, 9080 allowed) - SECURE
- Network: Localhost only via port forwarding - MITIGATED
- Use Case: Local development VMs only

---

## Features

- Pre-configured headless NixOS VM with development tools
- **Claude Code pre-installed** - Ready to use immediately
- Node.js, Python, Rust, and Go development environments
- Fish shell as default shell with modern CLI experience
- Passwordless SSH access with port forwarding
- Complete VM matrix: 2GB to 32GB RAM, 1 to 8 CPU cores, 20GB to 200GB storage (80 total combinations)

## Quick Start

1. **Interactive VM Selector** (Recommended):
   ```bash
   nix run
   ```
   This opens interactive fzf menus to select:
   - 💾 RAM size (2GB to 32GB)
   - ⚡ CPU cores (1 to 8 cores)
   - 💿 Storage size (20GB to 200GB)
   - 🔄 Overlay filesystem option

2. **Command Line Interface**:
   ```bash
   nix run .#default -- --help                          # Show help
   nix run .#default -- --ram 8 --cpu 4 --storage 100  # Direct launch (8GB RAM, 4 cores, 100GB)
   nix run .#default -- -r 16 -c 8 -s 200 --overlay     # With overlay (16GB RAM, 8 cores, 200GB)
   ```

3. Or run specific VM size directly:
   ```bash
   nix run .#vm                     # Default (8GB-2CPU-50GB)
   nix run .#vm-2gb-1cpu-20gb       # Minimal setup
   nix run .#vm-4gb-2cpu-50gb       # Light development
   nix run .#vm-16gb-4cpu-100gb     # Heavy development
   nix run .#vm-32gb-8cpu-200gb     # Maximum performance
   ```

4. Or build and run manually:
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

## Security

This project prioritizes development convenience over security. Review security considerations before use.

### Default Security Posture

**For Local Development (Default):**
- Empty passwords for quick access
- Passwordless sudo for rapid system changes
- Firewall enabled with essential ports (22, 3001, 9080)
- Accessible only via localhost port forwarding
- **Use Case:** Trusted local development environment

### Security Checklist

**Before Network Exposure or Shared Use:**
- [ ] Read [SECURITY.md](SECURITY.md) for comprehensive security guide
- [ ] Set strong user passwords: `mkpasswd -m sha-512`
- [ ] Add SSH public keys to user configurations
- [ ] Disable password authentication in SSH
- [ ] Enable sudo password requirement
- [ ] Review and minimize firewall allowed ports
- [ ] Remove or minimize shared folders
- [ ] Disable auto-login for console
- [ ] Enable audit logging

**For Production:** Do not use this VM configuration. Build a dedicated secure NixOS system from scratch.

### Quick Hardening

Inside VM (`ssh -p 2222 dennis@localhost`), edit `/etc/nixos/configuration.nix`:

```nix
# Set strong passwords (generate with: mkpasswd -m sha-512)
users.users.dennis.hashedPassword = "$6$rounds=4096$...";

# Add SSH keys
users.users.dennis.openssh.authorizedKeys.keys = [
  "ssh-ed25519 AAAAC3... your-key-here"
];

# Disable password auth
services.openssh.settings.PasswordAuthentication = false;
services.openssh.settings.PermitEmptyPasswords = false;

# Require sudo password
security.sudo.wheelNeedsPassword = true;

# Firewall already enabled - review allowed ports
networking.firewall.allowedTCPPorts = [ 22 ];  # SSH only
```

Then rebuild: `sudo nixos-rebuild switch`

See [SECURITY.md](SECURITY.md) for detailed hardening steps, threat model, and best practices.

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