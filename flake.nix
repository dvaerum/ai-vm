{
  description = "VM environment for running Claude Code";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # Convert size strings to actual values
        parseSize =
          size:
          let
            # Extract number and unit
            match = builtins.match "([0-9]+)(gb|cpu)" size;
          in
          if match != null then
            let
              number = builtins.fromJSON (builtins.elemAt match 0);
              unit = builtins.elemAt match 1;
            in
            if unit == "gb" then
              number * 1024 # Convert GB to MB
            else if unit == "cpu" then
              number
            else
              throw "Unknown unit: ${unit}"
          else
            throw "Invalid size format: ${size}";

        # Function to create VM with specific parameters
        makeVM =
          ramStr: cpuStr: storageStr: useOverlay: sharedFoldersRW: sharedFoldersRO: vmName: enableAudio: enableDesktop: portMappings: resolution:
          let
            memorySize = parseSize ramStr;
            cores = parseSize cpuStr;
            diskSize = parseSize storageStr;

            vm-system = nixpkgs.lib.nixosSystem {
              system = system;
              modules = [
                # Pure modules (no parameters)
                ./nixos/modules/users.nix
                ./nixos/modules/networking.nix
                ./nixos/modules/packages.nix
                ./nixos/modules/configuration.nix

                # Parameterized VM module (includes templates & activation)
                (
                  { config, pkgs, lib, ... }:
                  import ./nixos/modules/virtualisation-parameterized.nix {
                    inherit config pkgs lib;
                    inherit memorySize cores diskSize useOverlay;
                    inherit sharedFoldersRW sharedFoldersRO vmName enableAudio enableDesktop portMappings resolution;
                    # Pass nixpkgs info for flake.lock generation
                    nixpkgsRev = nixpkgs.rev;
                    nixpkgsNarHash = nixpkgs.narHash;
                  }
                )

                # Host-side VM build: QEMU boots directly, no grub needed
                # Note: In-VM uses grub (see vm-info.nix template)
                {
                  boot.loader.grub.enable = false;
                  boot.loader.grub.device = "nodev";
                }
              ];
            };
          in
          vm-system.config.system.build.vm;

        # Default port mappings: SSH + dev servers
        defaultPorts = [
          { host = 2222; guest = 22; }
          { host = 3001; guest = 3001; }
          { host = 9080; guest = 9080; }
        ];

      in
      {
        # VM packages - only a default example
        packages = {
          vm = makeVM "8gb" "2cpu" "50gb" false [ ] [ ] "ai-vm" false false defaultPorts null;
        };

        # Library functions for creating custom VMs
        lib = {
          makeCustomVM =
            ram: cpu: storage: overlay: sharedRW: sharedRO: vmName: enableAudio: enableDesktop: portMappings: resolution:
            makeVM "${toString ram}gb" "${toString cpu}cpu" "${toString storage}gb" overlay sharedRW sharedRO
              vmName enableAudio enableDesktop portMappings resolution;
        };

        # Apps - just the vm-selector and default VM
        apps = {
          default = {
            type = "app";
            program = "${pkgs.writeShellScript "vm-selector" ''
              set -euo pipefail
              export PATH="${
                pkgs.lib.makeBinPath [
                  pkgs.fzf
                  pkgs.nix
                ]
              }:$PATH"

              # Pass the flake store path to the script for building VMs
              export NIX_FLAKE_STORE_PATH="${self}"

              ${builtins.readFile ./vm-selector.sh}
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
            echo "Run 'nix build .#checks.${system}.integration-test' to run integration tests"
          '';
        };

        # Tests
        checks = {
          integration-test = import ./tests/integration { inherit pkgs; };
          nixos-rebuild-test = import ./tests/integration/nixos-rebuild-test.nix { inherit pkgs; };
          nested-vm-test = import ./tests/integration/nested-vm-test.nix { inherit pkgs; };
          start-script-test = import ./tests/integration/start-script-test.nix { inherit pkgs; };
          unit-test = import ./tests/unit.nix { inherit pkgs; };
        };
      }
    );
}
