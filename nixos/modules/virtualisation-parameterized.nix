# VM/QEMU-specific configuration for AI VM
# This module contains all VM-specific settings: virtualisation, templates, activation.

{ config, pkgs, lib, memorySize ? 8192, cores ? 2, diskSize ? 51200, useOverlay ? false, sharedFoldersRW ? [], sharedFoldersRO ? [], vmName ? "ai-vm", enableAudio ? false, enableDesktop ? false, portMappings ? [{ host = 2222; guest = 22; }], resolution ? null, nixpkgsRev ? "unknown", nixpkgsNarHash ? "unknown", ... }:

let
  # Generate short mount tag from path (max 31 chars for QEMU)
  mkMountTag = prefix: path:
    let
      basename = builtins.baseNameOf path;
      pathHash = builtins.substring 0 8 (builtins.hashString "sha256" path);
      maxBasename = 19;
      shortBasename = if builtins.stringLength basename > maxBasename
                     then builtins.substring 0 maxBasename basename
                     else basename;
    in "${prefix}${pathHash}-${shortBasename}";

  # Format port mappings for display (e.g., "2222→22, 3001→3001")
  portMappingsStr = builtins.concatStringsSep ", " (builtins.map (p: "${toString p.host}→${toString p.guest}") portMappings);

  # Get list of guest ports for firewall
  guestPorts = builtins.map (p: p.guest) portMappings;
  guestPortsStr = builtins.concatStringsSep " " (builtins.map toString guestPorts);

  # Parse resolution string (e.g., "1920x1080") into width and height
  parseResolution = res:
    if res == null then null
    else
      let
        parts = builtins.match "([0-9]+)x([0-9]+)" res;
      in
      if parts == null then null
      else {
        width = builtins.elemAt parts 0;
        height = builtins.elemAt parts 1;
      };

  parsedResolution = parseResolution resolution;
  hasResolution = parsedResolution != null;
  resolutionStr = if hasResolution then resolution else "auto";
