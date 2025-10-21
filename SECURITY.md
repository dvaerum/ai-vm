# Security Considerations

## Overview

This document outlines security considerations for the AI VM project. The VMs are configured with **development convenience as the priority**, trading security for ease of use. **This configuration is NOT suitable for production environments or network-exposed systems without hardening.**

## Default Security Posture

### Authentication and Access Control

**Empty Passwords (HIGH RISK)**
- All user accounts (`dennis`, `dvv`) have empty passwords (`hashedPassword = ""`)
- SSH permits empty passwords (`PermitEmptyPasswords = true`)
- Auto-login enabled for `dennis` user on console
- **Risk**: Anyone with network access to the VM can log in without credentials
- **Justification**: Local development VMs accessed only from localhost

**Passwordless Sudo (HIGH RISK)**
- All users in the `wheel` group can use sudo without password (`security.sudo.wheelNeedsPassword = false`)
- Both default users are in the `wheel` group
- **Risk**: Any command can be run with root privileges without verification
- **Justification**: Development convenience for rapid system configuration changes

**SSH Configuration**
- SSH enabled on port 22 (forwarded to host port 2222)
- Password authentication enabled
- Empty passwords permitted
- Root login disabled (`PermitRootLogin = "no"`)
- Challenge-response authentication disabled
- PAM disabled (`UsePAM = false`)
- No SSH key authentication configured by default
- **Risk**: Open SSH access without authentication barriers

### Network Security

**Firewall Enabled (SECURE)**
- Default configuration: `networking.firewall.enable = true`
- Only allowed ports: 22 (SSH), 3001, 9080 (development servers)
- All other ports blocked by default
- **Status**: SECURE - Firewall provides port-level filtering
- **Note**: Users can customize allowed ports in /etc/nixos/configuration.nix

**Port Forwarding**
- Host port 2222 → Guest port 22 (SSH)
- Host port 3001 → Guest port 3001 (development server)
- Host port 9080 → Guest port 9080 (development server)
- **Risk**: Services running on these ports are directly accessible from host

**Network Configuration**
- NetworkManager enabled
- DHCP on eth0
- No network isolation between VMs
- No network traffic filtering

### Shared Folders (MEDIUM RISK)

**Read-Write Shares**
- Host directories can be mounted with full write access
- Uses 9p/virtio filesystem sharing
- No access controls beyond filesystem permissions
- **Risk**: VM can modify host files, malware could spread to host
- **Security Note**: 9p uses host filesystem permissions; VM processes run as users with UIDs that may differ from host

**Read-Only Shares**
- Host directories mounted with `ro` mount option
- Still vulnerable to race conditions if host modifies files while VM reads
- **Risk**: Information disclosure if sensitive data is shared

**Host Nix Store Access**
- Host `/nix/store` mounted at `/nix/.ro-store` in all VMs
- Provides binary cache functionality for nested VMs
- Read-only mount prevents tampering
- **Risk**: Minimal - read-only access to system packages

### System Configuration

**Auto-Login**
- Console auto-login enabled for `dennis` user
- No authentication required for physical/console access
- **Risk**: Anyone with console access has immediate user privileges

**Writable /etc/nixos**
- System configuration directory is writable
- Git repository initialized automatically
- Users can modify system configuration
- **Risk**: Unauthorized system configuration changes (mitigated by sudo requirement for rebuild)

**Package Management**
- Flakes enabled with experimental features
- Users can install packages system-wide (via sudo) or user-specific (nix profile)
- Unfree packages allowed (limited to Claude Code by default)
- **Risk**: Installation of malicious packages

## Threat Model

### Local Development Environment (Default Assumption)

**Assumptions:**
- VMs run on trusted physical hardware
- Host system is secure and trusted
- Network access limited to localhost/NAT
- Single developer or trusted team environment
- No untrusted code execution inside VMs
- Host machine has disk encryption and screen lock

**Threats NOT Addressed:**
- Remote attackers accessing SSH
- Malicious code running inside VM
- Network eavesdropping
- Privilege escalation (already root-equivalent)
- Supply chain attacks via Nix packages
- Side-channel attacks
- VM escape vulnerabilities

**Acceptable Risks:**
- No authentication barriers
- No audit logging
- No intrusion detection
- No resource limits
- No mandatory access controls

### Network-Exposed VMs (Requires Hardening)

**Scenario:** VM SSH port exposed to LAN or internet

**Additional Threats:**
- Brute force attacks (prevented by no password requirement - any attempt succeeds)
- Unauthorized access from network
- Lateral movement in network
- Data exfiltration
- Cryptocurrency mining / resource abuse
- Bot/malware hosting

**Hardening Required:** See "Hardening Guide" section below

