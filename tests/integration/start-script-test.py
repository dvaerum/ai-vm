#!/usr/bin/env python3
"""
Integration test for VM start script generation and execution.

This test verifies that:
1. A VM can be built using vm-selector.sh
2. A start-{VM_NAME}.sh script is generated
3. The start script can successfully launch the VM
4. The VM can be stopped and restarted using the start script
"""

import os
import subprocess
import time
import tempfile
import shutil
import pytest
import signal
import re
from pathlib import Path


class TestVMStartScript:
    @pytest.fixture(autouse=True)
    def setup(self):
        """Set up test environment."""
        self.project_root = Path(__file__).parent.parent.parent
        self.vm_selector_script = self.project_root / "vm-selector.sh"

        # Create temporary directory for VM files
        self.test_dir = tempfile.mkdtemp(prefix="vm-start-test-")
        self.vm_name = "test-vm"
        self.start_script = Path(self.test_dir) / f"start-{self.vm_name}.sh"

        yield

        # Cleanup
        if os.path.exists(self.test_dir):
            shutil.rmtree(self.test_dir)

    def run_vm_selector(self, *args, timeout=300):
        """
        Run vm-selector.sh with the given arguments.

        Args:
            *args: Arguments to pass to vm-selector.sh
            timeout: Command timeout in seconds (default: 300s for VM build)

        Returns:
            subprocess.CompletedProcess
        """
        cmd = [
            str(self.vm_selector_script),
            "--name", self.vm_name,
            *args
        ]

        env = os.environ.copy()
        env["INTERACTIVE"] = "false"  # Disable interactive prompts

        result = subprocess.run(
            cmd,
            cwd=self.test_dir,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env
        )

        return result

    def wait_for_vm_boot(self, timeout=60):
        """
        Wait for VM to boot and SSH to become available.

        Args:
            timeout: Maximum time to wait in seconds

        Returns:
            bool: True if VM booted successfully, False otherwise
        """
        start_time = time.time()

        while time.time() - start_time < timeout:
            try:
                result = subprocess.run(
                    ["ssh", "-p", "2222", "-o", "StrictHostKeyChecking=no",
                     "-o", "UserKnownHostsFile=/dev/null", "-o", "ConnectTimeout=2",
                     "dennis@localhost", "echo", "ready"],
                    capture_output=True,
                    text=True,
                    timeout=5
                )

                if result.returncode == 0 and "ready" in result.stdout:
                    return True
            except (subprocess.TimeoutExpired, subprocess.SubprocessError):
                pass

            time.sleep(2)

        return False

    def test_start_script_generation(self):
        """Test that a start script is generated when building a VM."""
        print("\n=== Testing start script generation ===")

        # Build a minimal VM
        result = self.run_vm_selector(
            "--ram", "2",
            "--cpu", "1",
            "--storage", "10"
        )

        # Check if build succeeded
        assert result.returncode == 0, (
            f"VM build failed:\nSTDOUT:\n{result.stdout}\n\nSTDERR:\n{result.stderr}"
        )

        print(f"VM build output:\n{result.stdout}")

        # Check if start script was created
        assert self.start_script.exists(), (
            f"Start script not found at {self.start_script}"
        )

        # Check if start script is executable
        assert os.access(self.start_script, os.X_OK), (
            f"Start script is not executable: {self.start_script}"
        )

        print(f"✓ Start script created: {self.start_script}")

    def test_start_script_content(self):
        """Test that the start script contains correct VM name and configuration."""
        print("\n=== Testing start script content ===")

        # Build VM first
        result = self.run_vm_selector(
            "--ram", "4",
            "--cpu", "2",
            "--storage", "20"
        )
        assert result.returncode == 0

        # Read start script content
        with open(self.start_script, 'r') as f:
            content = f.read()

        print(f"Start script content:\n{content}\n")

        # Check for VM name in the script
        assert f"VM_NAME=\"{self.vm_name}\"" in content, (
            f"VM_NAME variable not set correctly in start script"
        )

        # Check for RAM configuration
        assert "RAM_SIZE=4" in content, "RAM size not set correctly"

        # Check for CPU configuration
        assert "CPU_CORES=2" in content, "CPU cores not set correctly"

        # Check for storage configuration
        assert "STORAGE_SIZE=20" in content, "Storage size not set correctly"

        # Check for VM binary path - this is the critical test
        # The script should reference run-{VM_NAME}-vm, not run-${VM_NAME}-vm
        assert f"run-{self.vm_name}-vm" in content, (
            f"VM binary path not correctly interpolated. Expected 'run-{self.vm_name}-vm', "
            f"check if the script has uninterpolated variables like '${{VM_NAME}}'"
        )

        # Check that there are no uninterpolated ${VM_NAME} variables in the exec line
        exec_line_match = re.search(r'exec.*run-.*-vm', content)
        if exec_line_match:
            exec_line = exec_line_match.group(0)
            assert "${VM_NAME}" not in exec_line, (
                f"VM binary path has uninterpolated variable: {exec_line}"
            )
            print(f"✓ Exec line looks correct: {exec_line}")

        print("✓ Start script content validated")

    def test_start_script_execution(self):
        """Test that the start script can actually launch the VM."""
        print("\n=== Testing start script execution ===")

        # Build VM first
        result = self.run_vm_selector(
            "--ram", "2",
            "--cpu", "1",
            "--storage", "10"
        )
        assert result.returncode == 0

        # Launch VM using start script in background
        print(f"Launching VM with: {self.start_script}")

        vm_process = subprocess.Popen(
            [str(self.start_script)],
            cwd=self.test_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )

        try:
            # Wait for VM to boot
            print("Waiting for VM to boot (max 60s)...")
            booted = self.wait_for_vm_boot(timeout=60)

            assert booted, "VM failed to boot within timeout"
            print("✓ VM booted successfully via start script")

            # Verify we can execute a command in the VM
            result = subprocess.run(
                ["ssh", "-p", "2222", "-o", "StrictHostKeyChecking=no",
                 "-o", "UserKnownHostsFile=/dev/null",
                 "dennis@localhost", "hostname"],
                capture_output=True,
                text=True,
                timeout=10
            )

            assert result.returncode == 0, f"Failed to execute command in VM: {result.stderr}"
            assert self.vm_name in result.stdout, (
                f"VM hostname mismatch. Expected '{self.vm_name}', got '{result.stdout.strip()}'"
            )
            print(f"✓ VM hostname verified: {result.stdout.strip()}")

        finally:
            # Stop the VM
            print("Stopping VM...")
            vm_process.terminate()
            try:
                vm_process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                vm_process.kill()
                vm_process.wait()

            print("✓ VM stopped")

    def test_start_script_reusability(self):
        """Test that the start script can be used multiple times (restart)."""
        print("\n=== Testing start script reusability ===")

        # Build VM
        result = self.run_vm_selector(
            "--ram", "2",
            "--cpu", "1",
            "--storage", "10"
        )
        assert result.returncode == 0

        # First launch
        print("First VM launch...")
        vm_process1 = subprocess.Popen(
            [str(self.start_script)],
            cwd=self.test_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )

        try:
            assert self.wait_for_vm_boot(timeout=60), "First boot failed"
            print("✓ First boot successful")
        finally:
            vm_process1.terminate()
            vm_process1.wait(timeout=10)

        # Wait a moment for cleanup
        time.sleep(2)

        # Second launch (restart)
        print("Second VM launch (restart)...")
        vm_process2 = subprocess.Popen(
            [str(self.start_script)],
            cwd=self.test_dir,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )

        try:
            assert self.wait_for_vm_boot(timeout=60), "Second boot failed"
            print("✓ Second boot successful - start script is reusable")
        finally:
            vm_process2.terminate()
            vm_process2.wait(timeout=10)


if __name__ == "__main__":
    pytest.main([__file__, "-v", "-s"])
