#!/usr/bin/env bash
# matrix-discord-killer uninstaller
set -euo pipefail

INSTALL_DIR="/opt/matrix-discord-killer"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Detect OS family
if [ -f /etc/os-release ]; then
    . /etc/os-release
    if [[ "$ID" == "rocky" || "$ID" == "rhel" || "$ID" == "centos" || "${ID_LIKE:-}" == *"rhel"* || "${ID_LIKE:-}" == *"fedora"* ]]; then
        OS_FAMILY="rhel"
    else
        OS_FAMILY="debian"
    fi
else
    OS_FAMILY="debian"
fi

fw_delete() {
    local rule="$1"
    if [ "$OS_FAMILY" = "rhel" ]; then
        firewall-cmd --permanent --zone=public --remove-port="$rule" >/dev/null 2>&1 || true
    else
        ufw delete allow "$rule" >/dev/null 2>&1 || true
    fi
}

fw_reload() {
    if [ "$OS_FAMILY" = "rhel" ]; then
        firewall-cmd --reload >/dev/null 2>&1 || true
    fi
}

echo ""
echo -e "${RED}  ╔══════════════════════════════════════════╗${NC}"
echo -e "${RED}  ║   matrix-discord-killer UNINSTALLER      ║${NC}"
echo -e "${RED}  ╚══════════════════════════════════════════╝${NC}"
echo ""

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Error: Must run as root.${NC}"
    exit 1
fi

# Detect platform
PLATFORM="matrix"
if [ -f "$INSTALL_DIR/.env" ]; then
    PLATFORM=$(grep "^PLATFORM=" "$INSTALL_DIR/.env" | cut -d= -f2) || true
    PLATFORM="${PLATFORM:-matrix}"
fi

echo -e "${YELLOW}WARNING: This will permanently destroy:${NC}"
echo "  - All Docker containers and volumes"
if [ "$PLATFORM" = "stoat" ]; then
    echo "  - All Stoat data (messages, media, accounts)"
    echo "  - MongoDB database"
    echo "  - MinIO file storage"
else
    echo "  - All Matrix data (messages, media, accounts)"
    echo "  - PostgreSQL database"
    echo "  - SSL certificates"
    echo "  - Coturn configuration"
fi
echo "  - Firewall rules added by the installer"
echo ""
read -rp "Type 'DELETE EVERYTHING' to confirm: " confirm

if [ "$confirm" != "DELETE EVERYTHING" ]; then
    echo "Aborted."
    exit 0
fi

echo ""

# Stop and remove containers
if [ "$PLATFORM" = "stoat" ]; then
    if [ -f "$INSTALL_DIR/docker-compose.stoat.yml" ]; then
        echo "[1/4] Stopping Docker containers..."
        cd "$INSTALL_DIR"
        docker compose -f docker-compose.stoat.yml down -v 2>/dev/null || true
        echo -e "       ${GREEN}[OK]${NC}"
    fi

    # Remove data
    echo "[2/4] Removing data directory..."
    rm -rf "$INSTALL_DIR/data"
    echo -e "       ${GREEN}[OK]${NC}"

    # No certbot for Stoat
    echo "[3/4] No SSL certificates to remove (Caddy auto-manages)..."
    echo -e "       ${GREEN}[OK]${NC}"

    # Remove firewall rules (Stoat only uses 80/443)
    echo "[4/4] Removing firewall rules..."
    fw_delete 80/tcp
    fw_delete 443/tcp
    fw_reload
    echo -e "       ${GREEN}[OK]${NC}"
else
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

    # Remove firewall rules
    echo "[4/5] Removing firewall rules..."
    fw_delete 80/tcp
    fw_delete 443/tcp
    fw_delete 8448/tcp
    fw_delete 3478/tcp
    fw_delete 3478/udp
    fw_delete 5349/tcp
    fw_delete 5349/udp
    fw_delete 49152:49200/udp
    fw_reload
    echo -e "       ${GREEN}[OK]${NC}"

    # Remove install directory (Matrix has extra step)
    echo "[5/5] Removing $INSTALL_DIR..."
    cd /
    rm -rf "$INSTALL_DIR"
    echo -e "       ${GREEN}[OK]${NC}"
fi

# Remove install directory (common for both, but Matrix already does it in 5/5)
if [ "$PLATFORM" = "stoat" ]; then
    cd /
    rm -rf "$INSTALL_DIR"
fi

echo ""
if [ "$PLATFORM" = "stoat" ]; then
    echo -e "${GREEN}Uninstall complete.${NC} All Stoat data has been destroyed."
else
    echo -e "${GREEN}Uninstall complete.${NC} All Matrix data has been destroyed."
fi
echo "Docker images remain cached. Run 'docker image prune -a' to free disk space."