in
{
  # ==========================================================================
  # VM IDENTITY & PARAMETERIZED SETTINGS
  # ==========================================================================

  # Set system hostname to VM name
  networking.hostName = lib.mkForce vmName;

  # Audio system configuration (enabled when audio passthrough is requested)
  services.pulseaudio = {
    enable = enableAudio;
    systemWide = false;
    support32Bit = true;
  };

  # Add audio group for users when audio is enabled
  users.groups = lib.mkIf enableAudio {
    audio = {};
  };

  users.users.dennis.extraGroups = lib.mkIf enableAudio [ "wheel" "networkmanager" "audio" ];
  users.users.dvv.extraGroups = lib.mkIf enableAudio [ "wheel" "networkmanager" "audio" ];

  # Desktop environment (KDE Plasma with Wayland)
  services.displayManager.sddm.enable = enableDesktop;
  services.displayManager.sddm.wayland.enable = enableDesktop;
  services.desktopManager.plasma6.enable = enableDesktop;

  # Set virtual console resolution via kernel parameters (for early boot and TTY)
  boot.kernelParams = lib.optionals (enableDesktop && hasResolution) [
    "video=${resolution}"
  ];

  # Firewall: open guest ports based on port mappings
  networking.firewall.allowedTCPPorts = builtins.map (p: p.guest) portMappings;

  # System packages: nixos-rebuild wrapper + resolution tools if desktop enabled
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "nixos-rebuild" ''
      # Wrapper for nixos-rebuild that automatically uses flakes
      if [ -f /etc/nixos/flake.nix ]; then
        if ! echo "$@" | grep -q -- "--flake"; then
          exec ${pkgs.nixos-rebuild}/bin/nixos-rebuild "$@" --flake "path:/etc/nixos#${vmName}"
        fi
      fi
      exec ${pkgs.nixos-rebuild}/bin/nixos-rebuild "$@"
    '')
  ]
  # Add desktop applications when desktop mode is enabled
  ++ lib.optionals enableDesktop [
    pkgs.firefox
  ]
  # Add resolution configuration tools when desktop with custom resolution is enabled
  ++ lib.optionals (enableDesktop && hasResolution) [
    pkgs.kdePackages.libkscreen
    (pkgs.writeShellScriptBin "set-resolution" ''
      # Set display resolution for virtual output
      # Wait for display to be ready
      sleep 2

      # Try using kscreen-doctor (KDE's display configuration tool)
      if command -v kscreen-doctor &>/dev/null; then
        # List available outputs and set resolution
        kscreen-doctor output.Virtual-1.mode.${resolution}@60 2>/dev/null || \
        kscreen-doctor output.VIRTUAL-1.mode.${resolution}@60 2>/dev/null || \
        kscreen-doctor output.1.mode.${resolution}@60 2>/dev/null || true
      fi

      # Fallback: try wlr-randr for wlroots-based compositors
      if command -v wlr-randr &>/dev/null; then
        wlr-randr --output Virtual-1 --mode ${resolution} 2>/dev/null || true
      fi
    '')
  ];

  # ==========================================================================
  # QEMU/VM SETTINGS
  # ==========================================================================

  virtualisation.vmVariant = {
    virtualisation.memorySize = memorySize;
    virtualisation.cores = cores;
    virtualisation.diskSize = diskSize;
    virtualisation.graphics = enableDesktop;

    # Writable store for nested VM support
    virtualisation.writableStore = true;
    virtualisation.writableStoreUseTmpfs = useOverlay;

    # VM disk image name
    virtualisation.diskImage = "./${vmName}.qcow2";

    # Port forwarding (dynamic based on portMappings parameter)
    virtualisation.forwardPorts = builtins.map (p: {
      from = "host";
      host.port = p.host;
      guest.port = p.guest;
    }) portMappings;

    # QEMU options: audio passthrough and display resolution
    virtualisation.qemu.options =
      # Audio passthrough options
      lib.optionals enableAudio [
        "-audiodev" "pa,id=pa1,in.name=${vmName}-input,out.name=${vmName}-output"
        "-device" "intel-hda"
        "-device" "hda-duplex,audiodev=pa1"
      ];

    # Shared folders
    virtualisation.sharedDirectories =
      {
        "nix-store" = {
          source = "/nix/store";
          target = "/nix/.ro-store";
        };
      } //
      (builtins.listToAttrs (builtins.map (path: {
        name = mkMountTag "rw" path;
        value = {
          source = path;
          target = "/mnt/host-rw/${builtins.baseNameOf path}";
        };
      }) sharedFoldersRW)) //
      (builtins.listToAttrs (builtins.map (path: {
        name = mkMountTag "ro" path;
        value = {
          source = path;
          target = "/mnt/host-ro/${builtins.baseNameOf path}";
        };
      }) sharedFoldersRO));

    # Filesystem mounts
    fileSystems =
      {
        "/nix/.ro-store" = {
          device = "nix-store";
          fsType = "9p";
          options = ["trans=virtio" "version=9p2000.L" "msize=104857600" "cache=loose" "ro"];
          neededForBoot = true;
        };
      } //
      (builtins.listToAttrs (builtins.map (path: {
        name = "/mnt/host-ro/${builtins.baseNameOf path}";
        value = {
          device = mkMountTag "ro" path;
          fsType = "9p";
          options = ["trans=virtio" "version=9p2000.L" "ro"];
        };
      }) sharedFoldersRO));
  };

  # ==========================================================================
  # /etc/nixos TEMPLATES
  # These are copied to /etc/nixos on first boot only.
  # User can reset by deleting /etc/nixos and rebooting.
  # ==========================================================================

  # Module files - copied from actual source files
  environment.etc."nixos-template/modules/configuration.nix".source = ./configuration.nix;
  environment.etc."nixos-template/modules/users.nix".source = ./users.nix;
  environment.etc."nixos-template/modules/packages.nix".source = ./packages.nix;
  environment.etc."nixos-template/modules/networking.nix".source = ./networking.nix;

  # Hardware configuration - static template
  environment.etc."nixos-template/hardware-configuration.nix".source = ../templates/hardware-configuration.nix;

  # VM-specific info (baked-in parameters)
  environment.etc."nixos-template/vm-info.nix".text = ''
    # VM-specific configuration
    # Generated at VM build time with baked-in parameters.

    { config, pkgs, lib, ... }:

    {
      networking.hostName = lib.mkDefault "${vmName}";

      # VM Specifications (reference only - these are QEMU settings)
      # RAM: ${toString memorySize}MB | CPU: ${toString cores} cores | Disk: ${toString diskSize}MB
      # Audio: ${if enableAudio then "enabled" else "disabled"} | Desktop: ${if enableDesktop then "KDE Plasma (${resolutionStr})" else "disabled"} | Overlay: ${if useOverlay then "tmpfs" else "disk"}
      # Port forwards: ${portMappingsStr}

      boot.loader.grub.enable = true;
      boot.loader.grub.device = "/dev/vda";

      networking.useDHCP = false;
      networking.interfaces.eth0.useDHCP = true;
      networking.firewall.allowedTCPPorts = [ ${guestPortsStr} ];

      services.qemuGuest.enable = true;

      ${lib.optionalString enableAudio ''
      services.pulseaudio = {
        enable = true;
        systemWide = false;
        support32Bit = true;
      };
      users.groups.audio = {};
      ''}
      ${lib.optionalString enableDesktop ''
      services.displayManager.sddm.enable = true;
      services.displayManager.sddm.wayland.enable = true;
      services.desktopManager.plasma6.enable = true;
      ''}
    }
  '';

  # Flake definition
  environment.etc."nixos-template/flake.nix".text = ''
    {
      description = "AI VM NixOS Configuration - ${vmName}";

      inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

      outputs = { self, nixpkgs }:
      {
        nixosConfigurations.${vmName} = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hardware-configuration.nix
            ./vm-info.nix
            ./modules/configuration.nix
            ./modules/users.nix
            ./modules/packages.nix
            ./modules/networking.nix
          ];
        };
      };
    }
  '';

  # Flake lock file (pins nixpkgs to same version as host)
  environment.etc."nixos-template/flake.lock".text = builtins.toJSON {
    nodes = {
      nixpkgs = {
        locked = {
          type = "github";
          owner = "NixOS";
          repo = "nixpkgs";
          rev = nixpkgsRev;
          narHash = nixpkgsNarHash;
        };
        original = {
          type = "github";
          owner = "NixOS";
          repo = "nixpkgs";
          ref = "nixos-unstable";
        };
      };
      root = {
        inputs = {
          nixpkgs = "nixpkgs";
        };
      };
    };
    root = "root";
    version = 7;
  };

  # Auto-run resolution script at user login (for KDE Plasma)
  # Only created when desktop mode is enabled with a custom resolution
  environment.etc."xdg/autostart/set-resolution.desktop" = lib.mkIf (enableDesktop && hasResolution) {
    text = ''
      [Desktop Entry]
      Type=Application
      Name=Set Display Resolution
      Exec=set-resolution
      X-KDE-autostart-phase=2
    '';
  };

  # Rebuild script
  environment.etc."nixos-template/rebuild".source = pkgs.writeShellScript "vm-rebuild" ''
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Rebuilding VM configuration..."
    if [[ ! -f /etc/nixos/flake.nix ]]; then
      echo "Error: /etc/nixos/flake.nix not found"
      exit 1
    fi
    if sudo nixos-rebuild switch --flake "path:/etc/nixos#${vmName}" "$@"; then
      echo "Rebuild successful!"
    else
      echo "Rebuild failed. Try: nix flake check path:/etc/nixos"
      exit 1
    fi
  '';

  # README
  environment.etc."nixos-template/README.md".text = ''
    # ${vmName} VM Configuration

    ## Quick Start
    ```bash
    sudo nano /etc/nixos/modules/packages.nix  # Add packages
    rebuild                                      # Apply changes
    ```

    ## Structure
    ```
    /etc/nixos/
    ├── flake.nix              # Flake definition
    ├── flake.lock             # Pinned nixpkgs (same as host)
    ├── vm-info.nix            # VM parameters (RAM: ${toString memorySize}MB, CPU: ${toString cores}, Disk: ${toString diskSize}MB)
    ├── hardware-configuration.nix
    └── modules/
        ├── configuration.nix  # Firewall, GC, base settings
        ├── users.nix          # User accounts
        ├── packages.nix       # Installed packages
        └── networking.nix     # SSH config
    ```

    ## Update nixpkgs
    ```bash
    nix flake update path:/etc/nixos && rebuild
    ```

    ## Reset to defaults
    ```bash
    sudo rm -rf /etc/nixos && sudo reboot
    ```
  '';

  # ==========================================================================
  # ACTIVATION SCRIPT
  # Copies templates to /etc/nixos on first boot only.
  # ==========================================================================

  system.activationScripts.vm-nixos-setup = {
    text = ''
      # Only create /etc/nixos if it doesn't exist
      if [ ! -d /etc/nixos ]; then
        echo "First boot: setting up /etc/nixos from templates..."

        mkdir -p /etc/nixos/modules

        # Copy all template files
        cp /etc/nixos-template/flake.nix /etc/nixos/
        cp /etc/nixos-template/flake.lock /etc/nixos/
        cp /etc/nixos-template/vm-info.nix /etc/nixos/
        cp /etc/nixos-template/hardware-configuration.nix /etc/nixos/
        cp /etc/nixos-template/rebuild /etc/nixos/
        cp /etc/nixos-template/README.md /etc/nixos/
        cp /etc/nixos-template/modules/*.nix /etc/nixos/modules/

        chmod 644 /etc/nixos/*.nix /etc/nixos/*.lock /etc/nixos/*.md /etc/nixos/modules/*.nix
        chmod +x /etc/nixos/rebuild

        echo "/etc/nixos setup complete."
      fi

      # Always ensure rebuild is in PATH
      ln -sf /etc/nixos/rebuild /run/current-system/sw/bin/rebuild 2>/dev/null || true
    '';
    deps = [ ];
  };
}
