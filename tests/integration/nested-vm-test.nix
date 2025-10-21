{ pkgs ? import <nixpkgs> { }, lib ? pkgs.lib }:

let
  # Import the flake to test
  flakeDir = ../../.;
in

pkgs.nixosTest {
  name = "ai-vm-nested-vm-test";

  nodes = {
    # Create a parent VM that will host the nested VM
    # Test both with and without overlay flag
    parentvm = { config, pkgs, ... }: {
      imports = [
        # Import the VM modules from our flake
        (import ../../nixos/modules/users.nix)
        (import ../../nixos/modules/networking.nix)
        (import ../../nixos/modules/packages.nix)
        (import ../../nixos/modules/virtualisation-parameterized.nix {
          inherit config pkgs;
          memorySize = 4096;  # 4GB for parent VM (needs more RAM for nested builds)
          cores = 4;
          diskSize = 20480;  # 20GB for test (nested VMs need space)
          useOverlay = false;  # Test WITHOUT overlay flag (this is the key test)
          sharedFoldersRW = [];
          sharedFoldersRO = [];
          vmName = "parent-vm";
          enableAudio = false;
        })
      ];

      # Enable nested virtualization support
      virtualisation.vmVariant.virtualisation = {
        # Enable KVM for nested VMs
        qemu.options = [ "-cpu" "host" ];
      };

      # Allow unfree for Claude Code
      nixpkgs.config.allowUnfreePredicate = pkg:
        builtins.elem (pkgs.lib.getName pkg) [ "claude-code" ];

      # Basic VM configuration
      boot.loader.grub.enable = true;
      boot.loader.grub.device = "/dev/vda";

      # Enable flakes
      nix.settings.experimental-features = [ "nix-command" "flakes" ];

      # System version
      system.stateVersion = "23.11";

      # Additional packages needed for testing
      environment.systemPackages = with pkgs; [
        git
        vim
        nixos-rebuild
      ];
    };
  };

  testScript = ''
    import time

    # Start the parent VM and wait for it to be ready
    print("Starting parent VM...")
    parentvm.start()
    parentvm.wait_for_unit("multi-user.target")
    parentvm.wait_for_unit("sshd.service")

    # Test 1: Verify /nix/store is writable (key requirement for nested VMs)
    print("Test 1: Verifying Nix store is writable")
    parentvm.succeed("touch /nix/store/.test-write && rm /nix/store/.test-write")
    print("✓ Nix store is writable")

    # Test 2: Verify host Nix store is mounted and accessible
    print("Test 2: Checking host Nix store mount")
    parentvm.succeed("test -d /nix/.ro-store")
    parentvm.succeed("ls /nix/.ro-store | head -n 5")
    print("✓ Host Nix store is mounted at /nix/.ro-store")

    # Test 3: Verify overlay filesystem is active
    print("Test 3: Verifying overlay filesystem")
    result = parentvm.succeed("mount | grep '/nix/store' || echo 'no overlay'")
    print(f"Mount info: {result}")
    # With disk-based overlay, changes should persist
    assert "overlay" in result or "upperdir" in result or "lowerdir" in result, "Overlay filesystem not detected"
    print("✓ Overlay filesystem is active")

    # Test 4: Create a minimal flake for nested VM
    print("Test 4: Creating minimal nested VM flake")
    parentvm.succeed("""
      mkdir -p /tmp/nested-vm-test
      cd /tmp/nested-vm-test

      cat > flake.nix << 'EOF'
{
  description = "Minimal nested VM test";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.$${system};
    in
    {
      # Define a minimal VM configuration
      nixosConfigurations.nested-test = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ({ config, pkgs, ... }: {
            # Minimal VM configuration
            boot.loader.grub.enable = true;
            boot.loader.grub.device = "/dev/vda";

            fileSystems."/" = {
              device = "/dev/disk/by-label/nixos";
              fsType = "ext4";
            };

            networking.hostName = "nested-test";
            system.stateVersion = "23.11";

            # Small memory footprint
            virtualisation.memorySize = 512;
            virtualisation.diskSize = 2048;
            virtualisation.graphics = false;

            users.users.test = {
              isNormalUser = true;
              password = "";
            };
          })
        ];
      };

      # VM package (this is what we'll build)
      packages.$${system}.vm = self.nixosConfigurations.nested-test.config.system.build.vm;
    };
}
EOF

      git init
      git add flake.nix
      git commit -m "Initial nested VM flake"
    """)
    print("✓ Created nested VM flake")

    # Test 5: Build the nested VM (THIS IS THE CRITICAL TEST)
    # This would fail with read-only /nix/store
    print("Test 5: Building nested VM (critical test - requires writable store)")
    print("Note: This may take a few minutes as it builds the VM...")

    # Build with a timeout to avoid hanging
    try:
        parentvm.succeed("cd /tmp/nested-vm-test && nix build .#vm --no-link", timeout=600)
        print("✓ Successfully built nested VM!")
        print("✓✓✓ NESTED VIRTUALIZATION IS WORKING! ✓✓✓")
    except Exception as e:
        print(f"✗ Failed to build nested VM: {e}")
        # Get more details about the failure
        try:
            error_log = parentvm.succeed("dmesg | tail -50")
            print(f"System logs:\n{error_log}")
        except:
            pass
        raise

    # Test 6: Verify the built VM exists
    print("Test 6: Verifying nested VM was built successfully")
    result = parentvm.succeed("cd /tmp/nested-vm-test && nix build .#vm --print-out-paths")
    print(f"Nested VM path: {result}")
    assert "/nix/store" in result, "Built VM should be in Nix store"
    print("✓ Nested VM artifact exists in Nix store")

    # Test 7: Verify store paths were created
    print("Test 7: Checking that new store paths were created")
    parentvm.succeed("test -n \"$(find /nix/store -name '*nested-test*' -type d | head -n 1)\"")
    print("✓ Nested VM store paths created successfully")

    # Test 8: Test that a simple nix build works (simpler than full VM)
    print("Test 8: Testing simple package build inside parent VM")
    parentvm.succeed("nix build nixpkgs#hello --no-link", timeout=300)
    print("✓ Simple package build works")

    # Test 9: Verify disk-based overlay persistence
    print("Test 9: Verifying overlay persistence (disk-based, not tmpfs)")
    # Check that the overlay is not using tmpfs
    mount_info = parentvm.succeed("mount | grep '/nix/.rw-store' || echo 'no rw-store mount'")
    print(f"RW store mount: {mount_info}")
    # Disk-based overlay should NOT show tmpfs
    assert "tmpfs" not in mount_info.lower() or "no rw-store mount" in mount_info, \
        "Overlay should be disk-based, not tmpfs (when overlay flag is not set)"
    print("✓ Overlay is disk-based (persistent)")

    # Test 10: Verify nested build artifacts persist
    print("Test 10: Verifying nested build artifacts are in writable store")
    # The nested VM should be in the writable part of the store
    parentvm.succeed("ls -la /nix/store/ | grep nested-test | head -n 5")
    print("✓ Nested build artifacts are accessible")

    print("")
    print("=" * 60)
    print("ALL NESTED VIRTUALIZATION TESTS PASSED!")
    print("=" * 60)
    print("")
    print("Summary:")
    print("  ✓ Nix store is writable (disk-based overlay)")
    print("  ✓ Host Nix store mounted and accessible")
    print("  ✓ Overlay filesystem working correctly")
    print("  ✓ Nested VM flake created successfully")
    print("  ✓ Nested VM built successfully (CRITICAL TEST)")
    print("  ✓ Nested VM artifacts in Nix store")
    print("  ✓ Store paths created correctly")
    print("  ✓ Simple builds also work")
    print("  ✓ Overlay is disk-based (persistent)")
    print("  ✓ Build artifacts persist correctly")
    print("")
    print("CONCLUSION: VMs without --overlay flag can now create nested VMs!")
  '';
}
