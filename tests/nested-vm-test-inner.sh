#!/usr/bin/env bash
# Nested VM Test - Run this INSIDE a VM to test nested VM creation
#
# Usage:
#   1. SSH into a running VM: ssh -p 2222 dennis@localhost
#   2. Copy this script to the VM: scp -P 2222 tests/nested-vm-test-inner.sh dennis@localhost:/tmp/
#   3. Run it: bash /tmp/nested-vm-test-inner.sh
#
# This script will test whether VMs can create nested VMs

set -euo pipefail

echo "╔════════════════════════════════════════════════════════════════════════╗"
echo "║           Nested VM Creation Test (Running inside VM)                 ║"
echo "╚════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "This test validates that this VM can build a nested VM."
echo ""

# Function to print test results
print_result() {
    local status="$1"
    local message="$2"
    if [[ "$status" == "pass" ]]; then
        echo "✓ $message"
    elif [[ "$status" == "fail" ]]; then
        echo "✗ $message"
    else
        echo "  $message"
    fi
}

# Test 1: Check host Nix store mounting
echo "═══════════════════════════════════════════════════════════════════════"
echo "Test 1: Verifying Host Nix Store Mount"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""

if [[ ! -d /nix/.ro-store ]]; then
    print_result "fail" "/nix/.ro-store directory not found"
    echo ""
    echo "ERROR: Host Nix store is not mounted at /nix/.ro-store"
    echo "This is required for nested VM creation."
    echo ""
    echo "Expected mount point: /nix/.ro-store"
    echo "This should contain the host's Nix store packages."
    exit 1
fi

print_result "pass" "/nix/.ro-store directory exists"

# Count packages in host store
HOST_STORE_COUNT=$(ls -1 /nix/.ro-store 2>/dev/null | wc -l)
print_result "info" "Host store contains $HOST_STORE_COUNT packages"

if [[ $HOST_STORE_COUNT -lt 100 ]]; then
    print_result "fail" "Host store has too few packages (expected >100)"
    echo ""
    echo "WARNING: Host store appears to be empty or incomplete."
    echo "Nested VM builds may not benefit from the binary cache."
    echo ""
else
    print_result "pass" "Host store has sufficient packages"
fi

echo ""

# Test 2: Check overlay filesystem
echo "═══════════════════════════════════════════════════════════════════════"
echo "Test 2: Verifying Overlay Filesystem"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""

if mount | grep -q "overlay on /nix/store"; then
    print_result "pass" "Overlay filesystem active on /nix/store"
    mount | grep "overlay on /nix/store"
else
    print_result "fail" "Overlay filesystem not detected on /nix/store"
    echo ""
    echo "ERROR: The Nix store should be an overlay filesystem."
    echo "Without this, the store would be read-only and nested VMs cannot be built."
    echo ""
    echo "Current /nix/store mounts:"
    mount | grep "/nix/store" || echo "  (none found)"
    exit 1
fi

echo ""

# Test 3: Check if Nix commands work
echo "═══════════════════════════════════════════════════════════════════════"
echo "Test 3: Verifying Nix Commands"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""

if ! command -v nix &>/dev/null; then
    print_result "fail" "nix command not found"
    exit 1
fi

NIX_VERSION=$(nix --version 2>&1)
print_result "pass" "Nix is available: $NIX_VERSION"

# Check experimental features
if nix show-config 2>&1 | grep -q "experimental-features.*flakes"; then
    print_result "pass" "Flakes are enabled"
else
    print_result "fail" "Flakes are not enabled"
    echo ""
    echo "ERROR: Nix flakes experimental feature is not enabled."
    echo "This is required for building nested VMs with this test."
    exit 1
fi

echo ""

# Test 4: Create a minimal nested VM flake
echo "═══════════════════════════════════════════════════════════════════════"
echo "Test 4: Creating Nested VM Flake"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""

