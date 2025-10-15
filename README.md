# Claude Code VM

A NixOS virtual machine configured for running Claude Code and AI development tools.

## Features

- Pre-configured NixOS VM with development tools
- Node.js, Python, Rust, and Go development environments
- SSH access with port forwarding
- Optional desktop environment (XFCE)
- 8GB RAM, 2 CPU cores, 50GB disk space

## Quick Start

1. Build the VM:
   ```bash
   nix build .#vm
   ```

2. Run the VM:
   ```bash
   ./result/bin/run-*-vm
   ```

3. SSH into the VM (from another terminal):
   ```bash
   ssh -p 2222 claude@localhost
   ```
   Password: `claude`

## VM Configuration

- **Hostname**: claude-code-vm
- **User**: claude (password: claude)
- **SSH Port**: 2222 (forwarded from host)
- **Development Ports**: 3000, 8080 (forwarded from host)

## Installing Claude Code

Once in the VM, you can install Claude Code using npm:

```bash
npm install -g @anthropic/claude-code
```

Or follow the official installation instructions from Anthropic.

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