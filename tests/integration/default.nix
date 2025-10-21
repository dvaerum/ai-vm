{ pkgs ? import <nixpkgs> { }, lib ? pkgs.lib }:

let
  # Import the flake to test
  flakeDir = ../../.;
in

pkgs.nixosTest {
  name = "ai-vm-integration-test";

  # Test nodes - we use a host system to test the vm-selector script
  nodes = {
    host = { pkgs, ... }: {
      # Enable virtualization for testing VMs within the test
      virtualisation.vmVariant.virtualisation.enableVirtualization = true;

      # Install required tools
      environment.systemPackages = with pkgs; [
        fzf
        qemu
        nix
        git
      ];

      # Enable flakes
      nix.settings.experimental-features = [ "nix-command" "flakes" ];

      # Copy the vm-selector script to the test environment
      environment.etc."vm-selector.sh" = {
        source = ../../vm-selector.sh;
        mode = "0755";
      };

      # Create test directories for shared folder testing
      system.activationScripts.createTestDirs = ''
        mkdir -p /tmp/test-share-rw
        mkdir -p /tmp/test-share-ro
        echo "test content rw" > /tmp/test-share-rw/test.txt
        echo "test content ro" > /tmp/test-share-ro/readonly.txt
        chmod 755 /tmp/test-share-rw /tmp/test-share-ro
      '';

      # Copy flake files for testing
      system.activationScripts.copyFlakeFiles = ''
        mkdir -p /tmp/ai-vm-test

        # Copy files from flake directory, making them writable
        # Using cp -r preserves structure but files from Nix store are read-only
        cp -r ${flakeDir}/* /tmp/ai-vm-test/ 2>/dev/null || true
        cp -r ${flakeDir}/.* /tmp/ai-vm-test/ 2>/dev/null || true

        # Make all copied files writable (they're read-only from Nix store)
        chmod -R u+w /tmp/ai-vm-test

        cd /tmp/ai-vm-test
        chmod +x vm-selector.sh 2>/dev/null || true

        # Ensure flake.lock exists and is writable
        if [[ -f flake.lock ]]; then
          chmod u+w flake.lock
        fi

        # Initialize git repository for custom VM builds
        # This is required for git+file:// flake references
        git init --initial-branch=main
        git config user.name "Test User"
        git config user.email "test@example.com"

        # Add all files to git (required for flakes to work)
        git add -A
        git commit -m "Initial test setup" --allow-empty

        # Tag the commit so we have a stable reference
        git tag -a v1.0.0 -m "Test version"
      '';
    };
  };

  # Test script
  testScript = builtins.readFile ./comprehensive-vm-selector-test.py;
}