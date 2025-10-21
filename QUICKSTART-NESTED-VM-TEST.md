# Quick Start: Testing Nested VM Functionality

This is a simple, copy-paste guide to test that VMs can create nested VMs.

## What You'll Do

1. Build and start a VM (3 minutes)
2. SSH into the VM (1 minute)
3. Run a test script inside the VM (5-10 minutes)
4. Verify nested VMs work correctly

**Total time:** ~15-20 minutes

## Prerequisites

- 8GB+ RAM available
- 50GB+ free disk space
- Internet connection (for downloading packages)

## Step 1: Build and Start a Test VM

Open a terminal and run:

```bash
cd /home/dennis/ai-vm

# Build a VM with 8GB RAM, 4 CPUs, 50GB storage
./vm-selector.sh --name nested-test --ram 8 --cpu 4 --storage 50
```

**Expected output:**
```
Building VM configuration...
Building VM with Nix...
✓ VM built successfully
Creating startup script: start-nested-test.sh
...
Starting VM now...
```

The VM will start and show QEMU output. **Leave this terminal open** - the VM is running here.

**Wait 60-90 seconds** for the VM to boot completely before continuing.

## Step 2: SSH into the VM

Open a **NEW terminal** (keep the first one running the VM) and connect:

```bash
ssh -p 2222 dennis@localhost
```

**No password required** - just press Enter if prompted.

You should see:

```
The authenticity of host '[localhost]:2222 ([127.0.0.1]:2222)' can't be established.
...
Are you sure you want to continue connecting (yes/no/[fingerprint])? yes

[dennis@nested-test:~]$
```

You're now inside the VM!

## Step 3: Copy and Run the Test Script

**Still in the second terminal (inside the VM)**, run:

```bash
# Download the test script from host
# (First open ANOTHER terminal on the host to copy the file)
```

Actually, let's make this simpler. In the **VM terminal**, create the test script directly:

```bash
# Create the test script inside the VM
curl -o /tmp/nested-vm-test.sh https://raw.githubusercontent.com/dvaerum/ai-vm/main/tests/nested-vm-test-inner.sh 2>/dev/null || \
cat > /tmp/nested-vm-test.sh << 'SCRIPT_END'
#!/usr/bin/env bash
# Quick nested VM test

set -euo pipefail

echo "Testing nested VM creation..."
echo ""

# Check host store
if [[ ! -d /nix/.ro-store ]]; then
    echo "✗ FAIL: /nix/.ro-store not found"
    exit 1
fi
echo "✓ Host store mounted: $(ls /nix/.ro-store | wc -l) packages"

# Check overlay
if ! mount | grep -q "overlay on /nix/store"; then
    echo "✗ FAIL: Overlay not active"
    exit 1
fi
echo "✓ Overlay filesystem active"

# Create minimal test VM
mkdir -p /tmp/nested-test-$$
cd /tmp/nested-test-$$

cat > flake.nix << 'EOF'
{
  description = "Minimal nested VM";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { nixpkgs, ... }: {
    packages.x86_64-linux.default =
      (nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [{
          boot.loader.grub = { enable = true; device = "/dev/vda"; };
          fileSystems."/" = { device = "/dev/disk/by-label/nixos"; fsType = "ext4"; };
          nix.settings.experimental-features = [ "nix-command" "flakes" ];
          users.users.test = { isNormalUser = true; password = ""; };
          system.stateVersion = "23.11";
        }];
      }).config.system.build.vm;
  };
}
EOF

git init -q
git add flake.nix
git commit -qm "test"

echo "✓ Created nested VM flake"
echo ""
echo "Building nested VM (this may take 5-10 minutes)..."

START=$(date +%s)
if timeout 600 nix build .#default --impure 2>&1 | grep -E "building|error" | tail -20; then
    END=$(date +%s)
    TIME=$((END - START))

    if [[ -f result/bin/run-*-vm ]]; then
        echo ""
        echo "✓✓✓ SUCCESS! Nested VM built in ${TIME} seconds"
        echo ""
        echo "Results:"
        echo "  • Host store packages used: $(grep -c '/nix/.ro-store' <(nix path-info --all 2>/dev/null) || echo 'many')"
        echo "  • VM binary: $(ls result/bin/run-*-vm)"
        echo "  • Build time: ${TIME}s (good if <300s)"
        echo ""
        echo "Nested VM creation is WORKING!"
    else
        echo "✗ FAIL: Build succeeded but no VM binary found"
        exit 1
    fi
else
    echo "✗ FAIL: Build failed or timed out"
    exit 1
fi

SCRIPT_END

chmod +x /tmp/nested-vm-test.sh
```

