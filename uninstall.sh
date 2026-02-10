#!/usr/bin/env bash
# matrix-discord-killer uninstaller
set -euo pipefail

INSTALL_DIR="/opt/matrix-discord-killer"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo -e "${RED}  ╔══════════════════════════════════════════╗${NC}"
echo -e "${RED}  ║   matrix-discord-killer UNINSTALLER      ║${NC}"
echo -e "${RED}  ╚══════════════════════════════════════════╝${NC}"
echo ""

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Error: Must run as root.${NC}"
    exit 1
fi

echo -e "${YELLOW}WARNING: This will permanently destroy:${NC}"
echo "  - All Docker containers and volumes"
echo "  - All Matrix data (messages, media, accounts)"
echo "  - PostgreSQL database"
echo "  - SSL certificates"
echo "  - Coturn configuration"
echo "  - UFW firewall rules added by the installer"
echo ""
read -rp "Type 'DELETE EVERYTHING' to confirm: " confirm

if [ "$confirm" != "DELETE EVERYTHING" ]; then
    echo "Aborted."
    exit 0
fi

echo ""

# Stop and remove containers
if [ -f "$INSTALL_DIR/docker-compose.yml" ]; then
    echo "[1/5] Stopping Docker containers..."
    cd "$INSTALL_DIR"
    docker compose --profile discord-bridge --profile telegram-bridge down -v 2>/dev/null || true
    echo -e "       ${GREEN}[OK]${NC}"
fi

# Remove data
echo "[2/5] Removing data directory..."
rm -rf "$INSTALL_DIR/data"
echo -e "       ${GREEN}[OK]${NC}"

# Remove certbot certs and cron
echo "[3/5] Removing SSL certificates and renewal cron..."
DOMAIN=""
if [ -f "$INSTALL_DIR/.env" ]; then
    DOMAIN=$(grep "^DOMAIN=" "$INSTALL_DIR/.env" | cut -d= -f2)
fi
if [ -n "$DOMAIN" ] && [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
    certbot delete --cert-name "$DOMAIN" --non-interactive 2>/dev/null || true
fi
crontab -l 2>/dev/null | grep -v "matrix-discord-killer" | crontab - 2>/dev/null || true
echo -e "       ${GREEN}[OK]${NC}"

# Remove UFW rules
echo "[4/5] Removing firewall rules..."
if command -v ufw &>/dev/null; then
    ufw delete allow 80/tcp 2>/dev/null || true
    ufw delete allow 443/tcp 2>/dev/null || true
    ufw delete allow 8448/tcp 2>/dev/null || true
    ufw delete allow 3478/tcp 2>/dev/null || true
    ufw delete allow 3478/udp 2>/dev/null || true
    ufw delete allow 5349/tcp 2>/dev/null || true
    ufw delete allow 5349/udp 2>/dev/null || true
    ufw delete allow 49152:49200/udp 2>/dev/null || true
fi
echo -e "       ${GREEN}[OK]${NC}"

# Remove install directory
echo "[5/5] Removing $INSTALL_DIR..."
cd /
rm -rf "$INSTALL_DIR"
echo -e "       ${GREEN}[OK]${NC}"

echo ""
echo -e "${GREEN}Uninstall complete.${NC} All Matrix data has been destroyed."
echo "Docker images remain cached. Run 'docker image prune -a' to free disk space."
