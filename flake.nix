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
          ramStr: cpuStr: storageStr: useOverlay: sharedFoldersRW: sharedFoldersRO: vmName: enableAudio:
          let
            memorySize = parseSize ramStr;
            cores = parseSize cpuStr;
            diskSize = parseSize storageStr;

            # Import module functions
            usersModule = import ./nixos/modules/users.nix;
            networkingModule = import ./nixos/modules/networking.nix;
            packagesModule = import ./nixos/modules/packages.nix;

            vm-system = nixpkgs.lib.nixosSystem {
              system = system;
              modules = [
                (
                  { config, pkgs, ... }:
                  {
                    # Allow only Claude Code as unfree package
                    nixpkgs.config.allowUnfreePredicate =
                      pkg:
                      builtins.elem (pkgs.lib.getName pkg) [
                        "claude-code"
                      ];
                  }
                )
                usersModule
                networkingModule
                packagesModule
                (
                  { config, pkgs, ... }:
                  import ./nixos/modules/virtualisation-parameterized.nix {
                    inherit
                      config
                      pkgs
                      memorySize
                      cores
                      diskSize
                      useOverlay
                      sharedFoldersRW
                      sharedFoldersRO
                      vmName
                      enableAudio
                      ;
                  }
                )
                (
                  { config, pkgs, ... }:
                  {
                    # Basic VM configuration
                    boot.loader.grub.enable = true;
                    boot.loader.grub.device = "/dev/vda";

                    # Enable flakes
                    nix.settings.experimental-features = [
                      "nix-command"
                      "flakes"
                    ];

                    # System version
                    system.stateVersion = "23.11";
                  }
                )
              ];
            };
          in
          vm-system.config.system.build.vm;

      in
      {
        # VM packages - only a default example
        packages = {
          vm = makeVM "8gb" "2cpu" "50gb" false [ ] [ ] "ai-vm" false; # Default example config (no audio)
        };

        # Library functions for creating custom VMs
        lib = {
          makeCustomVM =
            ram: cpu: storage: overlay: sharedRW: sharedRO: vmName: enableAudio:
            makeVM "${toString ram}gb" "${toString cpu}cpu" "${toString storage}gb" overlay sharedRW sharedRO
              vmName enableAudio;
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
          unit-test = import ./tests/unit.nix { inherit pkgs; };
        };
      }
    );
}
