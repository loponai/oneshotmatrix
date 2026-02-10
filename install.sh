#!/usr/bin/env bash
# matrix-discord-killer installer
# Usage: curl -fsSL https://raw.githubusercontent.com/loponai/oneshotmatrix/main/install.sh | bash
set -euo pipefail

REPO_URL="https://github.com/loponai/oneshotmatrix.git"
INSTALL_DIR="/opt/matrix-discord-killer"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

echo ""
echo "  ╔══════════════════════════════════════════╗"
echo "  ║       matrix-discord-killer              ║"
echo "  ║   Matrix/Element or Stoat — your pick    ║"
echo "  ╚══════════════════════════════════════════╝"
echo ""

# Must run as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Error: This installer must be run as root.${NC}"
    echo "Re-run with: curl -fsSL <url> | sudo bash"
    exit 1
fi

# Detect OS
if [ ! -f /etc/os-release ]; then
    echo -e "${RED}Error: Cannot detect OS. Only Ubuntu/Debian are supported.${NC}"
    exit 1
fi

. /etc/os-release
if [[ "$ID" != "ubuntu" && "$ID" != "debian" && "${ID_LIKE:-}" != *"debian"* && "${ID_LIKE:-}" != *"ubuntu"* ]]; then
    echo -e "${RED}Error: Only Ubuntu/Debian (or derivatives) are supported. Detected: $ID${NC}"
    exit 1
fi

echo -e "${GREEN}Detected:${NC} ${PRETTY_NAME:-$ID}"

# Reopen stdin for interactive prompts (curl pipes eat stdin)
if [ -t 0 ] || [ -e /dev/tty ]; then
    exec </dev/tty
fi

# Install git if missing
if ! command -v git &>/dev/null; then
    echo "Installing git..."
    apt-get update -qq && apt-get install -y -qq git >/dev/null 2>&1
fi

# Clone or update repo
if [ -d "$INSTALL_DIR" ]; then
    echo "Existing installation found at $INSTALL_DIR"
    echo "Pulling latest changes..."
    git -C "$INSTALL_DIR" pull --ff-only || true
else
    echo "Cloning to $INSTALL_DIR..."
    git clone "$REPO_URL" "$INSTALL_DIR"
fi

chmod +x "$INSTALL_DIR/setup.sh" "$INSTALL_DIR/uninstall.sh"

# Hand off to setup
exec "$INSTALL_DIR/setup.sh"