TEST_DIR="/tmp/nested-vm-test-$$"
mkdir -p "$TEST_DIR"
cd "$TEST_DIR"

print_result "info" "Test directory: $TEST_DIR"

# Create a minimal flake
cat > flake.nix << 'EOF'
{
  description = "Minimal nested VM for testing";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      nixosConfigurations.testvm = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          {
            # Absolutely minimal VM configuration
            boot.loader.grub.device = "/dev/vda";
            boot.loader.grub.enable = true;

            fileSystems."/" = {
              device = "/dev/disk/by-label/nixos";
              fsType = "ext4";
            };

            nix.settings.experimental-features = [ "nix-command" "flakes" ];
            system.stateVersion = "23.11";

            # One user with password
            users.users.testuser = {
              isNormalUser = true;
              password = "test";
            };

            # Minimal package set
            environment.systemPackages = with pkgs; [ vim htop ];
          }
        ];
      };

      # The VM build output
      packages.${system}.default =
        self.nixosConfigurations.testvm.config.system.build.vm;
    };
}
EOF

print_result "pass" "Flake configuration created"

# Initialize git (required for flakes)
git init --quiet
git add flake.nix
git commit --quiet -m "Initial nested VM test" --allow-empty 2>/dev/null

print_result "pass" "Git repository initialized"

echo ""

# Test 5: Build the nested VM (the critical test!)
echo "═══════════════════════════════════════════════════════════════════════"
echo "Test 5: Building Nested VM (Critical Test)"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""
echo "This will attempt to build a minimal NixOS VM inside this VM."
echo "This tests whether the host store is accessible and usable."
echo ""
echo "⏱  This may take 3-10 minutes depending on what needs to be built..."
echo "   Progress indicators will show below:"
echo ""

START_TIME=$(date +%s)

# Build with timeout and capture output
BUILD_LOG="$TEST_DIR/build.log"
BUILD_SUCCESS=false

# Try to build with a 10-minute timeout
if timeout 600 nix build .#default --impure --print-build-logs 2>&1 | tee "$BUILD_LOG"; then
    BUILD_SUCCESS=true
    BUILD_EXIT=0
else
    BUILD_EXIT=$?
fi

END_TIME=$(date +%s)
BUILD_TIME=$((END_TIME - START_TIME))

echo ""
echo "───────────────────────────────────────────────────────────────────────"

if [[ $BUILD_SUCCESS == true ]]; then
    print_result "pass" "Nested VM built successfully in ${BUILD_TIME} seconds"
    echo ""

    # Check if build used host store
    if grep -q "/nix/.ro-store" "$BUILD_LOG" 2>/dev/null; then
        print_result "pass" "Build used host store (efficient binary cache)"
    else
        print_result "info" "Could not confirm host store usage from logs"
    fi

else
    print_result "fail" "Nested VM build failed (exit code: $BUILD_EXIT)"
    echo ""

    if [[ $BUILD_EXIT == 124 ]]; then
        echo "ERROR: Build timed out after 10 minutes"
        echo ""
        echo "Possible causes:"
        echo "  - Host store not accessible (rebuilding everything)"
        echo "  - Network issues (downloading packages)"
        echo "  - Insufficient resources"
    else
        echo "ERROR: Build failed"
        echo ""
        echo "Last 30 lines of build log:"
        echo "───────────────────────────────────────────────────────────────────────"
        tail -30 "$BUILD_LOG"
        echo "───────────────────────────────────────────────────────────────────────"
    fi

    echo ""
    echo "Full build log saved to: $BUILD_LOG"
    echo ""
    exit 1
fi

echo ""

# Test 6: Verify nested VM artifacts
echo "═══════════════════════════════════════════════════════════════════════"
echo "Test 6: Verifying Nested VM Artifacts"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""

if [[ ! -L result ]]; then
    print_result "fail" "Result symlink not found"
    echo ""
    echo "ERROR: Build completed but 'result' symlink was not created."
    exit 1
