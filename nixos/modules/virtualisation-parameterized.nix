{ config, pkgs, memorySize ? 8192, cores ? 2, diskSize ? 51200, useOverlay ? false, sharedFoldersRW ? [], sharedFoldersRO ? [], vmName ? "ai-vm", enableAudio ? false, ... }:

{
  # Set system hostname to VM name
  networking.hostName = pkgs.lib.mkForce vmName;

  # VM-specific settings with parameterized size
  virtualisation.vmVariant = {
    virtualisation.memorySize = memorySize;
    virtualisation.cores = cores;
    virtualisation.diskSize = diskSize;

    # Disable graphics for headless operation
    virtualisation.graphics = false;

    # Configure writable store based on overlay option
    virtualisation.writableStore = useOverlay;

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
      let
        # Generate short mount tag from path (max 31 chars for QEMU)
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
      let
        # Use same mount tag generation as above
        mkMountTag = prefix: path:
          let
            basename = builtins.baseNameOf path;
            pathHash = builtins.substring 0 8 (builtins.hashString "sha256" path);
            maxBasename = 19;
            shortBasename = if builtins.stringLength basename > maxBasename
                           then builtins.substring 0 maxBasename basename
                           else basename;
          in "${prefix}${pathHash}-${shortBasename}";
      in
      builtins.listToAttrs (builtins.map (path: {
        name = "/mnt/host-ro/${builtins.baseNameOf path}";
        value = {
          device = mkMountTag "ro" path;
          fsType = "9p";
          options = ["trans=virtio" "version=9p2000.L" "ro"];
        };
      }) sharedFoldersRO);
  };

  # Audio system configuration (enabled when audio passthrough is requested)
  services.pulseaudio = {
    enable = enableAudio;
    systemWide = false;
    support32Bit = true;
  };

  # For better audio compatibility, we might want to add pipewire support as well
  # services.pipewire = {
  #   enable = enableAudio;
  #   alsa.enable = true;
  #   alsa.support32Bit = true;
  #   pulse.enable = true;
  # };

  # Add audio group for users when audio is enabled
  users.groups = pkgs.lib.mkIf enableAudio {
    audio = {};
  };

  # Add users to audio group when audio is enabled
  users.users.dennis.extraGroups = pkgs.lib.mkIf enableAudio [ "wheel" "networkmanager" "audio" ];
  users.users.dvv.extraGroups = pkgs.lib.mkIf enableAudio [ "wheel" "networkmanager" "audio" ];

  # Install VM configuration flake at /etc/nixos
  environment.etc."nixos/flake.nix".text = ''
    {
      description = "AI VM NixOS Configuration - ${vmName}";

      inputs = {
        nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
      };

      outputs = { self, nixpkgs }:
      let
        system = "x86_64-linux";
        pkgs = nixpkgs.legacyPackages.$${system};
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

  # Install a complete configuration.nix for the VM
  environment.etc."nixos/configuration.nix".text = ''
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
      # Overlay: ${if useOverlay then "enabled" else "disabled"}

      # System configuration
      boot.loader.grub.enable = true;
      boot.loader.grub.device = "/dev/vda";

      # Enable flakes
      nix.settings.experimental-features = [ "nix-command" "flakes" ];
      system.stateVersion = "23.11";

      # Networking
      networking.useDHCP = false;
      networking.interfaces.eth0.useDHCP = true;
      networking.firewall.enable = false;

      # User configuration
      users.users.dennis = {
        isNormalUser = true;
        extraGroups = [ "wheel" "networkmanager"${if enableAudio then " \"audio\"" else ""} ];
        hashedPassword = "";
        shell = pkgs.fish;
        openssh.authorizedKeys.keys = [ ];
      };

      users.users.dvv = {
        isNormalUser = true;
        extraGroups = [ "wheel" "networkmanager"${if enableAudio then " \"audio\"" else ""} ];
        hashedPassword = "";
        shell = pkgs.fish;
        openssh.authorizedKeys.keys = [ ];
      };

      security.sudo.wheelNeedsPassword = false;
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
          PermitRootLogin = "no";
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

      # To rebuild the system after making changes:
      # rebuild
    }
  '';

  # Generate a basic hardware-configuration.nix for the VM
  environment.etc."nixos/hardware-configuration.nix".text = ''
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
  environment.etc."nixos/rebuild".source = pkgs.writeShellScript "vm-rebuild" ''
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
    else
        # Add any new changes
        git add .
        if ! git diff --cached --quiet; then
            git commit --quiet -m "Update VM configuration $(date)"
        fi
    fi

    # Try to rebuild with flakes first, fallback to traditional method
    echo "🔄 Attempting flake-based rebuild..."
    if sudo nixos-rebuild switch --flake .#${vmName} "$@" 2>/dev/null; then
        echo ""
        echo "✅ VM configuration rebuilt successfully with flakes!"
        echo "   Changes are now active."
    else
        echo "⚠️  Flake rebuild failed, trying traditional method..."
        echo ""

        # Fallback to traditional rebuild method
        if sudo nixos-rebuild switch -I nixos-config=/etc/nixos/configuration.nix "$@"; then
            echo ""
            echo "✅ VM configuration rebuilt successfully (traditional method)!"
            echo "   Changes are now active."
            echo ""
            echo "ℹ️  Note: Used traditional rebuild due to flake limitations in VM environment."
        else
            echo ""
            echo "❌ Both flake and traditional rebuilds failed."
            echo ""
            echo "💡 Troubleshooting tips:"
            echo "   - Check your configuration.nix for syntax errors"
            echo "   - Try running: sudo nixos-rebuild switch -I nixos-config=/etc/nixos/configuration.nix --show-trace"
            exit 1
        fi
    fi
  '';

  # Make the rebuild command executable and accessible
  system.activationScripts.vm-rebuild-command = ''
    chmod +x /etc/nixos/rebuild
    ln -sf /etc/nixos/rebuild /run/current-system/sw/bin/rebuild
  '';

  # Add a helpful README
  environment.etc."nixos/README.md".text = ''
    # ${vmName} VM Configuration

    This directory contains the NixOS configuration for your VM.

    ## Quick Commands

    ```bash
    # Easy flake-based rebuild (recommended)
    rebuild

    # Alternative flake commands
    sudo nixos-rebuild switch --flake /etc/nixos#${vmName}
    sudo nixos-rebuild test --flake /etc/nixos#${vmName}

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

    # Rebuild with flakes using the simple command
    rebuild

    # Or use the full flake command
    sudo nixos-rebuild switch --flake /etc/nixos#${vmName}

    # Check flake for errors
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
    - **Overlay FS**: ${if useOverlay then "enabled" else "disabled"}

    ## Customization

    Edit \`configuration.nix\` to add packages, services, or other configuration.
    The VM parameters (RAM, CPU, etc.) are defined in \`flake.nix\`.

    ## Host System

    This VM was created with the AI VM selector tool.
    Original host configuration: /home/dennis/Projects/nixos-configs/ai-vm
  '';
}