{ config, pkgs, ... }:

{
  # User configuration
  # SECURITY NOTE: Users have empty passwords for development convenience
  # For production use:
  # - Generate a hashed password: mkpasswd -m sha-512
  # - Replace hashedPassword = "" with the generated hash
  # - Add SSH public keys to openssh.authorizedKeys.keys
  users.users.dennis = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    hashedPassword = "";
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = [ ];
  };

  users.users.dvv = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    hashedPassword = "";
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = [ ];
  };

  # Sudo configuration
  # SECURITY CONSIDERATION:
  # Passwordless sudo is enabled for development convenience (wheelNeedsPassword = false)
  # This allows wheel group members to run sudo commands without entering a password
  #
  # Trade-offs:
  # - PRO: Faster development workflow, no interruptions for sudo password
  # - PRO: Useful for automated scripts and system rebuilds
  # - CON: Any process running as a wheel user can gain root access
  # - CON: If an attacker compromises a user account, they get instant root access
  #
  # For production or shared environments:
  # - Set wheelNeedsPassword = true to require password for sudo
  # - Consider more granular sudo rules in security.sudo.extraRules
  # - See: https://nixos.org/manual/nixos/stable/options.html#opt-security.sudo.extraRules
  security.sudo.wheelNeedsPassword = false;

  # Auto-login configuration
  services.getty.autologinUser = "dennis";

  # Enable fish shell
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      fish_add_path --prepend /run/wrappers/bin
      fish_add_path --append /run/current-system/sw/bin
    '';
  };
}
