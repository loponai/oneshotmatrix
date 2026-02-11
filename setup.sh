#!/usr/bin/env bash
# matrix-discord-killer - Main setup script
# Run directly or via install.sh
set -euo pipefail

INSTALL_DIR="/opt/matrix-discord-killer"
DATA_DIR="$INSTALL_DIR/data"

# Restrict default file permissions (configs contain secrets)
umask 077

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Helpers ─────────────────────────────────────────────────────────

# OS detection (set by install.sh, fallback for standalone runs)
if [ -z "${OS_FAMILY:-}" ]; then
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
fi

step_count=0
total_steps=11

step() {
    step_count=$((step_count + 1))
    printf "\n${CYAN}[%2d/%d]${NC} %s" "$step_count" "$total_steps" "$1"
}

ok() {
    echo -e "  ${GREEN}[OK]${NC}"
}

fail() {
    echo -e "  ${RED}[FAIL]${NC}"
    echo -e "${RED}Error: $1${NC}"
    exit 1
}

generate_secret() {
    openssl rand -hex 32
}

template() {
    local src="$1" dst="$2"
    cp "$src" "$dst"
    sed -i \
        -e "s|__DOMAIN__|${DOMAIN}|g" \
        -e "s|__POSTGRES_PASSWORD__|${POSTGRES_PASSWORD:-}|g" \
        -e "s|__REGISTRATION_SHARED_SECRET__|${REGISTRATION_SHARED_SECRET:-}|g" \
        -e "s|__MACAROON_SECRET_KEY__|${MACAROON_SECRET_KEY:-}|g" \
        -e "s|__FORM_SECRET__|${FORM_SECRET:-}|g" \
        -e "s|__TURN_SHARED_SECRET__|${TURN_SHARED_SECRET:-}|g" \
        -e "s|__VAPID_PRIVATE_KEY__|${VAPID_PRIVATE_KEY:-}|g" \
        -e "s|__VAPID_PUBLIC_KEY__|${VAPID_PUBLIC_KEY:-}|g" \
        -e "s|__FILE_ENCRYPTION_KEY__|${FILE_ENCRYPTION_KEY:-}|g" \
        "$dst"
}

# ─── Package & firewall wrappers (Debian/RHEL) ──────────────────────

pkg_update() {
    if [ "$OS_FAMILY" = "debian" ]; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq >/dev/null 2>&1
    fi
    # dnf doesn't need a separate update step
}

pkg_install() {
    if [ "$OS_FAMILY" = "rhel" ]; then
        dnf install -y -q "$@" >/dev/null 2>&1
    else
        export DEBIAN_FRONTEND=noninteractive
        apt-get install -y -qq "$@" >/dev/null 2>&1
    fi
}

detect_ssh_port() {
    # Read the actual listening SSH port (handles Scala's port 6543)
    local port
    port=$(ss -tlnp 2>/dev/null | grep -E 'sshd|"ssh"' | awk '{print $4}' | grep -oE '[0-9]+$' | head -1)
    echo "${port:-22}"
}

fw_allow() {
    # Usage: fw_allow 80/tcp  OR  fw_allow 49152:49200/udp
    local rule="$1"
    if [ "$OS_FAMILY" = "rhel" ]; then
        firewall-cmd --permanent --zone=public --add-port="$rule" >/dev/null 2>&1 || true
    else
        ufw allow "$rule" >/dev/null 2>&1 || true
    fi
}

fw_enable() {
    if [ "$OS_FAMILY" = "rhel" ]; then
        systemctl enable --now firewalld >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
    else
        ufw --force enable >/dev/null 2>&1 || true
    fi
}

fw_delete() {
    # Usage: fw_delete 80/tcp
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
    # ufw applies changes immediately, no reload needed
}

# ─── Pre-flight ──────────────────────────────────────────────────────

# Reopen stdin for interactive prompts (curl pipes eat stdin in install.sh)
exec </dev/tty 2>/dev/null || true

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Error: Must run as root.${NC}"
    exit 1
fi

echo ""
echo -e "${BOLD}  ╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}  ║       matrix-discord-killer              ║${NC}"
echo -e "${BOLD}  ║   Self-hosted chat — your server         ║${NC}"
echo -e "${BOLD}  ╚══════════════════════════════════════════╝${NC}"
echo ""

