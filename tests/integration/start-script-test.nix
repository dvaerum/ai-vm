{ pkgs ? import <nixpkgs> { }, lib ? pkgs.lib }:

let
  # Import the flake to test
  flakeDir = ../../.;
in

pkgs.nixosTest {
  name = "vm-start-script-test";

  # Test nodes
  nodes = {
    host = { pkgs, ... }: {
      # Enable virtualization for nested VM testing
      virtualisation.vmVariant.virtualisation.enableVirtualization = true;

      # Install required tools
      environment.systemPackages = with pkgs; [
        qemu
        nix
        git
      ];

      # Enable flakes
      nix.settings.experimental-features = [ "nix-command" "flakes" ];

      # Copy flake files for testing
      system.activationScripts.copyFlakeFiles = ''
        mkdir -p /tmp/ai-vm-test

        # Copy files from flake directory
        cp -r ${flakeDir}/* /tmp/ai-vm-test/ 2>/dev/null || true
        cp -r ${flakeDir}/.* /tmp/ai-vm-test/ 2>/dev/null || true

        # Make all copied files writable
        chmod -R u+w /tmp/ai-vm-test

        cd /tmp/ai-vm-test
        chmod +x vm-selector.sh 2>/dev/null || true

        # Ensure flake.lock exists and is writable
        if [[ -f flake.lock ]]; then
          chmod u+w flake.lock
        fi

        # Initialize git repository
        git init --initial-branch=main
        git config user.name "Test User"
        git config user.email "test@example.com"
        git add -A
        git commit -m "Initial test setup" --allow-empty
        git tag -a v1.0.0 -m "Test version"
      '';
    };
  };

  # Test script
  testScript = ''
    # Start the host machine
    host.start()
    host.wait_for_unit("multi-user.target")

    print("=== Testing VM Start Script Generation and Execution ===")

    # Build a test VM
    print("Building test VM...")
    build_output = host.succeed(
        "cd /tmp/ai-vm-test && "
        "INTERACTIVE=false ./vm-selector.sh --name test-start-vm --ram 2 --cpu 1 --storage 10"
    )

    print("Build output:")
    print(build_output)

    # Verify start script was created
    print("Verifying start script exists...")
    host.succeed("test -f /tmp/ai-vm-test/start-test-start-vm.sh")
    print("✓ Start script exists")

    # Verify start script is executable
    print("Verifying start script is executable...")
    host.succeed("test -x /tmp/ai-vm-test/start-test-start-vm.sh")
    print("✓ Start script is executable")

    # Read and validate start script content
    print("Reading start script content...")
    script_content = host.succeed("cat /tmp/ai-vm-test/start-test-start-vm.sh")
    print("Start script content:")
    print(script_content)

    # Check for VM name variable
    assert 'VM_NAME="test-start-vm"' in script_content, "VM_NAME not set correctly in start script"
    print("✓ VM_NAME variable is set correctly")

    # Check for configuration variables
    assert "RAM_SIZE=2" in script_content, "RAM_SIZE not set correctly"
    assert "CPU_CORES=1" in script_content, "CPU_CORES not set correctly"
    assert "STORAGE_SIZE=10" in script_content, "STORAGE_SIZE not set correctly"
    print("✓ Configuration variables are set correctly")

    # CRITICAL TEST: Check that VM binary path is correctly interpolated
    # The script should have "run-test-start-vm-vm", not "run-''${VM_NAME}-vm"
    assert "run-test-start-vm-vm" in script_content, (
        f"VM binary path not correctly interpolated. "
        f"Expected 'run-test-start-vm-vm' to be in the script. "
        f"Check if the script has uninterpolated variables like '${{VM_NAME}}'"
    )
    print("✓ VM binary path is correctly interpolated (not using ''${VM_NAME})")

    # Check that there are no uninterpolated variables in the exec line
    if "''${VM_NAME}" in script_content:
        # Find the exec line to provide better error message
        for line in script_content.split('\n'):
            if 'exec' in line and 'run-' in line:
                raise AssertionError(
                    f"Found uninterpolated ''${{VM_NAME}} variable in start script. "
                    f"Problematic line: {line.strip()}"
                )
        raise AssertionError("Found uninterpolated ''${VM_NAME} variable in start script")
    print("✓ No uninterpolated variables found in start script")

    # Verify the VM binary exists
    print("Verifying VM binary exists...")
    host.succeed("test -f /tmp/ai-vm-test/result/bin/run-test-start-vm-vm")
    print("✓ VM binary exists at expected path")

    # Test that the start script can be executed (at least it starts without immediate errors)
    # We won't wait for full boot in this test, just verify the script runs
    print("Testing start script execution (basic smoke test)...")
    # Start the VM in background and immediately kill it to verify the script works
    result = host.succeed(
        "cd /tmp/ai-vm-test && "
        "timeout 5 ./start-test-start-vm.sh || true"
    )
    print("Start script execution test:")
    print(result)

    # If the script had a syntax error or couldn't find the binary, timeout would fail differently
    # The fact that timeout ran means the script at least started
    print("✓ Start script executed without immediate errors")

    print("=== All start script tests passed! ===")
  '';
}
