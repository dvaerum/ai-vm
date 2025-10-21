# Manual Nested VM Testing Instructions

I've created comprehensive testing tools and documentation for validating nested VM functionality. Here's what you need to do to test it.

## Files Created for Testing

1. **`QUICKSTART-NESTED-VM-TEST.md`** - Simple copy-paste guide (recommended start here)
2. **`tests/NESTED-VM-TESTING.md`** - Comprehensive testing documentation
3. **`tests/nested-vm-test-inner.sh`** - Full automated test script (runs inside VM)
4. **`tests/manual-nested-vm-test.sh`** - Semi-automated test harness

## Quick Test (15 minutes)

### Terminal 1: Start the VM

```bash
cd /home/dennis/ai-vm
./vm-selector.sh --name nested-test --ram 8 --cpu 4 --storage 50
```

**Leave this running** - the VM is executing here.

**Wait 60-90 seconds** for boot.

### Terminal 2: SSH and Test

```bash
# SSH into the VM (no password)
ssh -p 2222 dennis@localhost

# Quick verification
ls -l /nix/.ro-store | head
mount | grep overlay

# Quick test - create and build a minimal nested VM
mkdir -p ~/quick-test && cd ~/quick-test

cat > flake.nix << 'EOF'
{
  description = "Quick nested VM test";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  outputs = { nixpkgs, ... }: {
    packages.x86_64-linux.vm =
      (nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [{
          boot.loader.grub = { enable = true; device = "/dev/vda"; };
          fileSystems."/" = { device = "/dev/vda"; fsType = "ext4"; };
          nix.settings.experimental-features = [ "nix-command" "flakes" ];
          users.users.test.isNormalUser = true;
          system.stateVersion = "23.11";
        }];
      }).config.system.build.vm;
  };
}
EOF

git init && git add flake.nix && git commit -m "test"

# Build it (5-10 minutes)
time nix build .#vm --impure
```

**If this completes successfully in <10 minutes, nested VMs are working!**

### Verify Success

```bash
# Check the result
ls -lh result/bin/

# You should see: run-*-vm
```

**Success!** You've just built a VM inside a VM!

## Full Automated Test

For comprehensive testing with detailed output:

### Terminal 1: Start VM

```bash
cd /home/dennis/ai-vm
./vm-selector.sh --name nested-test --ram 8 --cpu 4 --storage 50
```

Wait 90 seconds for boot.

### Terminal 2: Copy and Run Test Script

```bash
# Copy test script to VM
scp -P 2222 tests/nested-vm-test-inner.sh dennis@localhost:/tmp/

# Run comprehensive test
ssh -p 2222 dennis@localhost "bash /tmp/nested-vm-test-inner.sh"
```

This runs a full test suite with 7 test categories and detailed diagnostics.

## Expected Results

### Success Indicators

✓ **Host store check**: `/nix/.ro-store` contains thousands of packages
✓ **Overlay check**: `mount | grep overlay` shows overlay on `/nix/store`
✓ **Build succeeds**: No errors during `nix build`
✓ **Build time**: <10 minutes (indicates host store being used)
✓ **VM binary created**: `result/bin/run-*-vm` exists

### Performance Benchmarks

| Scenario | Time | Status |
|----------|------|--------|
| With host store (working) | 2-5 min | Excellent |
| With host store (working) | 5-10 min | Good |
| Without host store (broken) | 30-60 min | Failing |

If build completes in <10 minutes, **nested VM feature is confirmed working**.

## Cleanup

```bash
# In VM: Remove test files
rm -rf ~/quick-test /tmp/nested-test-*

# On host: Stop VM (Ctrl+C in Terminal 1)
# Then optionally remove:
rm -f nested-test.qcow2 start-nested-test.sh
```

## Detailed Documentation

For complete information, see:

- **Quick Start**: `QUICKSTART-NESTED-VM-TEST.md` (simple guide)
- **Full Guide**: `tests/NESTED-VM-TESTING.md` (comprehensive)
- **Architecture**: `CLAUDE.md` (lines 149-184) (how it works)

## Why This Works

The nested VM feature works because:

1. **Host store mounted**: `/nix/store` from host → `/nix/.ro-store` in VM
2. **Overlay filesystem**: Writable layer on top of read-only host store
3. **Binary cache**: Packages from host are directly accessible
4. **No duplication**: Nested VMs don't rebuild packages already in host store

This is why build times are 5-10 minutes instead of 30-60 minutes!

## Troubleshooting

### Can't SSH
- Wait longer (90 seconds minimum)
- Check VM running: `ps aux | grep qemu`
- Try with verbose: `ssh -v -p 2222 dennis@localhost`

### /nix/.ro-store empty
- Check mount: `mount | grep nix-store`
- Check config: `virtualisation-parameterized.nix` lines 63-69

### Build fails
- Check internet: `ping -c 3 1.1.1.1` (in VM)
- Check disk space: `df -h`
- Check overlay: `mount | grep overlay`

### Build slow (>10 min)
- May not be using host store
- Check `/nix/.ro-store` has packages: `ls /nix/.ro-store | wc -l`
- Should show >1000

## What Gets Tested

The test validates:

1. Host Nix store mounting
2. Overlay filesystem activation
3. Nix commands working
4. Flake creation inside VM
5. **Nested VM building** (critical test)
6. VM binary creation
7. Build efficiency (time)

## Summary

You now have everything needed to test nested VM functionality:

- **Quick test**: 5-line command sequence (Terminal 2 above)
- **Full test**: `tests/nested-vm-test-inner.sh` script
- **Documentation**: Three guides at different detail levels

**Next step**: Follow the Quick Test instructions above to validate nested VMs work!

---

**Time Investment**: 15-20 minutes total
**Result**: Confirmed nested VM functionality working
**Value**: Enables VM development inside VMs without performance penalty
