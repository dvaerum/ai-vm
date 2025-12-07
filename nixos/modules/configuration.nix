# Base system configuration for AI VM
# This module contains pure system settings with no VM-specific parameters.
# It can be used both on the host (during VM build) and inside the VM.

{ config, pkgs, lib, ... }:

{
  # Base NixOS settings
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = "23.11";

  # Unfree packages allowlist
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [ "claude-code" ];

  # Firewall configuration
  # SECURITY: Firewall is enabled by default
  # Allowed ports are configured dynamically in virtualisation-parameterized.nix
  networking.firewall.enable = true;

  # Nix garbage collection
  nix.gc = {
    automatic = true;
    persistent = true;
    randomizedDelaySec = "10min";
    dates = "*-*-* 0/2:00:00";
  };

  # Nix overlay cleanup script (for VMs with writable store)
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "nix-overlay-cleanup" (builtins.readFile ./nix-overlay-cleanup.sh))
  ];

  # Systemd service for automatic Nix overlay cleanup
  systemd.services.nix-overlay-gc = {
    description = "Nix Overlay Garbage Collection";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/run/current-system/sw/bin/nix-overlay-cleanup --full";
      StandardOutput = "journal";
      StandardError = "journal";
    };
  };

  # Timer to run the cleanup hourly
  systemd.timers.nix-overlay-gc = {
    description = "Nix Overlay Garbage Collection Timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      OnBootSec = "30min";
      Persistent = true;
    };
  };
}
