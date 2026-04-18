#!/usr/bin/env bash
# Statica installer — installs the CLI and optionally provisions a self-host server.
#
# Install / upgrade CLI only:
#   curl -fsSL https://raw.githubusercontent.com/statica-ai/statica/main/scripts/install.sh | bash
#
# Install CLI + provision self-host server:
#   curl -fsSL https://raw.githubusercontent.com/statica-ai/statica/main/scripts/install.sh | bash -s -- --with-server
#
# After installation, run `statica setup` to configure your environment.
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
REPO_URL="https://github.com/statica-ai/statica.git"
REPO_WEB_URL="https://github.com/statica-ai/statica"  # without .git, for GitHub web APIs
INSTALL_DIR="${MULTICA_INSTALL_DIR:-$HOME/.statica/server}"
BREW_PACKAGE="statica-ai/tap/statica"

# Colors (disabled when not a terminal)
if [ -t 1 ] || [ -t 2 ]; then
  BOLD='\033[1m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  RED='\033[0;31m'
  CYAN='\033[0;36m'
  RESET='\033[0m'
else
  BOLD='' GREEN='' YELLOW='' RED='' CYAN='' RESET=''
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { printf "${BOLD}${CYAN}==> %s${RESET}\n" "$*"; }
ok()    { printf "${BOLD}${GREEN}✓ %s${RESET}\n" "$*"; }
warn()  { printf "${BOLD}${YELLOW}⚠ %s${RESET}\n" "$*" >&2; }
fail()  { printf "${BOLD}${RED}✗ %s${RESET}\n" "$*" >&2; exit 1; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

detect_os() {
  case "$(uname -s)" in
    Darwin) OS="darwin" ;;
    Linux)  OS="linux" ;;
    MINGW*|MSYS*|CYGWIN*)
            fail "This script does not support Windows. Use the PowerShell installer instead:
  irm https://raw.githubusercontent.com/statica-ai/statica/main/scripts/install.ps1 | iex" ;;
    *)      fail "Unsupported operating system: $(uname -s). Statica supports macOS, Linux, and Windows." ;;
  esac

  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    arm64)   ARCH="arm64" ;;
    *)       fail "Unsupported architecture: $ARCH" ;;
  esac
}

# ---------------------------------------------------------------------------
# CLI Installation
# ---------------------------------------------------------------------------
install_cli_brew() {
  info "Installing Statica CLI via Homebrew..."
  if ! brew tap statica-ai/tap 2>/dev/null; then
    fail "Failed to add Homebrew tap. Check your network connection."
  fi
  # brew install exits non-zero if already installed on older Homebrew versions
  if ! brew install "$BREW_PACKAGE" 2>/dev/null; then
    if brew list "$BREW_PACKAGE" >/dev/null 2>&1; then
      ok "Statica CLI already installed via Homebrew"
    else
      fail "Failed to install statica via Homebrew."
    fi
  else
    ok "Statica CLI installed via Homebrew"
  fi
}

install_cli_binary() {
  info "Installing Statica CLI from GitHub Releases..."

  # Get latest release tag
  local latest
  latest=$(curl -sI "$REPO_WEB_URL/releases/latest" 2>/dev/null | grep -i '^location:' | sed 's/.*tag\///' | tr -d '\r\n' || true)
  if [ -z "$latest" ]; then
    fail "Could not determine latest release. Check your network connection."
  fi

  local url="https://github.com/statica-ai/statica/releases/download/${latest}/statica_${OS}_${ARCH}.tar.gz"
  local tmp_dir
  tmp_dir=$(mktemp -d)

  info "Downloading $url ..."
  if ! curl -fsSL "$url" -o "$tmp_dir/statica.tar.gz"; then
    rm -rf "$tmp_dir"
    fail "Failed to download CLI binary."
  fi

  tar -xzf "$tmp_dir/statica.tar.gz" -C "$tmp_dir" statica

  # Try /usr/local/bin first, fall back to ~/.local/bin
  local bin_dir="/usr/local/bin"
  if [ -w "$bin_dir" ]; then
    mv "$tmp_dir/statica" "$bin_dir/statica"
  elif command_exists sudo; then
    sudo mv "$tmp_dir/statica" "$bin_dir/statica"
  else
    bin_dir="$HOME/.local/bin"
    mkdir -p "$bin_dir"
    mv "$tmp_dir/statica" "$bin_dir/statica"
    chmod +x "$bin_dir/statica"
    # Add to PATH if not already there
    if ! echo "$PATH" | tr ':' '\n' | grep -q "^$bin_dir$"; then
      export PATH="$bin_dir:$PATH"
      add_to_path "$bin_dir"
    fi
  fi

  rm -rf "$tmp_dir"
  ok "Statica CLI installed to $bin_dir/statica"
}

