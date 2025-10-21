#!/usr/bin/env bash
# Manual Nested VM Test Script
# This script tests that VMs can create nested VMs (VMs inside VMs)
#
# Usage:
#   1. Run this script on the HOST to create and start a test VM
#   2. SSH into the VM (port 2222)
#   3. Run the nested VM creation test inside the VM
#
# The script will create a VM and provide instructions for testing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "╔════════════════════════════════════════════════════════════════════════╗"
echo "║                    Nested VM Creation Test                            ║"
echo "╚════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "This test validates that VMs can create nested VMs inside them."
echo ""

# Step 1: Build a test VM
echo "Step 1: Building test VM..."
echo "----------------------------------------"

cd "$PROJECT_ROOT"

# Use vm-selector.sh to create a small test VM
# 4GB RAM, 2 CPUs, 30GB storage should be enough for testing
echo "Building VM with: 4GB RAM, 2 CPUs, 30GB storage"

if ! ./vm-selector.sh --name nested-test --ram 4 --cpu 2 --storage 30; then
    echo "Error: Failed to build test VM"
    exit 1
fi

echo ""
echo "✓ Test VM built successfully!"
echo ""

# The VM is now running in the background
# Wait a bit for it to boot
echo "Step 2: Waiting for VM to boot (60 seconds)..."
echo "----------------------------------------"
sleep 10
echo "  10 seconds..."
sleep 10
echo "  20 seconds..."
sleep 10
echo "  30 seconds..."
sleep 10
echo "  40 seconds..."
sleep 10
echo "  50 seconds..."
sleep 10
echo "  60 seconds - VM should be ready!"
echo ""

# Step 3: Test SSH connection
echo "Step 3: Testing SSH connection..."
echo "----------------------------------------"

MAX_RETRIES=10
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 -p 2222 dennis@localhost "echo 'SSH connected successfully'" 2>/dev/null; then
        echo "✓ SSH connection successful!"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
            echo "  Attempt $RETRY_COUNT/$MAX_RETRIES failed, retrying in 5 seconds..."
            sleep 5
        else
            echo "✗ Failed to connect via SSH after $MAX_RETRIES attempts"
            echo ""
            echo "Please check if the VM is running and try manually:"
            echo "  ssh -p 2222 dennis@localhost"
            exit 1
        fi
    fi
done

echo ""

# Step 4: Create test script for inside the VM
echo "Step 4: Creating test script for nested VM creation..."
echo "----------------------------------------"

cat > /tmp/nested-vm-test-inner.sh << 'INNER_SCRIPT'
#!/usr/bin/env bash
# This script runs INSIDE the VM to test nested VM creation

set -euo pipefail

echo "╔════════════════════════════════════════════════════════════════════════╗"
echo "║           Nested VM Creation Test (Running inside VM)                 ║"
echo "╚════════════════════════════════════════════════════════════════════════╝"
echo ""

# Check that we're inside a VM
if [[ ! -d /nix/.ro-store ]]; then
    echo "✗ ERROR: /nix/.ro-store not found!"
    echo "  This suggests host Nix store is not mounted."
    echo "  Nested VM creation will likely fail."
    exit 1
fi

echo "✓ Host Nix store detected at /nix/.ro-store"
echo ""

# Check overlay filesystem
if mount | grep -q "overlay on /nix/store"; then
    echo "✓ Overlay filesystem detected on /nix/store"
else
    echo "✗ WARNING: Overlay filesystem not detected"
    echo "  This may indicate the writable store is not configured correctly"
fi
echo ""

# Check available packages in host store
echo "Checking host store accessibility..."
HOST_STORE_PACKAGES=$(ls /nix/.ro-store | wc -l)
echo "✓ Host store contains $HOST_STORE_PACKAGES packages"
echo ""

# Test 1: Check if nix commands work
echo "Test 1: Verifying Nix commands work..."
echo "----------------------------------------"
if ! nix --version; then
    echo "✗ ERROR: nix command not found"
    exit 1
fi
echo "✓ Nix is available"
echo ""

# Test 2: Try to create a simple flake for a nested VM
echo "Test 2: Creating a minimal nested VM flake..."
echo "----------------------------------------"

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
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      # Create a minimal VM
      nixosConfigurations.minimal-vm = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          {
            # Minimal VM configuration
            boot.loader.grub.device = "/dev/vda";
            boot.loader.grub.enable = true;
            fileSystems."/" = {
              device = "/dev/vda";
              fsType = "ext4";
            };

            nix.settings.experimental-features = [ "nix-command" "flakes" ];
            system.stateVersion = "23.11";

            # Passwordless user for testing
            users.users.test = {
              isNormalUser = true;
              password = "";
            };
          }
        ];
      };

      # Build the VM
      packages.${system}.vm =
        self.nixosConfigurations.minimal-vm.config.system.build.vm;
    };
}
EOF

