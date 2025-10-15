{
  description = "VM environment for running Claude Code";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        packages.vm =
          let
            vm-system = nixpkgs.lib.nixosSystem {
              system = system;
              modules = [
                ({ config, pkgs, ... }: {
                  # Basic VM configuration
                  boot.loader.grub.enable = true;
                  boot.loader.grub.device = "/dev/vda";

                  # Network configuration
                  networking.hostName = "claude-code-vm";
                  networking.networkmanager.enable = true;

                  # Enable SSH for remote access
                  services.openssh.enable = true;
                  services.openssh.settings.PasswordAuthentication = true;

                  # User configuration
                  users.users.claude = {
                    isNormalUser = true;
                    extraGroups = [ "wheel" "networkmanager" ];
                    password = "claude";
                    openssh.authorizedKeys.keys = [ ];
                  };

                  # Enable sudo for wheel group
                  security.sudo.wheelNeedsPassword = false;

                  # Development tools and Claude Code dependencies
                  environment.systemPackages = with pkgs; [
                    # Basic system tools
                    curl
                    wget
                    git
                    vim
                    nano
                    htop
                    tree
                    unzip

                    # Development tools
                    nodejs_20
                    python3
                    python3Packages.pip
                    rustc
                    cargo
                    go

                    # Build tools
                    gcc
                    gnumake

                    # Claude Code and AI tools
                    # Note: Claude Code would need to be installed separately
                    # or built from source if available
                  ];

                  # Enable flakes
                  nix.settings.experimental-features = [ "nix-command" "flakes" ];

                  # VM-specific settings
                  virtualisation.vmVariant = {
                    virtualisation.memorySize = 8192;
                    virtualisation.cores = 2;
                    virtualisation.diskSize = 51200;

                    # Enable graphics for GUI if needed
                    virtualisation.graphics = true;

                    # Port forwarding for SSH and development servers
                    virtualisation.forwardPorts = [
                      { from = "host"; host.port = 2222; guest.port = 22; }
                      { from = "host"; host.port = 3000; guest.port = 3000; }
                      { from = "host"; host.port = 8080; guest.port = 8080; }
                    ];
                  };

                  # Enable X11 and desktop environment (optional)
                  services.xserver.enable = true;
                  services.xserver.displayManager.lightdm.enable = true;
                  services.xserver.desktopManager.xfce.enable = true;

                  # System version
                  system.stateVersion = "23.11";
                })
              ];
            };
          in
            vm-system.config.system.build.vm;

        # App to run the VM directly
        apps.default = {
          type = "app";
          program = "${self.packages.${system}.vm}/bin/run-claude-code-vm-vm";
        };

        # Development shell for working with the flake
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nixos-rebuild
            qemu
            qemu_kvm
          ];

          shellHook = ''
            echo "Claude Code VM development environment"
            echo "Run 'nix run' to start the VM"
            echo "Run 'nix build .#vm' to build the VM"
            echo "Run 'result/bin/run-*-vm' to start the VM manually"
          '';
        };
      });
}