{ config, pkgs, ... }:

{
  # Network configuration
  # Note: hostname is set in virtualisation-parameterized.nix based on vmName parameter
  networking.networkmanager.enable = true;

  # Enable SSH for remote access
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = true;
  services.openssh.settings.PermitEmptyPasswords = true;
  services.openssh.settings.ChallengeResponseAuthentication = false;
  services.openssh.settings.UsePAM = false;
}