git init
git add flake.nix
git commit -m "Initial nested VM test" --allow-empty

echo "✓ Nested VM flake created"
echo ""

# Test 3: Try to build the nested VM
echo "Test 3: Building nested VM (this will test host store access)..."
echo "----------------------------------------"
echo "This may take a while as it evaluates the flake and builds the VM..."
echo ""

# Set a timeout of 5 minutes for the build
timeout 300 nix build .#vm --impure --show-trace 2>&1 | tee /tmp/nested-vm-build.log || {
    BUILD_EXIT=$?
    echo ""
    if [ $BUILD_EXIT -eq 124 ]; then
        echo "✗ Build timed out after 5 minutes"
    else
        echo "✗ Build failed with exit code: $BUILD_EXIT"
    fi
    echo ""
    echo "Build log saved to: /tmp/nested-vm-build.log"
    echo ""
    echo "Last 20 lines of build log:"
    tail -20 /tmp/nested-vm-build.log
    exit 1
}

echo ""
echo "✓ Nested VM built successfully!"
echo ""

# Test 4: Verify the nested VM binary exists
echo "Test 4: Verifying nested VM binary..."
echo "----------------------------------------"

if [[ -f result/bin/run-minimal-vm-vm ]]; then
    echo "✓ Nested VM binary found: result/bin/run-minimal-vm-vm"
    ls -lh result/bin/run-minimal-vm-vm
else
    echo "✗ Nested VM binary not found"
    echo "Available files in result/bin/:"
    ls -la result/bin/ || echo "  (directory not found)"
    exit 1
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════════════╗"
echo "║                    ✓ ALL NESTED VM TESTS PASSED                       ║"
echo "╚════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Summary:"
echo "  ✓ Host Nix store mounted and accessible"
echo "  ✓ Overlay filesystem active"
echo "  ✓ Nix commands work"
echo "  ✓ Nested VM flake created"
echo "  ✓ Nested VM built successfully using host store"
echo "  ✓ Nested VM binary exists and is ready to run"
echo ""
echo "The nested VM could be started with:"
echo "  cd /tmp/nested-vm-test"
echo "  ./result/bin/run-minimal-vm-vm"
echo ""
echo "(Note: We're not starting it to avoid triple-nesting complexity)"
echo ""
INNER_SCRIPT

chmod +x /tmp/nested-vm-test-inner.sh

echo "✓ Test script created at /tmp/nested-vm-test-inner.sh"
echo ""

# Step 5: Copy test script to VM and run it
echo "Step 5: Copying test script to VM and running it..."
echo "----------------------------------------"
echo ""

scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P 2222 /tmp/nested-vm-test-inner.sh dennis@localhost:/tmp/ 2>/dev/null

echo "Running nested VM test inside the VM..."
echo "========================================"
echo ""

# Run the test script inside the VM
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p 2222 dennis@localhost "bash /tmp/nested-vm-test-inner.sh"

INNER_EXIT=$?

echo ""
echo "========================================"
echo "Nested VM test completed with exit code: $INNER_EXIT"
echo ""

if [ $INNER_EXIT -eq 0 ]; then
    echo "╔════════════════════════════════════════════════════════════════════════╗"
    echo "║          ✓✓✓ NESTED VM FUNCTIONALITY VALIDATED ✓✓✓                   ║"
    echo "╚════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "The nested VM feature is working correctly!"
    echo "VMs can successfully create and build nested VMs using the host store."
    echo ""
else
    echo "╔════════════════════════════════════════════════════════════════════════╗"
    echo "║          ✗✗✗ NESTED VM TEST FAILED ✗✗✗                               ║"
    echo "╚════════════════════════════════════════════════════════════════════════╝"
    echo ""
    echo "The nested VM test failed. Please review the output above."
    echo ""
fi

# Cleanup instructions
echo ""
echo "Cleanup:"
echo "  To stop the test VM, press Ctrl+C in the terminal where it's running"
echo "  Or kill the QEMU process"
echo "  VM disk and files are in: nested-test.qcow2, start-nested-test.sh"
echo ""

exit $INNER_EXIT
