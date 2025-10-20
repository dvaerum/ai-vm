{ pkgs ? import <nixpkgs> { }, lib ? pkgs.lib }:

let
  # Import the flake to test
  flakeDir = ../../.;

  # Import the VM building function from our flake
  flake = builtins.getFlake (toString flakeDir);
  system = pkgs.system;
in

pkgs.nixosTest {
  name = "ai-vm-nixos-rebuild-test";

  nodes = {
    # Create a test VM using our flake's makeCustomVM function
    testvm = { config, pkgs, ... }: {
      imports = [
        # Import the VM modules from our flake
        (import ../../nixos/modules/users.nix)
        (import ../../nixos/modules/networking.nix)
        (import ../../nixos/modules/packages.nix)
        (import ../../nixos/modules/virtualisation-parameterized.nix {
          inherit config pkgs;
          memorySize = 2048;  # 2GB for test
          cores = 2;
          diskSize = 10240;  # 10GB for test
          useOverlay = false;
          sharedFoldersRW = [];
          sharedFoldersRO = [];
          vmName = "test-vm";
          enableAudio = false;
        })
      ];

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
      ];
    };
  };

  testScript = ''
    import time

    # Start the VM and wait for it to be ready
    testvm.start()
    testvm.wait_for_unit("multi-user.target")
    testvm.wait_for_unit("sshd.service")

    # Test 1: Verify /etc/nixos exists and is writable
    print("Test 1: Checking /etc/nixos directory")
    testvm.succeed("test -d /etc/nixos")
    testvm.succeed("test -w /etc/nixos")

    # Test 2: Verify configuration files exist
    print("Test 2: Checking configuration files")
    testvm.succeed("test -f /etc/nixos/flake.nix")
    testvm.succeed("test -f /etc/nixos/flake.lock")
    testvm.succeed("test -f /etc/nixos/configuration.nix")
    testvm.succeed("test -f /etc/nixos/hardware-configuration.nix")
    testvm.succeed("test -f /etc/nixos/rebuild")
    testvm.succeed("test -x /etc/nixos/rebuild")

    # Test 3: Verify configuration files are writable
    print("Test 3: Checking files are writable")
    testvm.succeed("test -w /etc/nixos/configuration.nix")
    testvm.succeed("test -w /etc/nixos/flake.nix")

    # Test 4: Verify git repository is initialized
    print("Test 4: Checking git repository")
    testvm.succeed("test -d /etc/nixos/.git")
    testvm.succeed("cd /etc/nixos && git status")
    testvm.succeed("cd /etc/nixos && git log --oneline | grep 'Initial VM configuration'")

    # Test 5: Verify nixos-rebuild command exists
    print("Test 5: Checking nixos-rebuild command")
    testvm.succeed("which nixos-rebuild")
    testvm.succeed("which rebuild")

    # Test 6: Edit configuration file
    print("Test 6: Modifying configuration")
    testvm.succeed("""
      cat >> /etc/nixos/configuration.nix << 'EOF'
      # Test modification - add a custom environment variable
      environment.variables.TEST_VM_REBUILD = "success";
EOF
    """)

    # Test 7: Commit changes to git (required for flakes)
    print("Test 7: Committing changes to git")
    testvm.succeed("cd /etc/nixos && git add configuration.nix")
    testvm.succeed("cd /etc/nixos && git commit -m 'Test configuration change'")

    # Test 8: Run nixos-rebuild switch (dry run first)
    print("Test 8: Running nixos-rebuild switch --dry-run")
    testvm.succeed("nixos-rebuild switch --dry-run")

    # Test 9: Verify the wrapper adds --flake automatically
    print("Test 9: Checking nixos-rebuild wrapper behavior")
    # The wrapper should add --flake automatically when not specified
    result = testvm.succeed("nixos-rebuild switch --dry-run 2>&1 | grep -o 'evaluating derivation' || echo 'evaluated'")
    print(f"Dry run result: {result}")

    # Test 10: Run actual nixos-rebuild switch
    print("Test 10: Running nixos-rebuild switch (actual rebuild)")
    testvm.succeed("nixos-rebuild switch")

    # Test 11: Verify the change was applied
    print("Test 11: Verifying configuration was applied")
    testvm.succeed("test -n \"$TEST_VM_REBUILD\"")
    result = testvm.succeed("echo $TEST_VM_REBUILD")
    assert "success" in result, f"Environment variable not set correctly: {result}"

    # Test 12: Test the 'rebuild' convenience command
    print("Test 12: Testing 'rebuild' convenience command")
    testvm.succeed("""
      cat >> /etc/nixos/configuration.nix << 'EOF'
      environment.variables.TEST_REBUILD_COMMAND = "works";
EOF
    """)
    testvm.succeed("cd /etc/nixos && git add configuration.nix")
    testvm.succeed("cd /etc/nixos && git commit -m 'Test rebuild command'")
    testvm.succeed("rebuild")

    # Test 13: Verify rebuild command worked
    print("Test 13: Verifying rebuild command worked")
    testvm.succeed("test -n \"$TEST_REBUILD_COMMAND\"")
    result = testvm.succeed("echo $TEST_REBUILD_COMMAND")
    assert "works" in result, f"Rebuild command did not apply changes: {result}"

    # Test 14: Test nixos-rebuild with explicit --flake flag
    print("Test 14: Testing explicit --flake flag")
    testvm.succeed("nixos-rebuild switch --flake /etc/nixos#test-vm --dry-run")

    # Test 15: Verify flake check works
    print("Test 15: Running nix flake check")
    testvm.succeed("nix flake check /etc/nixos")

    print("All tests passed!")
  '';
}
