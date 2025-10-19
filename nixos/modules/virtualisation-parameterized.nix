{ config, pkgs, vmSize ? "8gb-2cpu-50gb", useOverlay ? false, ... }:

let
  sizes = import ./vm-sizes.nix;
  selectedSize = sizes.vmSizes.${vmSize};
in
{
  # VM-specific settings with parameterized size
  virtualisation.vmVariant = {
    virtualisation.memorySize = selectedSize.memorySize;
    virtualisation.cores = selectedSize.cores;
    virtualisation.diskSize = selectedSize.diskSize;

    # Disable graphics for headless operation
    virtualisation.graphics = false;

    # Configure writable store based on overlay option
    virtualisation.writableStore = useOverlay;

    # Port forwarding for SSH and development servers
    virtualisation.forwardPorts = [
      { from = "host"; host.port = 2222; guest.port = 22; }
      { from = "host"; host.port = 3001; guest.port = 3001; }
      { from = "host"; host.port = 9080; guest.port = 9080; }
    ];
  };
}