# Check if already configured
if [ -f "$INSTALL_DIR/.env" ]; then
    echo -e "${YELLOW}Existing installation detected at $INSTALL_DIR${NC}"
    read -rp "Reconfigure and overwrite? (y/N): " overwrite
    if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# ─── Platform selection ──────────────────────────────────────────────

echo -e "${BOLD}Which chat platform do you want to install?${NC}"
echo ""
echo "  [1] Matrix/Element  - Federated, E2EE, Discord/Telegram bridges"
echo "  [2] Stoat (Revolt)  - Modern UI, simple setup, no federation"
echo ""

while true; do
    read -rp "Type 1 or 2, then press Enter: " platform_choice
    case "$platform_choice" in
        1) PLATFORM="matrix"; break ;;
        2) PLATFORM="stoat"; break ;;
        *) echo -e "  ${RED}Please enter 1 or 2.${NC}" ;;
    esac
done

echo ""

if [ "$PLATFORM" = "matrix" ]; then
    total_steps=11
else
    total_steps=7
fi

# ─── User prompts ────────────────────────────────────────────────────

echo -e "${BOLD}Now we need a few details to set up your server.${NC}"
echo ""

# Domain
echo "Enter the domain name you pointed to this server's IP address."
echo -e "  ${CYAN}Example: chat.example.com${NC}"
echo ""
while true; do
    read -rp "Your domain: " DOMAIN
    if [[ "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
        break
    fi
    echo -e "  ${RED}That doesn't look right. Enter a domain like: chat.example.com${NC}"
done

echo ""

# Email
echo "Enter your email address (used for free SSL certificate from Let's Encrypt)."
echo -e "  ${CYAN}This is only used for certificate expiry warnings — no spam.${NC}"
echo ""
while true; do
    read -rp "Your email: " ACME_EMAIL
    if [[ "$ACME_EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
        break
    fi
    echo -e "  ${RED}That doesn't look like an email address. Try again.${NC}"
done

# Matrix-only prompts
if [ "$PLATFORM" = "matrix" ]; then
    echo ""
    echo "Choose a password for the admin account (@admin on your server)."
    echo -e "  ${CYAN}Must be at least 8 characters. You'll use this to log in.${NC}"
    echo ""
    while true; do
        read -rsp "Admin password (typing is hidden): " ADMIN_PASSWORD
        echo ""
        if [ ${#ADMIN_PASSWORD} -ge 8 ]; then
            break
        fi
        echo -e "  ${RED}Too short — must be at least 8 characters. Try again.${NC}"
    done

    # Bridges
    echo ""
    echo "Bridges let you read Discord/Telegram messages inside your chat client."
    echo ""
    read -rp "Install Discord bridge? (Y/n): " discord_choice
    ENABLE_DISCORD=false
    if [[ ! "$discord_choice" =~ ^[Nn]$ ]]; then
        ENABLE_DISCORD=true
    fi

    read -rp "Install Telegram bridge? (Y/n): " telegram_choice
    ENABLE_TELEGRAM=false
    if [[ ! "$telegram_choice" =~ ^[Nn]$ ]]; then
        ENABLE_TELEGRAM=true
    fi
fi

echo ""
echo -e "${GREEN}Here's what we'll install:${NC}"
echo "  Platform:        $PLATFORM"
echo "  Domain:          $DOMAIN"
echo "  Email:           $ACME_EMAIL"
if [ "$PLATFORM" = "matrix" ]; then
    echo "  Discord bridge:  $ENABLE_DISCORD"
    echo "  Telegram bridge: $ENABLE_TELEGRAM"
fi
echo ""
read -rp "Look good? Press Enter to install, or type N to cancel: " proceed
if [[ "$proceed" =~ ^[Nn]$ ]]; then
    echo "Aborted."
    exit 0
fi

# ══════════════════════════════════════════════════════════════════════
# MATRIX PATH
# ══════════════════════════════════════════════════════════════════════

if [ "$PLATFORM" = "matrix" ]; then

# ─── [1/11] Install dependencies ─────────────────────────────────────

step "Installing system dependencies..."

if ! pkg_update; then
    fail "Package update failed. Check your internet connection and package sources."
fi

if [ "$OS_FAMILY" = "rhel" ]; then
    if ! pkg_install curl wget openssl certbot firewalld; then
        fail "Failed to install system packages."
    fi
else
    if ! pkg_install curl wget openssl certbot ufw; then
        fail "Failed to install system packages."
    fi
fi

# Docker
if ! command -v docker &>/dev/null; then
    if ! curl -fsSL https://get.docker.com | sh >/dev/null 2>&1; then
        fail "Docker installation failed. Install manually: https://docs.docker.com/engine/install/"
    fi
fi

# Verify docker compose plugin
if ! docker compose version &>/dev/null; then
    if ! pkg_install docker-compose-plugin; then
        fail "Docker Compose plugin installation failed."
    fi
fi

ok

# ─── [2/11] Generate secrets ─────────────────────────────────────────

step "Generating secrets..."

# On re-run, preserve existing secrets to avoid breaking the database
if [ -f "$INSTALL_DIR/.env" ]; then
    POSTGRES_PASSWORD=$(grep "^POSTGRES_PASSWORD=" "$INSTALL_DIR/.env" | cut -d= -f2)
    REGISTRATION_SHARED_SECRET=$(grep "^SYNAPSE_REGISTRATION_SHARED_SECRET=" "$INSTALL_DIR/.env" | cut -d= -f2)
    MACAROON_SECRET_KEY=$(grep "^SYNAPSE_MACAROON_SECRET_KEY=" "$INSTALL_DIR/.env" | cut -d= -f2)
    FORM_SECRET=$(grep "^SYNAPSE_FORM_SECRET=" "$INSTALL_DIR/.env" | cut -d= -f2)
    TURN_SHARED_SECRET=$(grep "^TURN_SHARED_SECRET=" "$INSTALL_DIR/.env" | cut -d= -f2)
fi

# Generate any missing secrets (first run or incomplete .env)
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-$(generate_secret)}"
REGISTRATION_SHARED_SECRET="${REGISTRATION_SHARED_SECRET:-$(generate_secret)}"
MACAROON_SECRET_KEY="${MACAROON_SECRET_KEY:-$(generate_secret)}"
FORM_SECRET="${FORM_SECRET:-$(generate_secret)}"
TURN_SHARED_SECRET="${TURN_SHARED_SECRET:-$(generate_secret)}"

ok

# ─── [3/11] Create directory structure ───────────────────────────────

step "Creating directory structure..."

mkdir -p \
    "$DATA_DIR/synapse/media_store" \
    "$DATA_DIR/postgres" \
    "$DATA_DIR/element" \
    "$DATA_DIR/coturn" \
    "$DATA_DIR/nginx" \
    "$DATA_DIR/certbot/www" \
    "$DATA_DIR/mautrix-discord" \
    "$DATA_DIR/mautrix-telegram"

ok

# ─── [4/11] Write .env file ──────────────────────────────────────────

step "Writing environment file..."

cat > "$INSTALL_DIR/.env" <<ENVEOF
PLATFORM=matrix
DOMAIN=$DOMAIN
ACME_EMAIL=$ACME_EMAIL
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
SYNAPSE_REGISTRATION_SHARED_SECRET=$REGISTRATION_SHARED_SECRET
SYNAPSE_MACAROON_SECRET_KEY=$MACAROON_SECRET_KEY
SYNAPSE_FORM_SECRET=$FORM_SECRET
TURN_SHARED_SECRET=$TURN_SHARED_SECRET
ENABLE_DISCORD_BRIDGE=$ENABLE_DISCORD
ENABLE_TELEGRAM_BRIDGE=$ENABLE_TELEGRAM
ENVEOF

chmod 600 "$INSTALL_DIR/.env"

ok

# ─── [5/11] Template configuration files ─────────────────────────────

step "Generating configuration files..."

# Synapse homeserver.yaml
template "$INSTALL_DIR/templates/homeserver.yaml.template" "$DATA_DIR/synapse/homeserver.yaml"

# Add bridge registration lines if enabled
BRIDGE_LINES=""
if [ "$ENABLE_DISCORD" = true ]; then
    BRIDGE_LINES="${BRIDGE_LINES}app_service_config_files:\n"
    BRIDGE_LINES="${BRIDGE_LINES}  - /data/discord-registration.yaml\n"
    if [ "$ENABLE_TELEGRAM" = true ]; then
        BRIDGE_LINES="${BRIDGE_LINES}  - /data/telegram-registration.yaml\n"
    fi
elif [ "$ENABLE_TELEGRAM" = true ]; then
    BRIDGE_LINES="app_service_config_files:\n"
    BRIDGE_LINES="${BRIDGE_LINES}  - /data/telegram-registration.yaml\n"
fi

if [ -n "$BRIDGE_LINES" ]; then
    sed -i "s|# __BRIDGE_REGISTRATIONS__|${BRIDGE_LINES}|" "$DATA_DIR/synapse/homeserver.yaml"
else
    sed -i "/# __BRIDGE_REGISTRATIONS__/d" "$DATA_DIR/synapse/homeserver.yaml"
fi

# Synapse log config
cp "$INSTALL_DIR/templates/log.config.template" "$DATA_DIR/synapse/log.config"

# Synapse runs as UID 991 -- set ownership before generating signing key
chown -R 991:991 "$DATA_DIR/synapse"

# Synapse signing key - generate preserves backups of our configs
if [ ! -f "$DATA_DIR/synapse/${DOMAIN}.signing.key" ]; then
    cp "$DATA_DIR/synapse/homeserver.yaml" "$DATA_DIR/synapse/homeserver.yaml.ours"
    cp "$DATA_DIR/synapse/log.config" "$DATA_DIR/synapse/log.config.ours"
    docker run --rm \
        -v "$DATA_DIR/synapse:/data" \
        -e SYNAPSE_SERVER_NAME="$DOMAIN" \
        -e SYNAPSE_REPORT_STATS=no \
        matrixdotorg/synapse:latest generate 2>/dev/null || true
    # Restore our templated configs (generate overwrites them)
    mv -f "$DATA_DIR/synapse/homeserver.yaml.ours" "$DATA_DIR/synapse/homeserver.yaml"
    mv -f "$DATA_DIR/synapse/log.config.ours" "$DATA_DIR/synapse/log.config"
    if [ ! -f "$DATA_DIR/synapse/${DOMAIN}.signing.key" ]; then
        fail "Failed to generate Synapse signing key. Check Docker connectivity."
    fi
fi

# Element config
template "$INSTALL_DIR/templates/element-config.json.template" "$DATA_DIR/element/config.json"

# Nginx configs
template "$INSTALL_DIR/templates/nginx.conf.template" "$DATA_DIR/nginx/nginx.conf"
template "$INSTALL_DIR/templates/matrix.conf.template" "$DATA_DIR/nginx/matrix.conf"

# Coturn
template "$INSTALL_DIR/templates/turnserver.conf.template" "$DATA_DIR/coturn/turnserver.conf"

ok

# ─── [6/11] Obtain SSL certificate ───────────────────────────────────

step "Obtaining SSL certificate from Let's Encrypt..."

# Stop anything on port 80
systemctl stop nginx 2>/dev/null || true
docker compose -f "$INSTALL_DIR/docker-compose.yml" down 2>/dev/null || true

certbot certonly \
    --standalone \
    --non-interactive \
    --agree-tos \
    --email "$ACME_EMAIL" \
    -d "$DOMAIN" \
    --preferred-challenges http \
    2>/dev/null

if [ ! -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]; then
    fail "SSL certificate generation failed. Ensure DNS A record for ${DOMAIN} points to this server."
fi

# Patch certbot renewal config to use webroot (standalone only works when nginx is down)
RENEWAL_CONF="/etc/letsencrypt/renewal/${DOMAIN}.conf"
if [ -f "$RENEWAL_CONF" ]; then
    sed -i "s|authenticator = standalone|authenticator = webroot|" "$RENEWAL_CONF"
    if ! grep -q "webroot_path" "$RENEWAL_CONF"; then
        sed -i "/\[renewalparams\]/a webroot_path = $DATA_DIR/certbot/www" "$RENEWAL_CONF"
    fi
    # Add webroot map section if missing
    if ! grep -q "\[\[webroot\]\]" "$RENEWAL_CONF"; then
        printf "\n[[webroot]]\n${DOMAIN} = ${DATA_DIR}/certbot/www\n" >> "$RENEWAL_CONF"
    fi
fi

ok

# ─── [7/11] Configure firewall ───────────────────────────────────────

step "Configuring firewall..."

# Preserve SSH access before enabling firewall
SSH_PORT=$(detect_ssh_port)
fw_allow "${SSH_PORT}/tcp"
fw_allow 80/tcp
fw_allow 443/tcp
fw_allow 8448/tcp
fw_allow 3478/tcp
fw_allow 3478/udp
fw_allow 5349/tcp
fw_allow 5349/udp
fw_allow 49152:49200/udp
fw_enable

ok

# ─── [8/11] Setup bridge configs ─────────────────────────────────────

step "Configuring bridges..."

if [ "$ENABLE_DISCORD" = true ]; then
    # Bridge containers run as UID 1337 - must own dir before generating config
    chown -R 1337:1337 "$DATA_DIR/mautrix-discord"
    # Generate default config
    docker run --rm \
        -v "$DATA_DIR/mautrix-discord:/data" \
        dock.mau.dev/mautrix/discord:latest 2>/dev/null || true

    if [ -f "$DATA_DIR/mautrix-discord/config.yaml" ]; then
        # Patch homeserver address/domain using broad patterns that match any default value
        sed -i \
            -e '/^\s*address:.*\(localhost\|example\)/{s|address:.*|address: http://synapse:8008|}' \
            -e '/^\s*domain:.*\(localhost\|example\)/{s|domain:.*|domain: '"${DOMAIN}"'|}' \
            -e 's|address: http://localhost:29334|address: http://mautrix-discord:29334|' \
            "$DATA_DIR/mautrix-discord/config.yaml"
        # sed -i runs as root; restore ownership so container can read
        chown -R 1337:1337 "$DATA_DIR/mautrix-discord"

        # Re-run to generate registration.yaml with patched config
        docker run --rm \
            -v "$DATA_DIR/mautrix-discord:/data" \
            dock.mau.dev/mautrix/discord:latest 2>/dev/null || true
    fi

    # Copy registration to synapse data dir
    if [ -f "$DATA_DIR/mautrix-discord/registration.yaml" ]; then
        cp "$DATA_DIR/mautrix-discord/registration.yaml" "$DATA_DIR/synapse/discord-registration.yaml"
    fi
fi

if [ "$ENABLE_TELEGRAM" = true ]; then
    # Bridge containers run as UID 1337 - must own dir before generating config
    chown -R 1337:1337 "$DATA_DIR/mautrix-telegram"
    # Generate default config
    docker run --rm \
        -v "$DATA_DIR/mautrix-telegram:/data" \
        dock.mau.dev/mautrix/telegram:latest 2>/dev/null || true

    if [ -f "$DATA_DIR/mautrix-telegram/config.yaml" ]; then
        # Patch homeserver address/domain using broad patterns
        sed -i \
            -e '/^\s*address:.*\(localhost\|example\)/{s|address:.*|address: http://synapse:8008|}' \
            -e '/^\s*domain:.*\(localhost\|example\)/{s|domain:.*|domain: '"${DOMAIN}"'|}' \
            -e 's|address: http://localhost:29317|address: http://mautrix-telegram:29317|' \
            "$DATA_DIR/mautrix-telegram/config.yaml"
        # sed -i runs as root; restore ownership so container can read
        chown -R 1337:1337 "$DATA_DIR/mautrix-telegram"

        # Re-run to generate registration.yaml with patched config
        docker run --rm \
            -v "$DATA_DIR/mautrix-telegram:/data" \
            dock.mau.dev/mautrix/telegram:latest 2>/dev/null || true
    fi

    if [ -f "$DATA_DIR/mautrix-telegram/registration.yaml" ]; then
        cp "$DATA_DIR/mautrix-telegram/registration.yaml" "$DATA_DIR/synapse/telegram-registration.yaml"
    fi
fi

ok

# ─── [9/11] Set permissions ──────────────────────────────────────────

step "Setting file permissions..."

# Synapse runs as UID 991 inside the container
chown -R 991:991 "$DATA_DIR/synapse"
# Postgres runs as UID 999
chown -R 999:999 "$DATA_DIR/postgres"
# Element config must be readable by nginx worker (UID 101)
chmod 644 "$DATA_DIR/element/config.json"
# Nginx configs must be readable
chmod 644 "$DATA_DIR/nginx/nginx.conf" "$DATA_DIR/nginx/matrix.conf"
# Mautrix bridges run as UID 1337
[ -d "$DATA_DIR/mautrix-discord" ] && chown -R 1337:1337 "$DATA_DIR/mautrix-discord"
[ -d "$DATA_DIR/mautrix-telegram" ] && chown -R 1337:1337 "$DATA_DIR/mautrix-telegram"
# Certbot challenge dir must be readable by nginx
chmod 755 "$DATA_DIR/certbot" "$DATA_DIR/certbot/www"

ok

# ─── [10/11] Start the stack ─────────────────────────────────────────

step "Starting Matrix stack (this may take a few minutes on first run)..."

cd "$INSTALL_DIR"

# Build compose profiles argument
PROFILES=""
if [ "$ENABLE_DISCORD" = true ]; then
    PROFILES="$PROFILES --profile discord-bridge"
fi
if [ "$ENABLE_TELEGRAM" = true ]; then
    PROFILES="$PROFILES --profile telegram-bridge"
fi

COMPOSE_EXIT=0
docker compose $PROFILES up -d 2>&1 || COMPOSE_EXIT=$?
if [ "$COMPOSE_EXIT" -ne 0 ]; then
    fail "Docker Compose failed to start (exit $COMPOSE_EXIT). Check: docker compose logs"
fi

# Wait for Synapse to be ready
echo -n "  Waiting for Synapse..."
for i in $(seq 1 60); do
    if docker compose exec -T synapse curl -sf http://localhost:8008/health >/dev/null 2>&1; then
        break
    fi
    if [ "$i" -eq 60 ]; then
        fail "Synapse failed to start within 120 seconds. Check: docker compose logs synapse"
    fi
    sleep 2
done

ok

# ─── [11/11] Create admin account ────────────────────────────────────

step "Creating admin account..."

# -c provides shared secret for auth, -p sets the user's password
REGISTER_EXIT=0
REGISTER_OUTPUT=$(docker compose exec -T synapse register_new_matrix_user \
    -u admin \
    -p "$ADMIN_PASSWORD" \
    -a \
    -c /data/homeserver.yaml \
    http://localhost:8008 2>&1) || REGISTER_EXIT=$?

if [ "$REGISTER_EXIT" -eq 0 ]; then
    ok
elif echo "$REGISTER_OUTPUT" | grep -qi "already taken\|already exists\|in use"; then
    echo -e "  ${YELLOW}[SKIP]${NC} Admin account already exists"
else
    echo -e "  ${RED}[WARN]${NC} Could not create admin account. Create manually after install:"
    echo "         cd $INSTALL_DIR && docker compose exec synapse register_new_matrix_user -c /data/homeserver.yaml"
fi

# ─── Finalize: certificate auto-renewal ──────────────────────────────

# Certbot cron for renewal (webroot mode using nginx)
# Add cert renewal cron if not already present
CRON_LINE="0 3 * * * certbot renew --deploy-hook 'cd $INSTALL_DIR && docker compose exec -T nginx nginx -s reload && docker compose restart coturn' --quiet # matrix-discord-killer"
(crontab -l 2>/dev/null | grep -v "# matrix-discord-killer" || true; echo "$CRON_LINE") | crontab -

# ─── Save credentials ───────────────────────────────────────────────

CRED_FILE="$INSTALL_DIR/credentials.txt"
GENERATED_AT=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
cat > "$CRED_FILE" <<CREDEOF
matrix-discord-killer credentials
Generated: $GENERATED_AT
═══════════════════════════════════════════════

Platform:            Matrix/Element
Domain:              $DOMAIN
Element Web:         https://$DOMAIN
Admin Account:       @admin:$DOMAIN
Admin Password:      $ADMIN_PASSWORD

PostgreSQL Password: $POSTGRES_PASSWORD
Synapse Reg Secret:  $REGISTRATION_SHARED_SECRET
Synapse Macaroon:    $MACAROON_SECRET_KEY
TURN Shared Secret:  $TURN_SHARED_SECRET

Discord Bridge:      $ENABLE_DISCORD
Telegram Bridge:     $ENABLE_TELEGRAM

Federation Test:     https://federationtester.matrix.org/#$DOMAIN
CREDEOF

chmod 600 "$CRED_FILE"

# ─── Summary ─────────────────────────────────────────────────────────

echo ""
echo ""
echo -e "${GREEN}  ╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}  ║       Installation Complete!             ║${NC}"
echo -e "${GREEN}  ╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Element Web:${NC}      https://${DOMAIN}"
echo -e "  ${BOLD}Admin Account:${NC}    @admin:${DOMAIN}"
echo -e "  ${BOLD}Admin Password:${NC}   (as entered above)"

if [ "$ENABLE_DISCORD" = true ]; then
    echo -e "  ${BOLD}Discord Bridge:${NC}   ${GREEN}Active${NC} - DM @discordbot:${DOMAIN} to login"
fi
if [ "$ENABLE_TELEGRAM" = true ]; then
    echo -e "  ${BOLD}Telegram Bridge:${NC}  ${GREEN}Active${NC} - DM @telegrambot:${DOMAIN} to login"
fi

echo ""
echo -e "  ${BOLD}Federation Test:${NC}  https://federationtester.matrix.org/#${DOMAIN}"
echo -e "  ${BOLD}Credentials:${NC}      $CRED_FILE"
echo ""
echo -e "  ${YELLOW}Tip:${NC} Invite friends by sharing: https://${DOMAIN}"
echo -e "  ${YELLOW}Note:${NC} Public registration is disabled. Create accounts with:"
echo -e "        cd $INSTALL_DIR && docker compose exec synapse register_new_matrix_user -c /data/homeserver.yaml"
echo ""
echo -e "  ─────────────────────────────────────────────"
echo -e "  ${CYAN}Need a VPS? Get \$200 free credit:${NC}"
echo -e "  https://your-affiliate-link-here.example.com"
echo -e "  ─────────────────────────────────────────────"
echo ""

# ══════════════════════════════════════════════════════════════════════
# STOAT PATH
# ══════════════════════════════════════════════════════════════════════

else

# ─── [1/7] Install dependencies ──────────────────────────────────────

step "Installing system dependencies..."

if ! pkg_update; then
    fail "Package update failed. Check your internet connection and package sources."
fi

if [ "$OS_FAMILY" = "rhel" ]; then
    if ! pkg_install curl openssl firewalld; then
        fail "Failed to install system packages."
    fi
else
    if ! pkg_install curl openssl ufw; then
        fail "Failed to install system packages."
    fi
fi

# Docker
if ! command -v docker &>/dev/null; then
    if ! curl -fsSL https://get.docker.com | sh >/dev/null 2>&1; then
        fail "Docker installation failed. Install manually: https://docs.docker.com/engine/install/"
    fi
fi

# Verify docker compose plugin
if ! docker compose version &>/dev/null; then
    if ! pkg_install docker-compose-plugin; then
        fail "Docker Compose plugin installation failed."
    fi
fi

ok

# ─── [2/7] Generate secrets ─────────────────────────────────────────

step "Generating secrets..."

# On re-run, preserve existing secrets
if [ -f "$INSTALL_DIR/.env" ]; then
    VAPID_PRIVATE_KEY=$(grep "^VAPID_PRIVATE_KEY=" "$INSTALL_DIR/.env" | cut -d= -f2) || true
    VAPID_PUBLIC_KEY=$(grep "^VAPID_PUBLIC_KEY=" "$INSTALL_DIR/.env" | cut -d= -f2) || true
    FILE_ENCRYPTION_KEY=$(grep "^FILE_ENCRYPTION_KEY=" "$INSTALL_DIR/.env" | cut -d= -f2) || true
fi

# Generate VAPID keys if missing
if [ -z "${VAPID_PRIVATE_KEY:-}" ] || [ -z "${VAPID_PUBLIC_KEY:-}" ]; then
    VAPID_TEMP=$(mktemp)
    openssl ecparam -name prime256v1 -genkey -noout -out "$VAPID_TEMP" 2>/dev/null
    VAPID_PRIVATE_KEY=$(base64 < "$VAPID_TEMP" | tr -d '\n' | tr -d '=')
    VAPID_PUBLIC_KEY=$(openssl ec -in "$VAPID_TEMP" -outform DER 2>/dev/null | tail -c 65 | base64 | tr '/+' '_-' | tr -d '\n' | tr -d '=')
    rm -f "$VAPID_TEMP"
fi

FILE_ENCRYPTION_KEY="${FILE_ENCRYPTION_KEY:-$(openssl rand -base64 32)}"

ok

# ─── [3/7] Create directory structure ────────────────────────────────

step "Creating directory structure..."

mkdir -p \
    "$DATA_DIR/db" \
    "$DATA_DIR/rabbit" \
    "$DATA_DIR/minio" \
    "$DATA_DIR/caddy-data" \
    "$DATA_DIR/caddy-config"

ok

# ─── [4/7] Write configuration files ────────────────────────────────

step "Writing configuration files..."

# .env
cat > "$INSTALL_DIR/.env" <<ENVEOF
PLATFORM=stoat
COMPOSE_FILE=docker-compose.stoat.yml
DOMAIN=$DOMAIN
ACME_EMAIL=$ACME_EMAIL
VAPID_PRIVATE_KEY=$VAPID_PRIVATE_KEY
VAPID_PUBLIC_KEY=$VAPID_PUBLIC_KEY
FILE_ENCRYPTION_KEY=$FILE_ENCRYPTION_KEY
ENVEOF

chmod 600 "$INSTALL_DIR/.env"

# Revolt.toml
template "$INSTALL_DIR/templates/revolt.toml.template" "$INSTALL_DIR/Revolt.toml"

# .env.web (Caddy hostname + web client API URL)
template "$INSTALL_DIR/templates/stoat-env.web.template" "$INSTALL_DIR/.env.web"

# Caddyfile
cp "$INSTALL_DIR/templates/Caddyfile.template" "$INSTALL_DIR/Caddyfile"

ok

# ─── [5/7] Configure firewall ───────────────────────────────────────

step "Configuring firewall..."

SSH_PORT=$(detect_ssh_port)
fw_allow "${SSH_PORT}/tcp"
fw_allow 80/tcp
fw_allow 443/tcp
fw_enable

ok

# ─── [6/7] Start Stoat stack ────────────────────────────────────────

step "Starting Stoat stack (this may take a few minutes on first run)..."

cd "$INSTALL_DIR"

COMPOSE_EXIT=0
docker compose up -d 2>&1 || COMPOSE_EXIT=$?
if [ "$COMPOSE_EXIT" -ne 0 ]; then
    fail "Docker Compose failed to start (exit $COMPOSE_EXIT). Check: docker compose logs"
fi

ok

# ─── [7/7] Verify services ──────────────────────────────────────────

step "Verifying services..."

echo -n "  Waiting for API..."
for i in $(seq 1 60); do
    if curl -sf "http://localhost:14702/" >/dev/null 2>&1; then
        break
    fi
    if [ "$i" -eq 60 ]; then
        fail "Stoat API failed to start within 120 seconds. Check: docker compose logs api"
    fi
    sleep 2
done

ok

# ─── Save credentials ───────────────────────────────────────────────

CRED_FILE="$INSTALL_DIR/credentials.txt"
GENERATED_AT=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
cat > "$CRED_FILE" <<CREDEOF
matrix-discord-killer credentials
Generated: $GENERATED_AT
═══════════════════════════════════════════════

Platform:            Stoat (Revolt)
Domain:              $DOMAIN
Web Client:          https://$DOMAIN

Register your account at the URL above.
The first registered user becomes the server owner.

VAPID Public Key:    $VAPID_PUBLIC_KEY
CREDEOF

chmod 600 "$CRED_FILE"

# ─── Summary ─────────────────────────────────────────────────────────

echo ""
echo ""
echo -e "${GREEN}  ╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}  ║       Installation Complete!             ║${NC}"
echo -e "${GREEN}  ╚══════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Stoat:${NC}            https://${DOMAIN}"
echo -e "  ${BOLD}Register:${NC}         Create your account at the URL above"
echo -e "  ${BOLD}Credentials:${NC}      $CRED_FILE"
echo ""
echo -e "  ${YELLOW}Tip:${NC} The first registered account becomes the server owner."
echo -e "  ${YELLOW}Note:${NC} Caddy handles SSL automatically — no certbot needed."
echo ""
echo -e "  ─────────────────────────────────────────────"
echo -e "  ${CYAN}Need a VPS? Get \$200 free credit:${NC}"
echo -e "  https://your-affiliate-link-here.example.com"
echo -e "  ─────────────────────────────────────────────"
echo ""

fi
