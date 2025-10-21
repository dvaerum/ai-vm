{ config, pkgs, ... }:

{
  # Network configuration
  # Note: hostname is set in virtualisation-parameterized.nix based on vmName parameter
  networking.networkmanager.enable = true;

  # SSH Configuration
  # SECURITY CONSIDERATIONS:
  # The current configuration is optimized for local development VMs with these trade-offs:
  #
  # 1. EMPTY PASSWORDS: Users (dennis, dvv) have empty passwords for quick local access
  #    - PermitEmptyPasswords = true: Allows SSH login with empty passwords
  #    - PasswordAuthentication = true: Enables password-based authentication
  #    - Risk: Anyone with network access to port 2222 can log in without credentials
  #    - Mitigation: VMs are designed for local-only use with port forwarding (host:2222 -> guest:22)
  #
  # 2. SSH KEY-BASED AUTH: Supported alongside password auth
  #    - Users can add SSH public keys to openssh.authorizedKeys.keys in users.nix
  #    - For production: disable password auth and use keys only
  #
  # TO SECURE FOR PRODUCTION OR SHARED ENVIRONMENTS:
  # - Set proper user passwords (hashedPassword in users.nix)
  # - Set PermitEmptyPasswords = false
  # - Consider PasswordAuthentication = false (keys only)
  # - Add your public key to openssh.authorizedKeys.keys
  # - Enable the firewall (see virtualisation-parameterized.nix)
  # - Review the "Security Considerations" section in /etc/nixos/configuration.nix
  #
  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = true;
  services.openssh.settings.PermitEmptyPasswords = true;
  services.openssh.settings.ChallengeResponseAuthentication = false;
  services.openssh.settings.UsePAM = false;
}