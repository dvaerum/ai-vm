{ config, pkgs, ... }:

{
  # VM-specific settings
  virtualisation.vmVariant = {
    virtualisation.memorySize = 8192;
    virtualisation.cores = 2;
    virtualisation.diskSize = 51200;

    # Disable graphics for headless operation
    virtualisation.graphics = false;

    # Port forwarding for SSH and development servers
    virtualisation.forwardPorts = [
      { from = "host"; host.port = 2222; guest.port = 22; }
      { from = "host"; host.port = 3001; guest.port = 3001; }
      { from = "host"; host.port = 9080; guest.port = 9080; }
    ];
  };
}
