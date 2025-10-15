{ config, pkgs, ... }:

{
  # Network configuration
  networking.hostName = "claude-code-vm";
  networking.networkmanager.enable = true;

  # Enable SSH for remote access
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = true;
  services.openssh.settings.PermitEmptyPasswords = true;
}