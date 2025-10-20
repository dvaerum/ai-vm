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
      # Read-write shared folders
      (builtins.listToAttrs (builtins.map (path: {
        name = "rw-${builtins.replaceStrings ["/"] ["-"] (builtins.substring 1 (builtins.stringLength path - 1) path)}";
        value = {
          source = path;
          target = "/mnt/host-rw${path}";
        };
      }) sharedFoldersRW)) //
      # Read-only shared folders (note: readonly is enforced via mount options, not via QEMU)
      (builtins.listToAttrs (builtins.map (path: {
        name = "ro-${builtins.replaceStrings ["/"] ["-"] (builtins.substring 1 (builtins.stringLength path - 1) path)}";
        value = {
          source = path;
          target = "/mnt/host-ro${path}";
        };
      }) sharedFoldersRO));

    # Mount shared folders as read-only where needed
    fileSystems = builtins.listToAttrs (builtins.map (path: {
      name = "/mnt/host-ro${path}";
      value = {
        device = "ro-${builtins.replaceStrings ["/"] ["-"] (builtins.substring 1 (builtins.stringLength path - 1) path)}";
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
}