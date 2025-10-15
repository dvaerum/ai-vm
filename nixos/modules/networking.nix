{ config, pkgs, ... }:

{
  # Network configuration
  networking.hostName = "ai-vm";
  networking.networkmanager.enable = true;

  # Enable SSH for remote access
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = true;
  services.openssh.settings.PermitEmptyPasswords = true;
  services.openssh.settings.ChallengeResponseAuthentication = false;
  services.openssh.settings.UsePAM = false;
}