#!/usr/bin/env python3

import subprocess
import sys

def main():
    """Test that /etc/nixos configuration files are properly installed in the VM"""

    # Test configuration files exist and have expected content
    tests = [
        # Test flake.nix exists and contains VM name
        "test -f /etc/nixos/flake.nix",
        "grep -q 'AI VM NixOS Configuration' /etc/nixos/flake.nix",
        
        # Test configuration.nix exists and has VM name
        "test -f /etc/nixos/configuration.nix",
        "grep -q 'VM Configuration' /etc/nixos/configuration.nix",
        
        # Test hardware-configuration.nix exists
        "test -f /etc/nixos/hardware-configuration.nix",
        "grep -q 'Hardware configuration' /etc/nixos/hardware-configuration.nix",
        
        # Test README exists
        "test -f /etc/nixos/README.md",
        "grep -q 'Quick Commands' /etc/nixos/README.md",
        
        # Test flake.nix is properly formatted Nix
        "nix eval --file /etc/nixos/flake.nix --apply 'x: x.description' --json",
        
        # Test that the flake can be checked (syntax validation)
        "cd /etc/nixos && nix flake check --show-trace"
    ]

    print("=== Testing /etc/nixos configuration files ===")
    
    for i, test in enumerate(tests, 1):
        print(f"Test {i}: {test}")
        try:
            result = subprocess.run(
                test, 
                shell=True, 
                capture_output=True, 
                text=True, 
                timeout=30
            )
            if result.returncode == 0:
                print(f"✓ Test {i} passed")
            else:
                print(f"✗ Test {i} failed")
                print(f"  stdout: {result.stdout}")
                print(f"  stderr: {result.stderr}")
                return 1
        except subprocess.TimeoutExpired:
            print(f"✗ Test {i} timed out")
            return 1
        except Exception as e:
            print(f"✗ Test {i} error: {e}")
            return 1

    print("\n=== VM Configuration Information ===")
    
    # Show VM specs from configuration
    try:
        result = subprocess.run(
            "grep -E '(RAM|CPU|Disk|Audio|Overlay):' /etc/nixos/configuration.nix",
            shell=True,
            capture_output=True,
            text=True
        )
        if result.returncode == 0:
            print("VM Specifications found in configuration:")
            for line in result.stdout.strip().split('\n'):
                print(f"  {line.strip()}")
    except:
        pass

    print("\n✓ All /etc/nixos configuration tests passed!")
    return 0

if __name__ == "__main__":
    sys.exit(main())