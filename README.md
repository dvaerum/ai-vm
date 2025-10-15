# AI VM

A NixOS virtual machine configured for running Claude Code and AI development tools.

## Features

- Pre-configured headless NixOS VM with development tools
- **Claude Code pre-installed** - Ready to use immediately
- Node.js, Python, Rust, and Go development environments
- Fish shell as default shell with modern CLI experience
- Passwordless SSH access with port forwarding
- 8GB RAM, 2 CPU cores, 50GB disk space

## Quick Start

1. Run the VM directly:
   ```bash
   nix run
   ```

2. Or build and run manually:
   ```bash
   nix build .#vm
   ./result/bin/run-*-vm
   ```

3. SSH into the VM (from another terminal):
   ```bash
   ssh -p 2222 dennis@localhost
   # OR
   ssh -p 2222 dvv@localhost
   ```
   No password required!

## VM Configuration

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

Edit `flake.nix` to customize the VM configuration:
- Change memory/CPU allocation in `virtualisation.vmVariant`
- Add/remove packages in `environment.systemPackages`
- Modify port forwarding in `virtualisation.forwardPorts`