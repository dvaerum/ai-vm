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
    else
        # Add any new changes
        git add .
        if ! git diff --cached --quiet; then
            git commit --quiet -m "Update VM configuration $(date)"
        fi
    fi

    # Update git repo with any changes (flakes require clean git state)
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
    - **Overlay FS**: ${if useOverlay then "enabled" else "disabled"}

    ## Customization

    Edit \`configuration.nix\` to add packages, services, or other configuration.
    The VM parameters (RAM, CPU, etc.) are defined in \`flake.nix\`.

    ## Host System

    This VM was created with the AI VM selector tool.
    Original host configuration: /home/dennis/Projects/nixos-configs/ai-vm
  '';
}