### Production Use (NOT RECOMMENDED)

**This VM configuration is NOT designed for production use.** For production environments:
- Use a dedicated NixOS configuration from scratch
- Follow NixOS security best practices
- Implement proper authentication (SSH keys, MFA)
- Enable and configure firewall
- Set up audit logging and monitoring
- Apply principle of least privilege
- Regular security updates and patches
- Security scanning and compliance checks

## Hardening Guide

If you need to expose VMs to a network or use in a less-trusted environment, follow these steps:

### 1. Enable SSH Key Authentication

**On Host Machine:**
```bash
# Generate SSH key if you don't have one
ssh-keygen -t ed25519 -C "your_email@example.com"

# Copy public key
cat ~/.ssh/id_ed25519.pub
```

**Edit VM Configuration** (`/etc/nixos/configuration.nix` or `nixos/modules/users.nix`):
```nix
users.users.dennis = {
  isNormalUser = true;
  extraGroups = [ "wheel" "networkmanager" ];
  hashedPassword = "!";  # Disable password login
  shell = pkgs.fish;
  openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... your-key-here"
  ];
};

users.users.dvv = {
  isNormalUser = true;
  extraGroups = [ "wheel" "networkmanager" ];
  hashedPassword = "!";  # Disable password login
  shell = pkgs.fish;
  openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... your-key-here"
  ];
};
```

### 2. Secure SSH Configuration

**Edit `/etc/nixos/configuration.nix`:**
```nix
services.openssh = {
  enable = true;
  settings = {
    PasswordAuthentication = false;  # Disable password auth
    PermitEmptyPasswords = false;    # No empty passwords
    PermitRootLogin = "no";          # No root login
    ChallengeResponseAuthentication = false;
    KbdInteractiveAuthentication = false;
  };
  # Optional: Restrict to specific users
  allowUsers = [ "dennis" "dvv" ];
};
```

### 3. Require Password for Sudo

**Edit `/etc/nixos/configuration.nix`:**
```nix
# Remove or change this line:
# security.sudo.wheelNeedsPassword = false;
security.sudo.wheelNeedsPassword = true;

# Set user passwords
users.users.dennis.hashedPassword = "$6$rounds=4096$...";  # Use mkpasswd
users.users.dvv.hashedPassword = "$6$rounds=4096$...";
```

**Generate password hash:**
```bash
# On a system with mkpasswd
mkpasswd -m sha-512

# Or inside the VM
nix-shell -p mkpasswd --run 'mkpasswd -m sha-512'
```

### 4. Enable and Configure Firewall

**Edit `/etc/nixos/configuration.nix`:**
```nix
networking.firewall = {
  enable = true;
  allowedTCPPorts = [ 22 ];  # Only SSH
  # Add development ports only if needed and from trusted sources
  # allowedTCPPorts = [ 22 3001 9080 ];

  # Optional: Restrict SSH to specific IPs
  extraCommands = ''
    iptables -A INPUT -p tcp --dport 22 -s 192.168.1.0/24 -j ACCEPT
    iptables -A INPUT -p tcp --dport 22 -j DROP
  '';
};
```

### 5. Disable Auto-Login

**Edit `/etc/nixos/configuration.nix`:**
```nix
# Remove or comment out:
# services.getty.autologinUser = "dennis";
```

### 6. Secure Shared Folders

**Minimize Shared Folders:**
- Only share directories that are absolutely necessary
- Use read-only shares (`--share-ro`) whenever possible
- Never share sensitive directories (home directories, credentials, private keys)

**Review Shared Folder Permissions:**
```bash
# Inside VM, check what's mounted
mount | grep 9p

# On host, review permissions
ls -la /path/to/shared/folder
```

**Remove Shares from Running VM:**
```bash
# Unmount if not needed
sudo umount /mnt/host-rw/dirname
sudo umount /mnt/host-ro/dirname
```

### 7. Enable Audit Logging

**Edit `/etc/nixos/configuration.nix`:**
```nix
# Enable audit framework
security.audit.enable = true;
security.auditd.enable = true;

# Optional: Log all sudo commands
security.sudo.extraConfig = ''
  Defaults logfile=/var/log/sudo.log
  Defaults log_input, log_output
'';
```

### 8. Restrict Nix Package Installation

**Edit `/etc/nixos/configuration.nix`:**
```nix
# Prevent users from installing packages without sudo
nix.settings.allowed-users = [ "root" "@wheel" ];

# Disable nix-daemon for user installs
nix.settings.trusted-users = [ "root" ];

# Require signatures for binary cache
nix.settings.require-sigs = true;
```

### 9. Apply Resource Limits

