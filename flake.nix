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
        vmSizes = import ./nixos/modules/vm-sizes.nix;
      in
      let
        # Function to create VM with specific size and overlay option
        makeVM = vmSize: useOverlay:
          let
            # Import module functions
            usersModule = import ./nixos/modules/users.nix;
            networkingModule = import ./nixos/modules/networking.nix;
            packagesModule = import ./nixos/modules/packages.nix;

            vm-system = nixpkgs.lib.nixosSystem {
              system = system;
              modules = [
                ({ config, pkgs, ... }: {
                  # Allow only Claude Code as unfree package
                  nixpkgs.config.allowUnfreePredicate = pkg: builtins.elem (pkgs.lib.getName pkg) [
                    "claude-code"
                  ];
                })
                usersModule
                networkingModule
                packagesModule
                ({ config, pkgs, ... }: import ./nixos/modules/virtualisation-parameterized.nix { inherit config pkgs vmSize useOverlay; })
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

        # Generate all VM packages automatically (both with and without overlay)
        vmPackages = builtins.listToAttrs (
          builtins.concatMap (vmSize: [
            {
              name = "vm-${vmSize}";
              value = makeVM vmSize false;  # No overlay
            }
            {
              name = "vm-${vmSize}-overlay";
              value = makeVM vmSize true;   # With overlay
            }
          ]) (builtins.attrNames vmSizes.vmSizes)
        );

        # Generate all VM apps automatically (both with and without overlay)
        vmApps = builtins.listToAttrs (
          builtins.concatMap (vmSize: [
            {
              name = "vm-${vmSize}";
              value = {
                type = "app";
                program = "${vmPackages."vm-${vmSize}"}/bin/run-ai-vm-vm";
              };
            }
            {
              name = "vm-${vmSize}-overlay";
              value = {
                type = "app";
                program = "${vmPackages."vm-${vmSize}-overlay"}/bin/run-ai-vm-vm";
              };
            }
          ]) (builtins.attrNames vmSizes.vmSizes)
        );
      in
      {
        # VM packages - all combinations automatically generated
        packages = vmPackages // {
          vm = vmPackages.vm-8gb-2cpu-50gb;  # Default to standard config
        };

        # Apps - all VM apps automatically generated plus utilities
        apps = vmApps // {
          default = {
            type = "app";
            program = "${pkgs.writeShellScript "simple-vm-selector" ''
              set -euo pipefail
              export PATH="${pkgs.lib.makeBinPath [ pkgs.fzf pkgs.nix ]}:$PATH"
              
              # Check if fzf is available
              if ! command -v fzf &> /dev/null; then
                  echo "Error: fzf is not installed."
                  exit 1
              fi

              # Get VM sizes and create simple menu
              vm_sizes=$(nix eval --impure --raw --expr '
                  let vmSizes = import ./nixos/modules/vm-sizes.nix;
                  in builtins.concatStringsSep "\n" (builtins.attrNames vmSizes.vmSizes)
              ')

              # Show simple fzf menu for VM size
              selected_vm=$(echo "$vm_sizes" | sort -V | fzf --prompt="Select VM size: " --height=40%)

              # Exit if user cancelled
              if [[ -z "$selected_vm" ]]; then
                  echo "Cancelled."
                  exit 0
              fi

              # Show second fzf menu for overlay filesystem
              overlay_options="No overlay (faster startup, changes persist)
With overlay (slower startup, clean state each boot)"
              
              selected_overlay=$(echo "$overlay_options" | fzf --prompt="Nix store overlay: " --height=20%)

              # Exit if user cancelled
              if [[ -z "$selected_overlay" ]]; then
                  echo "Cancelled."
                  exit 0
              fi

              # Determine which app to run
              if [[ "$selected_overlay" == *"With overlay"* ]]; then
                  app_name="vm-$selected_vm-overlay"
                  overlay_status="enabled"
              else
                  app_name="vm-$selected_vm"
                  overlay_status="disabled"
              fi

              # Run selected VM
              echo "Starting VM: $selected_vm with overlay: $overlay_status"
              exec nix run ".#$app_name"
            ''}";
          };
          
          # Add convenience app for default VM
          vm = {
            type = "app";
            program = "${self.packages.${system}.vm}/bin/run-ai-vm-vm";
          };
        };

        # Development shell for working with the flake
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            nixos-rebuild
            qemu
            qemu_kvm
            fzf
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
