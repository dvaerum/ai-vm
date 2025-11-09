{ config, pkgs, ... }:

let
  # Wrapper script for Claude Code that automatically copies auth from shared folder
  # This wrapper is aliased as 'claude' command when --share-claude-auth is used
  start-claude = pkgs.writeShellScriptBin "start-claude" ''
    # Check if Claude auth is shared from host
    if [[ -f /mnt/host-ro/.claude/.credentials.json ]]; then
      # Create .claude directory if it doesn't exist
      mkdir -p "$HOME/.claude"

      # Copy credentials from shared folder
      cp /mnt/host-ro/.claude/.credentials.json "$HOME/.claude/.credentials.json"
      chmod 600 "$HOME/.claude/.credentials.json"

      # Copy settings file from host if available (contains theme preference, tips history, etc.)
      # This prevents first-time setup prompts (theme selection, etc.)
      if [[ -f /mnt/host-ro/.claude/.settings.json ]]; then
        cp /mnt/host-ro/.claude/.settings.json "$HOME/.claude.json"
        chmod 644 "$HOME/.claude.json"
        echo "✓ Claude settings copied from host"
      fi

      # Copy other files if they exist (history, projects, plugins config, etc.)
      if [[ -d /mnt/host-ro/.claude ]]; then
        # Copy everything except .credentials.json and .settings.json (already copied)
        rsync -a --exclude='.credentials.json' --exclude='.settings.json' /mnt/host-ro/.claude/ "$HOME/.claude/" 2>/dev/null || true
      fi

      echo "✓ Claude auth and settings copied from host shared folder"
    fi

    # Run claude with flags to bypass all permissions in VM environment
    exec ${pkgs.claude-code}/bin/claude --dangerously-skip-permissions --permission-mode bypassPermissions "$@"
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
    bat
    jq

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
    # claude: Normal Claude Code command
    # start-claude: Wrapper that copies auth from shared folders and uses permission bypass flags
    claude-code
    start-claude
  ];
}
