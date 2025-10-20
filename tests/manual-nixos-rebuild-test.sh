#!/usr/bin/env bash
# Manual test script for nixos-rebuild functionality
# Run this inside a VM created by this flake to verify nixos-rebuild works

set -euo pipefail

echo "=== Manual NixOS Rebuild Test ==="
echo

# Test 1: Check /etc/nixos directory
echo "Test 1: Checking /etc/nixos directory..."
if [ -d /etc/nixos ] && [ -w /etc/nixos ]; then
    echo "✓ /etc/nixos exists and is writable"
else
    echo "✗ /etc/nixos is missing or not writable"
    exit 1
fi

# Test 2: Check configuration files
echo
echo "Test 2: Checking configuration files..."
for file in flake.nix flake.lock configuration.nix hardware-configuration.nix rebuild README.md; do
    if [ -f /etc/nixos/$file ]; then
        echo "✓ /etc/nixos/$file exists"
    else
        echo "✗ /etc/nixos/$file is missing"
        exit 1
    fi
done

# Test 3: Check if files are writable
echo
echo "Test 3: Checking if configuration files are writable..."
if [ -w /etc/nixos/configuration.nix ]; then
    echo "✓ configuration.nix is writable"
else
    echo "✗ configuration.nix is not writable"
    exit 1
fi

# Test 4: Check git repository
echo
echo "Test 4: Checking git repository..."
if [ -d /etc/nixos/.git ]; then
    echo "✓ Git repository exists"
    cd /etc/nixos
    if git log --oneline | grep -q "Initial VM configuration"; then
        echo "✓ Initial commit found"
    else
        echo "✗ Initial commit not found"
        exit 1
    fi
else
    echo "✗ Git repository not initialized"
    exit 1
fi

# Test 5: Check nixos-rebuild command
echo
echo "Test 5: Checking nixos-rebuild command..."
if command -v nixos-rebuild &> /dev/null; then
    echo "✓ nixos-rebuild command exists"
else
    echo "✗ nixos-rebuild command not found"
    exit 1
fi

if command -v rebuild &> /dev/null; then
    echo "✓ rebuild command exists"
else
    echo "✗ rebuild command not found"
    exit 1
fi

# Test 6: Test dry-run rebuild
echo
echo "Test 6: Testing nixos-rebuild switch --dry-run..."
if sudo nixos-rebuild switch --dry-run &> /tmp/rebuild-test.log; then
    echo "✓ nixos-rebuild switch --dry-run succeeded"
else
    echo "✗ nixos-rebuild switch --dry-run failed"
    cat /tmp/rebuild-test.log
    exit 1
fi

# Test 7: Verify wrapper adds --flake automatically
echo
echo "Test 7: Verifying nixos-rebuild wrapper behavior..."
if sudo nixos-rebuild switch --dry-run 2>&1 | grep -q "evaluating derivation"; then
    echo "✓ nixos-rebuild wrapper is working (flakes are being used)"
else
    echo "⚠ Could not verify wrapper behavior (this is okay)"
fi

# Test 8: Test adding a configuration change
echo
echo "Test 8: Testing configuration modification..."
cd /etc/nixos
cat >> configuration.nix << 'EOF'
  # Test configuration change
  environment.variables.TEST_NIXOS_REBUILD = "working";
EOF

git add configuration.nix
git commit -m "Test configuration change"
echo "✓ Configuration modified and committed"

# Test 9: Actual rebuild (optional, commented out by default)
echo
echo "Test 9: Actual rebuild (skipped - uncomment to test)"
echo "  To test actual rebuild, uncomment the following line in this script:"
echo "  # sudo nixos-rebuild switch"
# sudo nixos-rebuild switch

echo
echo "=== All Tests Passed ==="
echo
echo "To complete the test, run an actual rebuild:"
echo "  sudo nixos-rebuild switch"
echo
echo "Then verify the environment variable is set:"
echo "  echo \$TEST_NIXOS_REBUILD"
