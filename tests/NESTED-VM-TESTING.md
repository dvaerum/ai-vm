# Nested VM Testing Guide

This guide provides step-by-step instructions for testing the nested VM functionality - the ability to create VMs inside VMs.

## What We're Testing

The nested VM feature allows you to:
1. Start a VM (the "parent VM")
2. Inside that VM, build and create another VM (the "nested VM")
3. Access packages from the host's Nix store without rebuilding them

This is made possible by mounting the host's `/nix/store` inside the VM at `/nix/.ro-store` and using it as a binary cache.

## Prerequisites

- The ai-vm project built successfully
- At least 8GB RAM available on host
- At least 50GB free disk space
- QEMU/KVM support (will work with emulation but slower)

## Testing Methods

### Method 1: Automated Test Script (Recommended)

**Note**: This method requires the VM to run in the background, which may not work with the current vm-selector.sh implementation. Use Method 2 for manual testing.

### Method 2: Manual Step-by-Step Testing (Recommended)

This is the most reliable method for testing nested VM functionality.

#### Step 1: Build a Test VM on Host

```bash
# From the project root
cd /home/dennis/ai-vm

# Build a VM with sufficient resources for nested VM creation
# 8GB RAM, 4 CPUs, 50GB storage
./vm-selector.sh --name nested-test --ram 8 --cpu 4 --storage 50
```

The VM will start automatically. You should see output like:
```
Starting VM: 8GB RAM, 4 CPU cores, 50GB storage...
```

#### Step 2: SSH into the VM (New Terminal)

Open a **new terminal** and connect:

```bash
ssh -p 2222 dennis@localhost
```

No password is required (passwordless authentication for development).

You should see a shell prompt inside the VM:
```
dennis@nested-test:~$
```

#### Step 3: Verify Host Store Mounting

Inside the VM, verify the host Nix store is mounted:

```bash
# Check if /nix/.ro-store exists
ls /nix/.ro-store

# You should see many package directories
# Count how many packages are accessible
ls /nix/.ro-store | wc -l

# Check overlay filesystem
mount | grep "overlay on /nix/store"

# You should see something like:
# overlay on /nix/store type overlay (rw,...)
```

**Expected results:**
- `/nix/.ro-store` contains thousands of package directories
- Overlay filesystem is active on `/nix/store`

#### Step 4: Create a Minimal Nested VM Flake

Inside the VM, create a test directory and flake:

```bash
# Create test directory
mkdir -p ~/nested-vm-test
cd ~/nested-vm-test

# Create a minimal VM flake
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

            users.users.test = {
              isNormalUser = true;
              initialPassword = "test";
            };

            # Minimal packages
            environment.systemPackages = with pkgs; [ vim ];
          }
        ];
      };

      packages.${system}.vm =
        self.nixosConfigurations.minimal-vm.config.system.build.vm;
    };
}
EOF

# Initialize git (required for flakes)
git init
git add flake.nix
git commit -m "Initial nested VM flake"
```

#### Step 5: Build the Nested VM

This is the critical test - building a VM inside a VM:

```bash
# Build the nested VM
# This should use the host store via /nix/.ro-store
nix build .#vm --impure --print-build-logs
```

**What to watch for:**
- Build should complete successfully
- Build should be relatively fast (using cached packages from host store)
- You might see messages about copying from `/nix/.ro-store`
- No errors about read-only filesystem or missing store paths

**Expected output (end):**
```
...
building '/nix/store/...-nixos-system-minimal-vm-23.11.drv'...
...
```

#### Step 6: Verify Nested VM Binary

Check that the nested VM was built successfully:

```bash
# Check result symlink
ls -l result

# Should point to a path in /nix/store
# lrwxrwxrwx 1 dennis users 55 Oct 21 12:00 result -> /nix/store/...-vm

# Check for VM binary
ls -lh result/bin/

# Should contain: run-minimal-vm-vm
file result/bin/run-minimal-vm-vm

# Should show: POSIX shell script, ASCII text executable
```

#### Step 7: (Optional) Start the Nested VM

**Warning**: Starting a VM inside a VM (triple nesting) requires significant resources and may be very slow.

```bash
# Only try this if you have spare resources
./result/bin/run-minimal-vm-vm

# The nested VM will start (very slowly)
# Press Ctrl+A then X to exit QEMU
```

This step is optional - the fact that the build succeeded proves nested VM functionality works!

### Step 8: Validate Success

If you completed steps 1-6 successfully, the nested VM feature is working! You've verified:

✅ Host Nix store is mounted in the VM
✅ Overlay filesystem allows writing to `/nix/store`
✅ VMs can build nested VMs using host store packages
✅ No duplication of packages (efficient binary cache)
✅ Nested VM binaries are created correctly