add_to_path() {
  local dir="$1"
  local line="export PATH=\"$dir:\$PATH\""
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$rc" ] && ! grep -qF "$dir" "$rc"; then
      printf '\n# Added by Statica installer\n%s\n' "$line" >> "$rc"
    fi
  done
}

get_latest_version() {
  # grep exits 1 when no match; use `|| true` to avoid triggering pipefail
  curl -sI "$REPO_WEB_URL/releases/latest" 2>/dev/null | grep -i '^location:' | sed 's/.*tag\///' | tr -d '\r\n' || true
}

upgrade_cli_brew() {
  info "Upgrading Statica CLI via Homebrew..."
  brew update 2>/dev/null || true
  if brew upgrade "$BREW_PACKAGE" 2>/dev/null; then
    ok "Statica CLI upgraded via Homebrew"
  else
    # brew upgrade exits non-zero if already up to date
    ok "Statica CLI is already the latest version"
  fi
}

install_cli() {
  if command_exists statica; then
    local current_ver
    # `statica version` outputs "statica v0.1.13 (commit: abc1234)" — extract just the version
    current_ver=$(statica version 2>/dev/null | awk '{print $2}' || echo "unknown")

    local latest_ver
    latest_ver=$(get_latest_version)

    # Normalize: strip leading 'v' for comparison
    local current_cmp="${current_ver#v}"
    local latest_cmp="${latest_ver#v}"

    if [ -z "$latest_ver" ] || [ "$current_cmp" = "$latest_cmp" ]; then
      ok "Statica CLI is up to date ($current_ver)"
      return 0
    fi

    info "Statica CLI $current_ver installed, latest is $latest_ver — upgrading..."
    if command_exists brew && brew list "$BREW_PACKAGE" >/dev/null 2>&1; then
      upgrade_cli_brew
    else
      install_cli_binary
    fi

    local new_ver
    new_ver=$(statica version 2>/dev/null | awk '{print $2}' || echo "unknown")
    ok "Statica CLI upgraded ($current_ver → $new_ver)"
    return 0
  fi

  if command_exists brew; then
    install_cli_brew
  else
    install_cli_binary
  fi

  # Verify
  if ! command_exists statica; then
    fail "CLI installed but 'statica' not found on PATH. You may need to restart your shell."
  fi
}

# ---------------------------------------------------------------------------
# Docker check
# ---------------------------------------------------------------------------
check_docker() {
  if ! command_exists docker; then
    printf "\n"
    fail "Docker is not installed. Statica self-hosting requires Docker and Docker Compose.

Install Docker:
  macOS:  https://docs.docker.com/desktop/install/mac-install/
  Linux:  https://docs.docker.com/engine/install/

After installing Docker, re-run this script with --with-server."
  fi

  if ! docker info >/dev/null 2>&1; then
    fail "Docker is installed but not running. Please start Docker and re-run this script."
  fi

  ok "Docker is available"
}

# ---------------------------------------------------------------------------
# Server setup (self-host / --with-server)
# ---------------------------------------------------------------------------
setup_server() {
  info "Setting up Statica server..."

  if [ -d "$INSTALL_DIR/.git" ]; then
    info "Updating existing installation at $INSTALL_DIR..."
    cd "$INSTALL_DIR"
    git fetch origin main --depth 1 2>/dev/null || true
    git reset --hard origin/main 2>/dev/null || true
  else
    info "Cloning Statica repository..."
    if ! command_exists git; then
      fail "Git is not installed. Please install git and re-run."
    fi
    # Remove leftover directory from a previously interrupted clone
    if [ -d "$INSTALL_DIR" ]; then
      warn "Removing incomplete installation at $INSTALL_DIR..."
      rm -rf "$INSTALL_DIR"
    fi
    mkdir -p "$(dirname "$INSTALL_DIR")"
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
    cd "$INSTALL_DIR"
  fi

  ok "Repository ready at $INSTALL_DIR"

  # Generate .env if needed
  if [ ! -f .env ]; then
    info "Creating .env with random JWT_SECRET..."
    cp .env.example .env
    local jwt
    jwt=$(openssl rand -hex 32)
    if [ "$(uname -s)" = "Darwin" ]; then
      sed -i '' "s/^JWT_SECRET=.*/JWT_SECRET=$jwt/" .env
    else
      sed -i "s/^JWT_SECRET=.*/JWT_SECRET=$jwt/" .env
    fi
    ok "Generated .env with random JWT_SECRET"
  else
    ok "Using existing .env"
  fi

  # Start Docker Compose
  info "Starting Statica services (this may take a few minutes on first run)..."
  docker compose -f docker-compose.selfhost.yml up -d --build

  # Wait for health check
  info "Waiting for backend to be ready..."
  local ready=false
  for i in $(seq 1 45); do
    if curl -sf http://localhost:8080/health >/dev/null 2>&1; then
      ready=true
      break
    fi
    sleep 2
  done

  if [ "$ready" = true ]; then
    ok "Statica server is running"
  else
    warn "Server is still starting. You can check logs with:"
    echo "  cd $INSTALL_DIR && docker compose -f docker-compose.selfhost.yml logs"
    echo ""
  fi
}


