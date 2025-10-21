{ config, pkgs, ... }:

let
  # Wrapper script for Claude Code that automatically copies auth from shared folder
  claude-wrapper = pkgs.writeShellScriptBin "claude" ''
    # Check if Claude auth is shared from host
    if [[ -f /mnt/host-ro/.claude/.credentials.json ]]; then
      # Create .claude directory if it doesn't exist
      mkdir -p "$HOME/.claude"

      # Copy credentials from shared folder
      cp /mnt/host-ro/.claude/.credentials.json "$HOME/.claude/.credentials.json"
      chmod 600 "$HOME/.claude/.credentials.json"

      # Copy other files if they exist (history, projects, etc.)
      if [[ -d /mnt/host-ro/.claude ]]; then
        # Copy everything except .credentials.json (already copied with correct permissions)
        rsync -a --exclude='.credentials.json' /mnt/host-ro/.claude/ "$HOME/.claude/" 2>/dev/null || true
      fi

      echo "✓ Claude auth copied from host shared folder"
    fi

    # Run claude with the dangerously-skip-permissions flag
    exec ${pkgs.claude-code}/bin/claude --dangerously-skip-permissions "$@"
  '';
in
{
  # Development tools and Claude Code dependencies
  environment.systemPackages = with pkgs; [
    # Basic system tools
    curl
    wget
    git
    vim
    nano
    htop
    pstree
    tree
    unzip
    fish
    rsync

    # Search and file tools
    fd
    ripgrep
    ripgrep-all

    # Development tools
    nodejs_22
    python3
    python3Packages.pip
    rustc
    cargo
    go

    # Build tools
    gcc
    gnumake

    # Claude Code and AI tools
    # Note: Using wrapper instead of direct claude-code package
    # The wrapper automatically copies auth from shared folders and uses --dangerously-skip-permissions
    claude-wrapper
  ];
}
