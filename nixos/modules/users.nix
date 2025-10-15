{ config, pkgs, ... }:

{
  # User configuration
  users.users.dennis = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    hashedPassword = "";
    shell = pkgs.fish;
    openssh.authorizedKeys.keys = [ ];
  };

  # Enable sudo for wheel group
  security.sudo.wheelNeedsPassword = false;

  # Auto-login configuration
  services.getty.autologinUser = "dennis";

  # Enable fish shell
  programs.fish.enable = true;
}