**Edit `/etc/nixos/configuration.nix`:**
```nix
# Limit user processes and memory
security.pam.loginLimits = [
  { domain = "*"; type = "hard"; item = "nproc"; value = "1000"; }
  { domain = "*"; type = "hard"; item = "nofile"; value = "4096"; }
];

# Optional: Enable systemd resource control
systemd.services.user-runtime-dir.serviceConfig = {
  CPUQuota = "50%";
  MemoryMax = "2G";
};
```

### 10. Network Exposure Checklist

Before exposing VM to network:

- [ ] SSH key authentication configured and tested
- [ ] Password authentication disabled
- [ ] Empty passwords disabled
- [ ] Sudo requires password
- [ ] Auto-login disabled
- [ ] Firewall enabled with minimal ports
- [ ] Shared folders reviewed and minimized
- [ ] Audit logging enabled
- [ ] User accounts reviewed (remove unnecessary accounts)
- [ ] System updated (`nix flake update /etc/nixos && rebuild`)
- [ ] Intrusion detection considered (fail2ban, etc.)
- [ ] Monitoring configured (if long-running)

### 11. Rebuild and Test

```bash
# Inside VM, rebuild with new security settings
sudo nixos-rebuild switch

# Test SSH access with keys
# (From another terminal on host)
ssh -p 2222 -i ~/.ssh/id_ed25519 dennis@localhost

# Verify password auth disabled
ssh -p 2222 -o PreferredAuthentications=password dennis@localhost
# Should fail: "Permission denied (publickey)"

# Verify sudo requires password
sudo echo "test"
# Should prompt for password

# Check firewall status
sudo iptables -L -n
```

## Best Practices

### Development Environment

1. **Network Isolation**
   - Keep VMs on host-only or NAT networks
   - Don't bridge VMs to external networks without hardening
   - Use SSH port forwarding (2222→22) not direct exposure

2. **Regular Updates**
   ```bash
   # Inside VM
   nix flake update /etc/nixos
   rebuild
   ```

3. **Minimal Shared Folders**
   - Only share project directories needed for work
   - Use read-only shares for reference data
   - Never share `.ssh`, `.gnupg`, credentials

4. **Separate VMs for Different Trust Levels**
   - Untrusted code → isolated VM with no shared folders
   - Trusted development → VM with shared folders
   - Testing → disposable VM with `--overlay` flag

5. **Use Overlay for Untrusted Workloads**
   ```bash
   # Create VM with clean state on each boot
   nix run .#default -- --ram 8 --cpu 4 --storage 50 --overlay
   ```

### SSH Key Management

1. **Use Ed25519 Keys**
   - More secure and faster than RSA
   ```bash
   ssh-keygen -t ed25519 -C "vm-access-key"
   ```

2. **Separate Keys per Purpose**
   - Don't reuse your GitHub/work SSH key for VM access
   - Create dedicated keys for VM access

3. **Passphrase Protection**
   - Always use passphrase for SSH private keys
   - Use ssh-agent to avoid repeated entry

### Shared Folder Security

1. **File Permissions Matter**
   - VM can only access files that host user can access
   - Set restrictive permissions on host before sharing
   ```bash
   chmod 700 ~/project  # Only owner can access
   ```

2. **UID/GID Considerations**
   - VM users may have different UIDs than host
   - Check effective permissions inside VM
   ```bash
   # Inside VM
   ls -ln /mnt/host-rw/shared  # Shows numeric UIDs
   ```

3. **Sensitive Data**
   - Never share directories containing:
     - SSH private keys
     - GPG keys
     - API tokens/credentials
     - Password databases
     - Browser profiles

### Monitoring and Maintenance

1. **Check for Unusual Activity**
   ```bash
   # Inside VM
   last          # Login history
   w             # Currently logged in users
   ps aux        # Running processes
   netstat -tlnp # Listening services
   ```

2. **Review User Accounts**
   ```bash
   # List all users
   cat /etc/passwd

   # Remove unnecessary users from /etc/nixos/configuration.nix
   ```

3. **Audit Installed Packages**
   ```bash
   # List installed packages
   nix-env -q

   # System packages
   nix-store --query --requisites /run/current-system | cut -d- -f2- | sort -u
   ```

## Security Features

### Currently Implemented

- **Root Login Disabled**: SSH root login is disabled (`PermitRootLogin = "no"`)
- **No Root Password**: Root account has no password set
- **Unprivileged VMs**: QEMU runs as user process (not root)
- **Read-Only Nix Store**: Host Nix store shared read-only (prevents tampering)
- **Isolated Filesystem**: VM disk image isolated from host filesystem (except shared folders)
- **QEMU Isolation**: Standard QEMU virtualization provides process isolation
- **Firewall Enabled**: Default firewall with port allowlist (22, 3001, 9080)

### NOT Implemented (Require Hardening)

