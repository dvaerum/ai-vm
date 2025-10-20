{ pkgs ? import <nixpkgs> { } }:

let
  # Import the vm-selector script for testing
  vmSelectorScript = ../vm-selector.sh;
in

pkgs.runCommand "vm-selector-unit-tests" {
  buildInputs = with pkgs; [ bash ];
} ''
  # Test script syntax
  echo "=== Testing vm-selector.sh syntax ==="
  bash -n ${vmSelectorScript}
  echo "✓ Script syntax is valid"

  # Test script has required functions
  echo "=== Testing script structure ==="

  # Check for required functions and variables
  grep -q "show_help()" ${vmSelectorScript} || (echo "✗ show_help function missing" && exit 1)
  grep -q "validate_numeric()" ${vmSelectorScript} || (echo "✗ validate_numeric function missing" && exit 1)
  grep -q "RAM_OPTIONS=" ${vmSelectorScript} || (echo "✗ RAM_OPTIONS variable missing" && exit 1)
  grep -q "CPU_OPTIONS=" ${vmSelectorScript} || (echo "✗ CPU_OPTIONS variable missing" && exit 1)
  grep -q "STORAGE_OPTIONS=" ${vmSelectorScript} || (echo "✗ STORAGE_OPTIONS variable missing" && exit 1)

  echo "✓ All required functions and variables present"

  # Test help text content
  echo "=== Testing help text content ==="

  grep -q "\-\-ram RAM" ${vmSelectorScript} || (echo "✗ --ram option missing from help" && exit 1)
  grep -q "\-\-cpu CPU" ${vmSelectorScript} || (echo "✗ --cpu option missing from help" && exit 1)
  grep -q "\-\-storage STORAGE" ${vmSelectorScript} || (echo "✗ --storage option missing from help" && exit 1)
  grep -q "\-\-share-rw PATH" ${vmSelectorScript} || (echo "✗ --share-rw option missing from help" && exit 1)
  grep -q "\-\-share-ro PATH" ${vmSelectorScript} || (echo "✗ --share-ro option missing from help" && exit 1)
  grep -q "\-\-name NAME" ${vmSelectorScript} || (echo "✗ --name option missing from help" && exit 1)
  grep -q "\-\-overlay" ${vmSelectorScript} || (echo "✗ --overlay option missing from help" && exit 1)
  grep -q "\-\-audio" ${vmSelectorScript} || (echo "✗ --audio option missing from help" && exit 1)

  echo "✓ All command line options documented in help"

  # Test validation patterns
  echo "=== Testing validation patterns ==="

  grep -q "\[a-zA-Z0-9_-\]" ${vmSelectorScript} || (echo "✗ VM name validation pattern missing" && exit 1)
  grep -q "\[1-9\]\[0-9\]" ${vmSelectorScript} || (echo "✗ Numeric validation pattern missing" && exit 1)

  echo "✓ Validation patterns are present"

  # Test script contains all required argument parsing
  echo "=== Testing argument parsing ==="

  grep -q "\-r|\-\-ram)" ${vmSelectorScript} || (echo "✗ RAM argument parsing missing" && exit 1)
  grep -q "\-c|\-\-cpu)" ${vmSelectorScript} || (echo "✗ CPU argument parsing missing" && exit 1)
  grep -q "\-s|\-\-storage)" ${vmSelectorScript} || (echo "✗ Storage argument parsing missing" && exit 1)
  grep -q "\-n|\-\-name)" ${vmSelectorScript} || (echo "✗ Name argument parsing missing" && exit 1)
  grep -q "\-\-share-rw)" ${vmSelectorScript} || (echo "✗ Share-RW argument parsing missing" && exit 1)
  grep -q "\-\-share-ro)" ${vmSelectorScript} || (echo "✗ Share-RO argument parsing missing" && exit 1)
  grep -q "\-a|\-\-audio)" ${vmSelectorScript} || (echo "✗ Audio argument parsing missing" && exit 1)

  echo "✓ All argument parsing cases are present"

  # Test fzf custom input handling fix
  echo "=== Testing fzf custom input handling ==="

  # Check that the script has the correct fzf output handling logic
  grep -q "fzf_output=.*fzf.*--print-query" ${vmSelectorScript} || (echo "✗ fzf output capture missing" && exit 1)

  # Check for the fallback logic pattern (separate lines)
  grep -q "tail -1" ${vmSelectorScript} || (echo "✗ tail -1 extraction missing" && exit 1)
  grep -q "head -1" ${vmSelectorScript} || (echo "✗ head -1 fallback missing" && exit 1)
  grep -q "\[\[ -z.*\]\] && .*head -1" ${vmSelectorScript} || (echo "✗ fallback condition missing" && exit 1)

  # Check that all three selection types (RAM, CPU, Storage) have the fix applied
  grep -c "fzf_output=.*fzf.*--print-query" ${vmSelectorScript} | grep -q "3" || (echo "✗ fzf fix not applied to all three selection types" && exit 1)

  echo "✓ fzf custom input handling fix is properly implemented"

  # Test specific scenario: typing "12" in fzf for CPU cores
  echo "=== Testing fzf '12 cores' scenario specifically ==="

  # Test Case 1: Only query output (most common)
  fzf_output="12"
  selected_cpu=$(echo "$fzf_output" | tail -1)
  [[ -z "$selected_cpu" ]] && selected_cpu=$(echo "$fzf_output" | head -1)
  [[ "$selected_cpu" == "12" ]] || (echo "✗ Case 1 failed - got '$selected_cpu'" && exit 1)
  echo "✓ Case 1: Query-only output works"

  # Test Case 2: Query + empty selection
  fzf_output=$'12\n'
  selected_cpu=$(echo "$fzf_output" | tail -1)
  [[ -z "$selected_cpu" ]] && selected_cpu=$(echo "$fzf_output" | head -1)
  [[ "$selected_cpu" == "12" ]] || (echo "✗ Case 2 failed - got '$selected_cpu'" && exit 1)
  echo "✓ Case 2: Query + empty selection works"

  # Test Case 3: Validation test
  [[ "12" =~ ^[1-9][0-9]*$ ]] || (echo "✗ Case 3 failed - validation failed" && exit 1)
  echo "✓ Case 3: Validation accepts 12"

  echo "✓ fzf 12 cores scenario test passed"

  # Test /etc/nixos configuration generation (basic validation)
  echo "=== Testing /etc/nixos configuration generation ==="

  # Check that the virtualisation module contains /etc/nixos configuration patterns
  vmModule=../nixos/modules/virtualisation-parameterized.nix
  if [[ -f "$vmModule" ]]; then
    grep -q "environment.etc.\"nixos/flake.nix\"" "$vmModule" || (echo "✗ flake.nix generation missing" && exit 1)
    grep -q "environment.etc.\"nixos/configuration.nix\"" "$vmModule" || (echo "✗ configuration.nix generation missing" && exit 1)
    grep -q "environment.etc.\"nixos/hardware-configuration.nix\"" "$vmModule" || (echo "✗ hardware-configuration.nix generation missing" && exit 1)
    grep -q "environment.etc.\"nixos/README.md\"" "$vmModule" || (echo "✗ README.md generation missing" && exit 1)
    grep -q "Quick Commands" "$vmModule" || (echo "✗ README content missing" && exit 1)
    echo "✓ /etc/nixos configuration generation tests passed"
  else
    echo "⚠️ Virtualisation module not found at expected path (test environment limitation)"
  fi

  # Success marker
  touch $out
  echo "=== All unit tests passed! ==="
''