# ---------------------------------------------------------------------------
# Main: Default mode (install / upgrade CLI only)
# ---------------------------------------------------------------------------
run_default() {
  printf "\n"
  printf "${BOLD}  Statica — Installer${RESET}\n"
  printf "\n"

  detect_os
  install_cli

  printf "\n"
  printf "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
  printf "${BOLD}${GREEN}  ✓ Statica CLI is ready!${RESET}\n"
  printf "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
  printf "\n"
  printf "  ${BOLD}Next: configure your environment${RESET}\n"
  printf "\n"
  printf "     ${CYAN}statica setup${RESET}                # Connect to Statica Cloud (statica.ai)\n"
  printf "     ${CYAN}statica setup self-host${RESET}       # Connect to a self-hosted server\n"
  printf "\n"
  printf "  ${BOLD}Self-hosting?${RESET} Install the server first:\n"
  printf "     curl -fsSL https://raw.githubusercontent.com/statica-ai/statica/main/scripts/install.sh | bash -s -- --with-server\n"
  printf "\n"
}

# ---------------------------------------------------------------------------
# Main: With-server mode (provision self-host infrastructure + install CLI)
# ---------------------------------------------------------------------------
run_with_server() {
  printf "\n"
  printf "${BOLD}  Statica — Self-Host Installer${RESET}\n"
  printf "  Provisioning server infrastructure + installing CLI\n"
  printf "\n"

  detect_os
  check_docker
  setup_server
  install_cli

  printf "\n"
  printf "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
  printf "${BOLD}${GREEN}  ✓ Statica server is running and CLI is ready!${RESET}\n"
  printf "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
  printf "\n"
  printf "  ${BOLD}Frontend:${RESET}  http://localhost:3000\n"
  printf "  ${BOLD}Backend:${RESET}   http://localhost:8080\n"
  printf "  ${BOLD}Server at:${RESET} %s\n" "$INSTALL_DIR"
  printf "\n"
  printf "  ${BOLD}Next: configure your CLI to connect${RESET}\n"
  printf "\n"
  printf "     ${CYAN}statica setup self-host${RESET}   # Configure + authenticate + start daemon\n"
  printf "\n"
  printf "  Default verification code: ${BOLD}888888${RESET}\n"
  printf "\n"
  printf "  ${BOLD}To stop all services:${RESET}\n"
  printf "     curl -fsSL https://raw.githubusercontent.com/statica-ai/statica/main/scripts/install.sh | bash -s -- --stop\n"
  printf "\n"
}

# ---------------------------------------------------------------------------
# Stop: shut down a self-hosted installation
# ---------------------------------------------------------------------------
run_stop() {
  printf "\n"
  info "Stopping Statica services..."

  if [ -d "$INSTALL_DIR" ]; then
    cd "$INSTALL_DIR"
    if [ -f docker-compose.selfhost.yml ]; then
      docker compose -f docker-compose.selfhost.yml down
      ok "Docker services stopped"
    else
      warn "No docker-compose.selfhost.yml found at $INSTALL_DIR"
    fi
  else
    warn "No Statica installation found at $INSTALL_DIR"
  fi

  if command_exists statica; then
    statica daemon stop 2>/dev/null && ok "Daemon stopped" || true
  fi

  printf "\n"
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
main() {
  local mode="default"

  while [ $# -gt 0 ]; do
    case "$1" in
      --with-server) mode="with-server" ;;
      --local)       mode="with-server" ;;  # backwards compat alias
      --stop)        mode="stop" ;;
      --help|-h)
        echo "Usage: install.sh [--with-server | --stop]"
        echo ""
        echo "  (default)       Install / upgrade the Statica CLI"
        echo "  --with-server   Install CLI + provision a self-host server (Docker)"
        echo "  --stop          Stop a self-hosted installation"
        echo ""
        echo "After installation, run 'statica setup' to configure your environment."
        exit 0
        ;;
      *) warn "Unknown option: $1" ;;
    esac
    shift
  done

  case "$mode" in
    default)     run_default ;;
    with-server) run_with_server ;;
    stop)        run_stop ;;
  esac
}

main "$@"
