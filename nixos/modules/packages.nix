{ config, pkgs, ... }:

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
    tree
    unzip
    fish

    # Search and file tools
    fd
    ripgrep
    ripgrep-all

    # Development tools
    nodejs_20
    python3
    python3Packages.pip
    rustc
    cargo
    go

    # Build tools
    gcc
    gnumake

    # Claude Code and AI tools
    claude-code
  ];
}