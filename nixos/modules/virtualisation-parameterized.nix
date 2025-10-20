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
        vmSystem = "x86_64-linux";
        pkgs = nixpkgs.legacyPackages.$${vmSystem};
      in
      {
        nixosConfigurations.${vmName} = nixpkgs.lib.nixosSystem {
          system = vmSystem;
          modules = [
            ./configuration.nix
            {
              # VM-specific configuration
              networking.hostName = "${vmName}";

              # Virtualisation settings (current configuration)
              virtualisation.vmVariant = {
                virtualisation.memorySize = ${toString memorySize};
                virtualisation.cores = ${toString cores};
                virtualisation.diskSize = ${toString diskSize};
                virtualisation.graphics = false;
                virtualisation.writableStore = ${if useOverlay then "true" else "false"};
                virtualisation.diskImage = "./${vmName}.qcow2";

                virtualisation.forwardPorts = [
                  { from = "host"; host.port = 2222; guest.port = 22; }
                  { from = "host"; host.port = 3001; guest.port = 3001; }
                  { from = "host"; host.port = 9080; guest.port = 9080; }
                ];

                ${if enableAudio then ''
                virtualisation.qemu.options = [
                  "-audiodev"
                  "pa,id=pa1,in.name=${vmName}-input,out.name=${vmName}-output"
                  "-device"
                  "intel-hda"
                  "-device"
                  "hda-duplex,audiodev=pa1"
                ];
                '' else ''
                virtualisation.qemu.options = [];
                ''}
              };

              # System configuration
              boot.loader.grub.enable = true;
              boot.loader.grub.device = "/dev/vda";

              nix.settings.experimental-features = [ "nix-command" "flakes" ];
              system.stateVersion = "23.11";

              # Audio configuration
              ${if enableAudio then ''
              services.pulseaudio = {
                enable = true;
                systemWide = false;
                support32Bit = true;
              };

              users.groups.audio = {};
              '' else ""}

              # User configuration
              users.users.dennis = {
                isNormalUser = true;
                extraGroups = [ "wheel" "networkmanager" ${if enableAudio then "\"audio\"" else ""} ];
                hashedPassword = "";
                shell = pkgs.fish;
                openssh.authorizedKeys.keys = [ ];
              };

              users.users.dvv = {
                isNormalUser = true;
                extraGroups = [ "wheel" "networkmanager" ${if enableAudio then "\"audio\"" else ""} ];
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

              # Networking
              networking.useDHCP = false;
              networking.interfaces.eth0.useDHCP = true;
              networking.firewall.enable = false;

              # Services
              services.openssh = {
                enable = true;
                settings = {
                  PasswordAuthentication = true;
                  PermitRootLogin = "no";
                };
              };

              services.qemuGuest.enable = true;

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
              ];
            }
          ];
        };
      };
    }
  '';

  # Install a basic configuration.nix that imports hardware-configuration.nix
  environment.etc."nixos/configuration.nix".text = ''
    # ${vmName} VM Configuration
    # Edit this file to customize your VM, then run: sudo nixos-rebuild switch

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

      # Add your custom configuration here
      # Examples:
      # environment.systemPackages = with pkgs; [ firefox ];
      # services.docker.enable = true;
      # virtualisation.docker.enable = true;

      # To rebuild the system:
      # sudo nixos-rebuild switch -I nixos-config=/etc/nixos/configuration.nix
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

  # Add a helpful README
  environment.etc."nixos/README.md".text = ''
    # ${vmName} VM Configuration

    This directory contains the NixOS configuration for your VM.

    ## Quick Commands

    ```bash
    # Rebuild the system (recommended method for VMs)
    sudo nixos-rebuild switch -I nixos-config=/etc/nixos/configuration.nix

    # Test a configuration without switching
    sudo nixos-rebuild test -I nixos-config=/etc/nixos/configuration.nix

    # Show current configuration
    sudo nix-instantiate --eval -E "with import <nixpkgs/nixos> {}; config.system.nixos.release"

    # Alternative: Install packages temporarily
    nix-shell -p package-name

    # Note: The flake.nix is provided for reference but VM rebuilds work better
    # with the traditional nixos-rebuild approach shown above.
    ```

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