## Method 3: Automated Testing with Script

Use the provided test script for a partially automated approach:

```bash
# Copy the inner test script to your clipboard or a file
# Then SSH into the VM and run it

# On host:
cd /home/dennis/ai-vm

# Start a VM first (in one terminal)
./vm-selector.sh --name nested-test --ram 8 --cpu 4 --storage 50

# In another terminal, wait for VM to boot (60 seconds), then:
scp -P 2222 tests/nested-vm-test-inner.sh dennis@localhost:/tmp/
ssh -p 2222 dennis@localhost "bash /tmp/nested-vm-test-inner.sh"
```

## Troubleshooting

### Issue: `/nix/.ro-store` not found

**Cause**: Host store not mounted
**Solution**: Check virtualisation-parameterized.nix:63-69 and 92-98 for sharedDirectories configuration

### Issue: Overlay filesystem not active

**Cause**: writableStore not enabled
**Solution**: Check virtualisation-parameterized.nix:34 - should be `true`

### Issue: Nested VM build fails with "read-only file system"

**Cause**: Overlay not working correctly
**Solution**: Check `mount | grep overlay` output - overlay should be mounted on `/nix/store`

### Issue: Build extremely slow or times out

**Cause**: Not using host store cache, rebuilding everything
**Solution**:
- Verify `/nix/.ro-store` has packages: `ls /nix/.ro-store | wc -l` should show >1000
- Check 9p mount: `mount | grep nix-store`

### Issue: Cannot SSH into VM

**Cause**: VM not started or SSH not ready
**Solution**:
- Wait longer (VMs can take 60-90 seconds to boot)
- Check if VM process is running: `ps aux | grep qemu`
- Check VM console output for errors

## Expected Results

### Successful Test

When nested VM creation works correctly, you'll see:

1. **Host store mounted**:
   ```
   $ ls /nix/.ro-store | wc -l
   3421  # (large number of packages)
   ```

2. **Overlay active**:
   ```
   $ mount | grep overlay
   overlay on /nix/store type overlay (rw,relatime,...)
   ```

3. **Build succeeds**:
   ```
   $ nix build .#vm --impure
   building '/nix/store/xxx-vm'...
   [builds successfully]
   ```

4. **VM binary created**:
   ```
   $ ls result/bin/
   run-minimal-vm-vm
   ```

### Build Time Comparison

Without host store (would need to build everything):
- First build: **30-60 minutes** (building entire NixOS)
- Subsequent builds: **5-10 minutes** (with local cache)

With host store (nested VM feature):
- First build: **2-5 minutes** (using host store cache)
- Subsequent builds: **30-60 seconds** (evaluation only)

**If your nested VM build completes in under 5 minutes, the host store feature is working!**

## Cleanup

After testing:

```bash
# On host:
# Stop the VM (Ctrl+C in the terminal running it)

# Remove test files
rm -f nested-test.qcow2
rm -f start-nested-test.sh

# Inside VM (before exiting):
rm -rf ~/nested-vm-test
```

## Success Criteria

The nested VM feature is working if:

- ✅ VM starts and is accessible via SSH
- ✅ `/nix/.ro-store` exists and contains host packages
- ✅ Overlay filesystem is active on `/nix/store`
- ✅ Nested VM flake can be created
- ✅ **Nested VM builds successfully without errors**
- ✅ Nested VM binary exists at `result/bin/run-*-vm`
- ✅ Build completes in under 10 minutes (indicating host store usage)

## Additional Tests

### Test Host Store Usage

Verify that builds are actually using the host store:

```bash
# Inside the VM, check if a specific package is used from host store
nix build nixpkgs#hello --print-build-logs 2>&1 | grep -i "copying\|/nix/.ro-store"

# You should see references to /nix/.ro-store or "copying from" messages
```

### Test Store Persistence

Verify that changes persist (without --overlay flag):

```bash
# Inside the VM, build something
nix build nixpkgs#cowsay

# Reboot the VM (from host, stop and restart)
# SSH back in
# The built package should still be available in /nix/store
```

## Performance Metrics

Collect metrics during nested VM build:

```bash
# Inside VM, before building
time nix build .#vm --impure --print-build-logs

# Typical results with working host store:
# real    3m24.532s
# user    1m42.101s
# sys     0m28.445s
```

## Documentation

After successful testing, document your results:

1. Time taken to build nested VM
2. Number of packages in `/nix/.ro-store`
3. Any errors encountered
4. System resources used (htop during build)

This helps validate the feature and provides benchmarks for future improvements.
