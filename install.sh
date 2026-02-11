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
    echo -e "${RED}Error: Cannot detect OS (missing /etc/os-release).${NC}"
    exit 1
fi

. /etc/os-release
if [[ "$ID" == "ubuntu" || "$ID" == "debian" || "${ID_LIKE:-}" == *"debian"* || "${ID_LIKE:-}" == *"ubuntu"* ]]; then
    export OS_FAMILY="debian"
elif [[ "$ID" == "rocky" || "$ID" == "rhel" || "$ID" == "centos" || "${ID_LIKE:-}" == *"rhel"* || "${ID_LIKE:-}" == *"fedora"* ]]; then
    export OS_FAMILY="rhel"
else
    echo -e "${RED}Error: Unsupported OS. Supported: Ubuntu, Debian, Rocky Linux, RHEL, CentOS. Detected: $ID${NC}"
    exit 1
fi

echo -e "${GREEN}Detected:${NC} ${PRETTY_NAME:-$ID} (${OS_FAMILY})"

# Install git if missing
if ! command -v git &>/dev/null; then
    echo -n "Installing git... "
    if [ "$OS_FAMILY" = "rhel" ]; then
        dnf install -y -q git 2>&1 || { echo -e "${RED}FAILED${NC}"; echo "Run manually: dnf install -y git"; exit 1; }
    else
        apt-get update -qq && apt-get install -y -qq git 2>&1 || { echo -e "${RED}FAILED${NC}"; echo "Run manually: apt-get install -y git"; exit 1; }
    fi
    echo -e "${GREEN}done${NC}"
fi

# Clone or update repo
if [ -d "$INSTALL_DIR" ]; then
    echo -n "Updating existing installation... "
    git -C "$INSTALL_DIR" pull --ff-only >/dev/null 2>&1 || true
    echo -e "${GREEN}done${NC}"
else
    echo -n "Downloading installer files... "
    git clone -q "$REPO_URL" "$INSTALL_DIR" 2>&1
    echo -e "${GREEN}done${NC}"
fi

chmod +x "$INSTALL_DIR/setup.sh" "$INSTALL_DIR/uninstall.sh"

echo "Starting setup..."
echo ""

# Hand off to setup (redirect stdin to /dev/tty for interactive prompts,
# since curl|bash leaves stdin as the exhausted pipe)
exec "$INSTALL_DIR/setup.sh" </dev/tty