- No authentication required for SSH
- No password required for sudo
- No audit logging
- No intrusion detection
- No rate limiting
- No SELinux/AppArmor
- No automatic security updates
- No resource quotas
- No file integrity monitoring
- No security scanning

## Known Security Limitations

### 1. Development vs Production Trade-off

This project prioritizes **developer experience over security**. The configuration is designed for:
- Local development on trusted hardware
- Rapid iteration and experimentation
- Easy access without authentication friction
- Maximum compatibility and minimal restrictions

### 2. VM Escape Vulnerabilities

- VMs rely on QEMU/KVM for isolation
- QEMU vulnerabilities could allow VM escape
- Keep host system updated for QEMU security patches
- VMs should not run untrusted code without additional sandboxing

### 3. Shared Folder Risks

- 9p filesystem sharing has had security vulnerabilities
- Shared folders bypass normal VM isolation
- Malicious code in VM can access shared host directories
- No additional sandboxing beyond filesystem permissions

### 4. No Secrets Management

- No built-in secrets management (vault, encrypted storage)
- Credentials must be managed manually
- Configuration files stored in plaintext
- Git history may contain sensitive data

### 5. Network Security

- VMs trust the host network completely
- No network segmentation between VMs
- DNS and routing controlled by host
- No network-based intrusion detection

## Incident Response

If you suspect a VM has been compromised:

1. **Isolate the VM**
   ```bash
   # Shut down the VM immediately
   # From VM console or SSH:
   sudo poweroff

   # Or kill the QEMU process from host:
   pkill -f "qemu.*ai-vm"
   ```

2. **Assess the Damage**
   - Check shared folders for modifications
   - Review host system for unusual activity
   - Check network connections from host
   ```bash
   # On host
   netstat -tlnp | grep 2222
   ```

3. **Clean Up**
   ```bash
   # Remove VM disk image
   rm -f ai-vm.qcow2

   # Remove generated files
   rm -f start-*.sh

   # Optional: Clean Nix store
   nix-collect-garbage -d
   ```

4. **Rebuild from Scratch**
   ```bash
   # Create new VM with hardened config
   nix run .#default -- --ram 8 --cpu 4 --storage 50

   # Apply hardening steps from this guide
   ```

5. **Prevent Recurrence**
   - Review what code was run in the VM
   - Apply hardening steps before running untrusted code
   - Consider using disposable VMs with `--overlay` flag

## Additional Resources

- [NixOS Security Guide](https://nixos.wiki/wiki/Security)
- [NixOS Manual - Security](https://nixos.org/manual/nixos/stable/index.html#ch-security)
- [OpenSSH Hardening Guide](https://www.sshaudit.com/hardening_guides.html)
- [CIS Benchmark for Linux](https://www.cisecurity.org/benchmark/linux)
- [QEMU Security](https://www.qemu.org/docs/master/system/security.html)

## Reporting Security Issues

If you discover a security vulnerability in this project:

1. **Do NOT** open a public GitHub issue
2. Email the maintainer privately (see repository README)
3. Include detailed description and reproduction steps
4. Allow reasonable time for fix before public disclosure

## Security Update Policy

This is a development tool project, not a security-focused distribution:
- Security updates are NOT guaranteed
- No SLA for security patch response time
- Users are responsible for their own security hardening
- Check for updates regularly: `nix flake update`

**For security-critical deployments, use official NixOS releases and security channels, not this development VM builder.**

## Summary

### Default Security Posture (Development-Optimized)

| Security Control | Status | Risk Level |
|-----------------|--------|------------|
| Authentication | None (empty passwords) | HIGH |
| Sudo Password | Not required | HIGH |
| SSH Security | Accepts empty passwords | HIGH |
| Firewall | **Enabled (ports 22, 3001, 9080)** | **LOW** |
| Audit Logging | Disabled | MEDIUM |
| Auto-login | Enabled | MEDIUM |
| Shared Folders | Unrestricted | MEDIUM |
| Root Access | SSH disabled, sudo enabled | LOW |
| Network Isolation | NAT only | LOW |

### After Hardening (Secure)

| Security Control | Status | Risk Level |
|-----------------|--------|------------|
| Authentication | SSH keys only | LOW |
| Sudo Password | Required | LOW |
| SSH Security | Public key auth only | LOW |
| Firewall | Enabled, minimal ports | LOW |
| Audit Logging | Enabled | LOW |
| Auto-login | Disabled | LOW |
| Shared Folders | Minimized, reviewed | LOW |
| Root Access | SSH disabled, sudo with password | LOW |
| Network Isolation | Firewall + port restrictions | LOW |

**Remember: These VMs are development tools. Never use default configuration in production or on untrusted networks.**
