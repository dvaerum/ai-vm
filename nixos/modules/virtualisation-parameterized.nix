{ config, pkgs, memorySize ? 8192, cores ? 2, diskSize ? 51200, useOverlay ? false, sharedFoldersRW ? [], sharedFoldersRO ? [], vmName ? "ai-vm", enableAudio ? false, ... }:

let
  # Generate short mount tag from path (max 31 chars for QEMU)
  # Shared function used by both sharedDirectories and fileSystems
  mkMountTag = prefix: path:
    let
      # Get basename and hash for uniqueness
      basename = builtins.baseNameOf path;
      pathHash = builtins.substring 0 8 (builtins.hashString "sha256" path);
      # Limit total length: prefix(3) + hash(8) + dash(1) + basename(max 19) = 31
      maxBasename = 19;
      shortBasename = if builtins.stringLength basename > maxBasename
                     then builtins.substring 0 maxBasename basename
                     else basename;
    in "${prefix}${pathHash}-${shortBasename}";
in
{
  # Set system hostname to VM name
  networking.hostName = pkgs.lib.mkForce vmName;

  # Firewall configuration
  # SECURITY: Firewall is enabled by default with only necessary ports allowed
  # The VM is accessible via port forwarding from the host:
  #   - Host:2222 -> Guest:22 (SSH)
  #   - Host:3001 -> Guest:3001 (Development server)
  #   - Host:9080 -> Guest:9080 (Development server)
  #
  # Allowed ports within the VM network:
  #   - 22: SSH (required for remote access)
  #   - 3001, 9080: Development servers (common for web development)
  #
  # To open additional ports, edit /etc/nixos/configuration.nix and add:
  #   networking.firewall.allowedTCPPorts = [ 22 3001 9080 YOUR_PORT ];
  #
  # To disable firewall (NOT recommended for production):
  #   networking.firewall.enable = false;
  #
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22 3001 9080 ];
    # Uncomment to allow specific UDP ports:
    # allowedUDPPorts = [ ];
  };

  # VM-specific settings with parameterized size
  virtualisation.vmVariant = {
    virtualisation.memorySize = memorySize;
    virtualisation.cores = cores;
    virtualisation.diskSize = diskSize;

    # Disable graphics for headless operation
    virtualisation.graphics = false;

    # Configure writable store
    # Always enable writable store to support nested VM creation
    # The difference is in whether overlay changes persist to disk or tmpfs
    virtualisation.writableStore = true;

    # When overlay flag is NOT set, persist overlay to disk for nested VM support
    # When overlay flag IS set, use tmpfs for clean state on each boot (original behavior)
    virtualisation.writableStoreUseTmpfs = useOverlay;

    # Use custom VM name for qcow2 file
    virtualisation.diskImage = "./${vmName}.qcow2";

    # Port forwarding for SSH and development servers
    virtualisation.forwardPorts = [
      { from = "host"; host.port = 2222; guest.port = 22; }
      { from = "host"; host.port = 3001; guest.port = 3001; }
      { from = "host"; host.port = 9080; guest.port = 9080; }
    ];

    # Audio configuration
    virtualisation.qemu.options = if enableAudio then [
      # PulseAudio passthrough with both input and output
      "-audiodev"
      "pa,id=pa1,in.name=${vmName}-input,out.name=${vmName}-output"
      "-device"
      "intel-hda"
      "-device"
      "hda-duplex,audiodev=pa1"
    ] else [];

    # Shared folders configuration
    virtualisation.sharedDirectories =
      # Host Nix store (mounted as read-only to serve as binary cache)
      # This allows nested VMs to access packages from the host without rebuilding
      {
        "nix-store" = {
          source = "/nix/store";
          target = "/nix/.ro-store";
        };
      } //
      # Read-write shared folders
      (builtins.listToAttrs (builtins.map (path: {
        name = mkMountTag "rw" path;
        value = {
          source = path;
          target = "/mnt/host-rw/${builtins.baseNameOf path}";
        };
      }) sharedFoldersRW)) //
      # Read-only shared folders (note: readonly is enforced via mount options, not via QEMU)
      (builtins.listToAttrs (builtins.map (path: {
        name = mkMountTag "ro" path;
        value = {
          source = path;
          target = "/mnt/host-ro/${builtins.baseNameOf path}";
        };
      }) sharedFoldersRO));

    # Mount shared folders as read-only where needed
    fileSystems =
      # Mount host Nix store with optimized cache settings for binary cache usage
      # This is the key to nested VM support - VMs can access host packages directly
      {
        "/nix/.ro-store" = {
          device = "nix-store";
          fsType = "9p";
          options = ["trans=virtio" "version=9p2000.L" "msize=104857600" "cache=loose" "ro"];
          neededForBoot = true;
        };
      } //
      # User-specified read-only shared folders
      (builtins.listToAttrs (builtins.map (path: {
        name = "/mnt/host-ro/${builtins.baseNameOf path}";
        value = {
          device = mkMountTag "ro" path;
          fsType = "9p";
          options = ["trans=virtio" "version=9p2000.L" "ro"];
        };
      }) sharedFoldersRO));
  };

  # Audio system configuration (enabled when audio passthrough is requested)
  # Uses PulseAudio for compatibility with QEMU's -audiodev pa option
  services.pulseaudio = {
    enable = enableAudio;
    systemWide = false;
    support32Bit = true;
  };

  # Add audio group for users when audio is enabled
  users.groups = pkgs.lib.mkIf enableAudio {
    audio = {};
  };

  # Add users to audio group when audio is enabled
  users.users.dennis.extraGroups = pkgs.lib.mkIf enableAudio [ "wheel" "networkmanager" "audio" ];
  users.users.dvv.extraGroups = pkgs.lib.mkIf enableAudio [ "wheel" "networkmanager" "audio" ];

  # Create a nixos-rebuild wrapper that uses flakes by default
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "nixos-rebuild" ''
      # Wrapper for nixos-rebuild that automatically uses flakes
      if [ -f /etc/nixos/flake.nix ]; then
        # If no --flake argument provided, add it automatically
        if ! echo "$@" | grep -q -- "--flake"; then
          exec ${pkgs.nixos-rebuild}/bin/nixos-rebuild "$@" --flake /etc/nixos#${vmName}
        fi
      fi
      # Fall through to normal nixos-rebuild
      exec ${pkgs.nixos-rebuild}/bin/nixos-rebuild "$@"
    '')
  ];

  # Install VM configuration flake templates at /etc/nixos-template
  # These will be copied to /etc/nixos by the activation script
  environment.etc."nixos-template/flake.nix".text = ''
    {
      description = "AI VM NixOS Configuration - ${vmName}";

      inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
      };

      outputs = { self, nixpkgs }:
      let
        system = "x86_64-linux";
        pkgs = nixpkgs.legacyPackages.''${system};
      in
      {
        nixosConfigurations.${vmName} = nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            ./hardware-configuration.nix
            ./configuration.nix
          ];
        };
      };
    }
  '';

  # Create a flake.lock file to avoid lock file creation issues
  environment.etc."nixos-template/flake.lock".text = builtins.toJSON {
    nodes = {
      nixpkgs = {
        locked = {
          lastModified = 1729534635;
          narHash = "sha256-xuVPp0iNKlAaHUbhHTZ/XnRLaHX1lY3A4IW6YSX8eOw=";
          owner = "NixOS";
          repo = "nixpkgs";
          rev = "5e04827322c3a2b315c4a7dd3ba0df6e0fb33f5c";
          type = "github";
        };
        original = {
          owner = "NixOS";
          ref = "nixos-unstable";
          repo = "nixpkgs";
          type = "github";
        };
      };
      root = {
        inputs.nixpkgs = "nixpkgs";
      };
    };
    root = "root";
    version = 7;
  };

  # Install a complete configuration.nix for the VM
  environment.etc."nixos-template/configuration.nix".text = ''
    # ${vmName} VM Configuration
    # Edit this file to customize your VM, then run: switch

    { config, pkgs, ... }:

    {
      imports = [ ./hardware-configuration.nix ];

      # VM Identity
      networking.hostName = "${vmName}";

      # Current VM specs (for reference):
      # RAM: ${toString memorySize}MB
      # CPU Cores: ${toString cores}
      # Disk: ${toString diskSize}MB
      # Audio: ${if enableAudio then "enabled" else "disabled"}
      # Overlay: ${if useOverlay then "tmpfs (clean state each boot)" else "disk-based (persists across boots)"}
      #
      # Note: All VMs now support nested virtualization (building VMs inside VMs)
      # thanks to writable Nix store with ${if useOverlay then "in-memory" else "disk-persisted"} overlay

      # ==============================================================================
      # SECURITY CONSIDERATIONS
      # ==============================================================================
      # This VM is configured for LOCAL DEVELOPMENT with convenience over security.
      # Review these settings before using in production or shared environments:
      #
      # 1. EMPTY PASSWORDS (HIGH RISK)
      #    Current: Users 'dennis' and 'dvv' have empty passwords (hashedPassword = "")
      #    Risk: Anyone with network access can log in without credentials
      #    Fix: Generate password with: mkpasswd -m sha-512
      #         Then set: hashedPassword = "hash-from-mkpasswd";
      #
      # 2. PASSWORDLESS SUDO (HIGH RISK)
      #    Current: wheelNeedsPassword = false (no password required for sudo)
      #    Risk: Compromised user account = instant root access
      #    Fix: Set wheelNeedsPassword = true to require password for sudo
      #
      # 3. SSH CONFIGURATION (MEDIUM RISK)
      #    Current: PasswordAuthentication = true, PermitEmptyPasswords = true
      #    Risk: Allows SSH login without password
      #    Mitigation: VM accessible only via host port forwarding (host:2222 -> guest:22)
      #    Fix for production:
      #      - Add SSH keys: openssh.authorizedKeys.keys = [ "ssh-rsa AAAA..." ];
      #      - Disable password auth: PasswordAuthentication = false;
      #      - Disable empty passwords: PermitEmptyPasswords = false;
      #
      # 4. FIREWALL (NOW ENABLED)
      #    Current: Firewall enabled with ports 22, 3001, 9080 allowed
      #    Status: SECURE - Only necessary ports are open
      #    Customize: Add ports to networking.firewall.allowedTCPPorts as needed
      #
      # 5. AUTO-LOGIN (LOW RISK for VMs)
      #    Current: User 'dennis' auto-logs in on console
      #    Risk: Anyone with console access gets user shell
      #    Note: Console is accessible only from host via QEMU
      #
      # PRODUCTION SECURITY CHECKLIST:
      # [ ] Set strong passwords for all users (hashedPassword)
      # [ ] Add SSH public keys (openssh.authorizedKeys.keys)
      # [ ] Disable password SSH authentication (PasswordAuthentication = false)
      # [ ] Enable sudo password requirement (wheelNeedsPassword = true)
      # [ ] Review firewall rules (networking.firewall.allowedTCPPorts)
      # [ ] Disable auto-login if needed (services.getty.autologinUser = null)
      # [ ] Review user permissions and groups (extraGroups)
      #
      # For more information, see:
      # - NixOS Security: https://nixos.org/manual/nixos/stable/#sec-security
      # - SSH Hardening: https://nixos.wiki/wiki/SSH_public_key_authentication
      # ==============================================================================

      # System configuration
      boot.loader.grub.enable = true;
      boot.loader.grub.device = "/dev/vda";

      # Enable flakes
      nix.settings.experimental-features = [ "nix-command" "flakes" ];
      system.stateVersion = "23.11";

      # Networking
      networking.useDHCP = false;
      networking.interfaces.eth0.useDHCP = true;

      # Firewall configuration (enabled by default for security)
      networking.firewall = {
        enable = true;
        allowedTCPPorts = [ 22 3001 9080 ];
        # Add more ports as needed for your applications
      };

      # User configuration
      # SECURITY: Users have empty passwords for development convenience
      # For production: Generate with 'mkpasswd -m sha-512' and replace hashedPassword
      users.users.dennis = {
        isNormalUser = true;
        extraGroups = [ "wheel" "networkmanager"${if enableAudio then " \"audio\"" else ""} ];
        hashedPassword = "";  # INSECURE: Empty password - change for production
        shell = pkgs.fish;
        openssh.authorizedKeys.keys = [
          # Add your SSH public key here for key-based authentication:
          # "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... user@host"
        ];
      };

      users.users.dvv = {
        isNormalUser = true;
        extraGroups = [ "wheel" "networkmanager"${if enableAudio then " \"audio\"" else ""} ];
        hashedPassword = "";  # INSECURE: Empty password - change for production
        shell = pkgs.fish;
        openssh.authorizedKeys.keys = [ ];
      };

      # SECURITY: Passwordless sudo enabled for development convenience
      # For production: Set to true to require password for sudo
      security.sudo.wheelNeedsPassword = false;

      # Auto-login for console access (only accessible from host via QEMU)
      services.getty.autologinUser = "dennis";

      programs.fish = {
        enable = true;
        interactiveShellInit = '''
          fish_add_path --prepend /run/wrappers/bin
          fish_add_path --append /run/current-system/sw/bin
        ''';
      };

      # Services
      services.openssh = {
        enable = true;
        settings = {
          PasswordAuthentication = true;
          PermitEmptyPasswords = true;  # Required for empty password login
          PermitRootLogin = "no";
          # For production, add your SSH key to users.users.<name>.openssh.authorizedKeys.keys
          # and set: PasswordAuthentication = false; PermitEmptyPasswords = false;
        };
      };

      services.qemuGuest.enable = true;

      ${if enableAudio then ''
      # Audio configuration
      services.pulseaudio = {
        enable = true;
        systemWide = false;
        support32Bit = true;
      };

      users.groups.audio = {};
      '' else ""}

      # Packages
      nixpkgs.config.allowUnfree = true;
      nixpkgs.config.allowUnfreePredicate = pkg:
        builtins.elem (pkgs.lib.getName pkg) [ "claude-code" ];

      environment.systemPackages = with pkgs; [
        # Development tools
        git
        curl
        wget
        vim
        nano
        htop
        tree
        unzip
        file
        jq

        # Build tools
        gcc
        gnumake
        pkg-config

        # Claude Code
        claude-code

        # Additional development packages
        nodejs_22
        python3
        rustc
        cargo
        go

        # Add your packages here
      ];

      # Add your custom configuration here
      # Examples:
      # environment.systemPackages = with pkgs; [ firefox ];
      # services.docker.enable = true;
      # virtualisation.docker.enable = true;

      # To rebuild the system after making changes, run:
      #   sudo nixos-rebuild switch
      # or use the convenience command:
      #   rebuild
    }
  '';

  # Generate a basic hardware-configuration.nix for the VM
  environment.etc."nixos-template/hardware-configuration.nix".text = ''
    # Hardware configuration for ${vmName} VM
    # Generated automatically - do not edit

    { config, lib, pkgs, modulesPath, ... }:

    {
      imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

      boot.initrd.availableKernelModules = [ "ahci" "xhci_pci" "virtio_pci" "sr_mod" "virtio_blk" ];
      boot.initrd.kernelModules = [ ];
      boot.kernelModules = [ ];
      boot.extraModulePackages = [ ];

      fileSystems."/" = {
        device = "/dev/disk/by-label/nixos";
        fsType = "ext4";
      };

      swapDevices = [ ];

      networking.useDHCP = lib.mkDefault true;
      nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    }
  '';

  # Add a simple 'rebuild' command for easy VM rebuilds using flakes
  environment.etc."nixos-template/rebuild".source = pkgs.writeShellScript "vm-rebuild" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Simple VM rebuild command using flakes
    echo "🔄 Rebuilding ${vmName} VM configuration with flakes..."
    echo ""

    # Check if configuration files exist
    if [[ ! -f /etc/nixos/flake.nix ]]; then
        echo "❌ Error: /etc/nixos/flake.nix not found"
        exit 1
    fi

    if [[ ! -f /etc/nixos/configuration.nix ]]; then
        echo "❌ Error: /etc/nixos/configuration.nix not found"
        exit 1
    fi

    # Change to /etc/nixos directory (important for flakes)
    cd /etc/nixos

    # Initialize git repo if it doesn't exist (flakes need git)
    if [[ ! -d .git ]]; then
        echo "📝 Initializing git repository for flake..."
        git init --quiet
        git add .
        git commit --quiet -m "Initial VM configuration"
    fi

    # Commit any changes (flakes require clean git state)
    if git status --porcelain | grep -q .; then
        git add .
        git commit --quiet -m "Update VM configuration $(date)"
    fi

    # Run the rebuild with flakes
    echo "🔄 Rebuilding with flakes..."
    if sudo nixos-rebuild switch --flake .#${vmName} "$@"; then
        echo ""
        echo "✅ VM configuration rebuilt successfully with flakes!"
        echo "   Changes are now active."
    else
        echo ""
        echo "❌ Flake rebuild failed. Check the error messages above."
        echo ""
        echo "💡 Troubleshooting tips:"
        echo "   - Check your configuration.nix for syntax errors"
        echo "   - Run 'nix flake check .' to validate the flake"
        echo "   - Try: sudo nixos-rebuild switch --flake .#${vmName} --show-trace"
        exit 1
    fi
  '';

  # Set up /etc/nixos as a writable directory with flake configuration
  system.activationScripts.vm-nixos-setup = {
    text = ''
      # Create /etc/nixos as a real writable directory (not a symlink)
      if [ ! -d /etc/nixos ] || [ -L /etc/nixos ]; then
        rm -rf /etc/nixos
        mkdir -p /etc/nixos
      fi

      # Copy template files to /etc/nixos if they don't exist or are older
      for file in flake.nix flake.lock configuration.nix hardware-configuration.nix rebuild README.md; do
        if [ ! -f /etc/nixos/$file ] || [ /etc/nixos-template/$file -nt /etc/nixos/$file ]; then
          cp -f /etc/nixos-template/$file /etc/nixos/$file
          chmod 644 /etc/nixos/$file
        fi
      done

      # Make rebuild script executable
      chmod +x /etc/nixos/rebuild
      ln -sf /etc/nixos/rebuild /run/current-system/sw/bin/rebuild

      # Initialize git repo if it doesn't exist (required for flakes)
      if [ ! -d /etc/nixos/.git ]; then
        cd /etc/nixos
        ${pkgs.git}/bin/git init --quiet
        ${pkgs.git}/bin/git config user.name "VM User"
        ${pkgs.git}/bin/git config user.email "user@vm.local"
        ${pkgs.git}/bin/git add .
        ${pkgs.git}/bin/git commit --quiet -m "Initial VM configuration"
      fi
    '';
    deps = [ ];
  };

  # Add a helpful README
  environment.etc."nixos-template/README.md".text = ''
    # ${vmName} VM Configuration

    This directory contains the NixOS configuration for your VM.

    ## Quick Commands

    ```bash
    # Standard NixOS rebuild (automatically uses flakes)
    sudo nixos-rebuild switch

    # Alternative: use the convenience command
    rebuild

    # Other rebuild operations
    sudo nixos-rebuild test      # Test without making it boot default
    sudo nixos-rebuild boot      # Set as boot default without switching

    # Flake utilities
    nix flake check /etc/nixos
    nix flake update /etc/nixos

    # Install packages temporarily
    nix shell nixpkgs#package-name
    ```

    ## Usage Examples

    ```bash
    # Edit the configuration
    sudo nano /etc/nixos/configuration.nix

    # Add packages (add to environment.systemPackages)
    environment.systemPackages = with pkgs; [ firefox git htop ];

    # Rebuild the system (automatically uses flakes)
    sudo nixos-rebuild switch

    # Or use the convenience command
    rebuild

    # Check flake for errors before rebuilding
    nix flake check /etc/nixos
    ```

    ## Flake Benefits

    - **Reproducible**: Exact dependency versions locked in flake.lock
    - **Modern**: Uses the latest Nix flakes technology
    - **Isolated**: Dependencies are tracked and version-controlled
    - **Future-proof**: Flakes are the future of Nix configuration

    ## Configuration Files

    - **flake.nix**: Main flake configuration with VM parameters
    - **configuration.nix**: Your custom system configuration
    - **hardware-configuration.nix**: Hardware-specific settings (auto-generated)

    ## Current VM Specifications

    - **RAM**: ${toString memorySize}MB
    - **CPU Cores**: ${toString cores}
    - **Disk Size**: ${toString diskSize}MB
    - **Audio**: ${if enableAudio then "enabled" else "disabled"}
    - **Overlay FS**: ${if useOverlay then "tmpfs (clean state)" else "disk-based (persistent)"}
    - **Nested VMs**: Supported (writable Nix store enabled)

    ## Customization

    Edit \`configuration.nix\` to add packages, services, or other configuration.
    The VM parameters (RAM, CPU, etc.) are defined in \`flake.nix\`.

    ## Host System

    This VM was created with the AI VM selector tool.
    Original host configuration: /home/dennis/Projects/nixos-configs/ai-vm
  '';
}