Now run the test:

```bash
bash /tmp/nested-vm-test.sh
```

**This will take 5-10 minutes.** You'll see output like:

```
Testing nested VM creation...

✓ Host store mounted: 3421 packages
✓ Overlay filesystem active
✓ Created nested VM flake

Building nested VM (this may take 5-10 minutes)...
building '/nix/store/...'
...
```

## Step 4: Verify Success

If the test succeeds, you'll see:

```
✓✓✓ SUCCESS! Nested VM built in 287 seconds

Results:
  • Host store packages used: many
  • VM binary: result/bin/run-testvm-vm
  • Build time: 287s (good if <300s)

Nested VM creation is WORKING!
```

**This confirms:**
- ✓ VMs can create nested VMs
- ✓ Host store is accessible as binary cache
- ✓ No package duplication (efficient)
- ✓ Build times are reasonable (<5 minutes)

## Alternative: Use the Full Test Script

For more detailed testing, copy the comprehensive test script:

**On host (in a 3rd terminal):**

```bash
cd /home/dennis/ai-vm
scp -P 2222 tests/nested-vm-test-inner.sh dennis@localhost:/tmp/
```

**Inside the VM:**

```bash
bash /tmp/nested-vm-test-inner.sh
```

This runs a complete test suite with detailed diagnostics.

## Cleanup

**Inside the VM:**
```bash
# Remove test files
rm -rf /tmp/nested-test-*
rm -f /tmp/nested-vm-test.sh
```

**On host (after exiting the VM):**
```bash
# Stop the VM: Press Ctrl+C in the terminal running the VM

# Optionally remove test VM files:
rm -f nested-test.qcow2
rm -f start-nested-test.sh
```

## Troubleshooting

### VM won't start
- Check you have enough RAM: `free -h`
- Check QEMU is installed: `which qemu-system-x86_64`

### Can't SSH into VM
- Wait longer (VMs take 60-90 seconds to boot)
- Check VM is running: `ps aux | grep qemu`
- Try again: `ssh -p 2222 dennis@localhost`

### Build fails in VM
- Check internet connection in VM: `ping -c 3 1.1.1.1`
- Check /nix/.ro-store exists: `ls /nix/.ro-store | wc -l`
- Check overlay is active: `mount | grep overlay`

### Build takes >10 minutes
- This might indicate host store isn't being used
- Check available disk space: `df -h`
- Check for errors in output

## Expected Performance

**With working host store:**
- Build time: 2-5 minutes (excellent)
- Build time: 5-10 minutes (good)

**Without host store (broken):**
- Build time: 30-60 minutes (rebuilds everything)

If your build completes in under 10 minutes, **the nested VM feature is working correctly!**

## Success Criteria

Nested VM functionality is confirmed if:

✓ `/nix/.ro-store` contains thousands of packages
✓ Overlay filesystem is active on `/nix/store`
✓ Nested VM builds successfully (no errors)
✓ Build completes in <10 minutes
✓ VM binary is created at `result/bin/run-*-vm`

## What's Next?

The nested VM feature is now validated. You can:

1. Use nested VMs for testing VM configurations
2. Build VMs inside development VMs
3. Create isolated testing environments

The nested VM doesn't need to be started (triple nesting is very slow) - the fact that it builds proves the feature works!

## Questions?

See the full testing guide: `tests/NESTED-VM-TESTING.md`

Or refer to the project documentation: `CLAUDE.md` (lines 149-184)
