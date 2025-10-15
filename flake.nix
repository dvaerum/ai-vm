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
            # Import module functions
            usersModule = import ./nixos/modules/users.nix;
            networkingModule = import ./nixos/modules/networking.nix;
            packagesModule = import ./nixos/modules/packages.nix;
            virtualisationModule = import ./nixos/modules/virtualisation.nix;

            vm-system = nixpkgs.lib.nixosSystem {
              system = system;
              modules = [
                ({ config, pkgs, ... }: {
                  # Allow unfree packages (needed for Claude Code)
                  nixpkgs.config.allowUnfree = true;
                })
                usersModule
                networkingModule
                packagesModule
                virtualisationModule
                ({ config, pkgs, ... }: {
                  # Basic VM configuration
                  boot.loader.grub.enable = true;
                  boot.loader.grub.device = "/dev/vda";

                  # Enable flakes
                  nix.settings.experimental-features = [ "nix-command" "flakes" ];

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