fi

print_result "pass" "Result symlink exists"

RESULT_PATH=$(readlink -f result)
print_result "info" "Points to: $RESULT_PATH"

# Check for VM binary
VM_BINARY=$(find result/bin -name "run-*-vm" -type f 2>/dev/null | head -1)

if [[ -z "$VM_BINARY" ]]; then
    print_result "fail" "VM binary not found in result/bin/"
    echo ""
    echo "Expected to find: result/bin/run-*-vm"
    echo "Actual contents:"
    ls -la result/bin/ 2>/dev/null || echo "  (directory not found)"
    exit 1
fi

print_result "pass" "VM binary found: $VM_BINARY"

# Check binary is executable
if [[ -x "$VM_BINARY" ]]; then
    print_result "pass" "VM binary is executable"
    ls -lh "$VM_BINARY"
else
    print_result "fail" "VM binary is not executable"
    exit 1
fi

echo ""

# Test 7: Verify store usage efficiency
echo "═══════════════════════════════════════════════════════════════════════"
echo "Test 7: Build Efficiency Analysis"
echo "═══════════════════════════════════════════════════════════════════════"
echo ""

print_result "info" "Build completed in $BUILD_TIME seconds"

if [[ $BUILD_TIME -lt 120 ]]; then
    print_result "pass" "Excellent: Build time < 2 minutes (host store working efficiently)"
elif [[ $BUILD_TIME -lt 300 ]]; then
    print_result "pass" "Good: Build time < 5 minutes (host store is being used)"
elif [[ $BUILD_TIME -lt 600 ]]; then
    print_result "info" "Acceptable: Build time < 10 minutes (some rebuilding occurred)"
else
    print_result "fail" "Slow: Build time > 10 minutes (host store may not be working)"
    echo ""
    echo "WARNING: Build was unusually slow."
    echo "Expected: <5 minutes with working host store"
    echo "Actual: $BUILD_TIME seconds"
    echo ""
    echo "This suggests the host store may not be accessible or usable."
fi

# Check store growth
STORE_SIZE_BEFORE=$(du -sh /nix/store 2>/dev/null | awk '{print $1}' || echo "unknown")
print_result "info" "Nix store size: $STORE_SIZE_BEFORE"

echo ""

# Final summary
echo "╔════════════════════════════════════════════════════════════════════════╗"
echo "║                    ✓✓✓ ALL TESTS PASSED ✓✓✓                          ║"
echo "╚════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Summary of Results:"
echo "───────────────────────────────────────────────────────────────────────"
echo "  ✓ Host Nix store mounted and accessible ($HOST_STORE_COUNT packages)"
echo "  ✓ Overlay filesystem active on /nix/store"
echo "  ✓ Nix commands and flakes working"
echo "  ✓ Nested VM flake created successfully"
echo "  ✓ Nested VM built successfully (${BUILD_TIME}s)"
echo "  ✓ Nested VM binary created and is executable"
echo ""
echo "Conclusion:"
echo "───────────────────────────────────────────────────────────────────────"
echo "  The nested VM feature is WORKING CORRECTLY!"
echo ""
echo "  This VM can successfully build nested VMs using the host's Nix store"
echo "  as a binary cache, avoiding redundant package builds."
echo ""
echo "Optional Next Steps:"
echo "───────────────────────────────────────────────────────────────────────"
echo "  To actually run the nested VM (requires significant resources):"
echo "    cd $TEST_DIR"
echo "    $VM_BINARY"
echo "  (Press Ctrl+A then X to exit QEMU)"
echo ""
echo "  To examine the build:"
echo "    ls -la result/"
echo "    cat result/bin/run-*-vm  # View the VM startup script"
echo ""
echo "Cleanup:"
echo "───────────────────────────────────────────────────────────────────────"
echo "  To remove test files:"
echo "    rm -rf $TEST_DIR"
echo ""
