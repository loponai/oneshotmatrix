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
        -e "s|__POSTGRES_PASSWORD__|${POSTGRES_PASSWORD}|g" \
        -e "s|__REGISTRATION_SHARED_SECRET__|${REGISTRATION_SHARED_SECRET}|g" \
        -e "s|__MACAROON_SECRET_KEY__|${MACAROON_SECRET_KEY}|g" \
        -e "s|__FORM_SECRET__|${FORM_SECRET}|g" \
        -e "s|__TURN_SHARED_SECRET__|${TURN_SHARED_SECRET}|g" \
        "$dst"
}

# ─── Pre-flight ──────────────────────────────────────────────────────

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Error: Must run as root.${NC}"
    exit 1
fi

echo ""
echo -e "${BOLD}  ╔══════════════════════════════════════════╗${NC}"
echo -e "${BOLD}  ║       matrix-discord-killer              ║${NC}"
echo -e "${BOLD}  ║   Self-hosted Matrix + Element stack     ║${NC}"
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

# ─── User prompts ────────────────────────────────────────────────────

echo -e "${BOLD}Configure your Matrix server:${NC}"
echo ""

# Domain
while true; do
    read -rp "  Domain name (e.g., chat.example.com): " DOMAIN
    if [[ "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]; then
        break
    fi
    echo -e "  ${RED}Invalid domain. Use format: sub.example.com${NC}"
done

# Email
while true; do
    read -rp "  Email for SSL certificates: " ACME_EMAIL
    if [[ "$ACME_EMAIL" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
        break
    fi
    echo -e "  ${RED}Invalid email address.${NC}"
done

# Admin password
while true; do
    read -rsp "  Admin account password (min 8 chars): " ADMIN_PASSWORD
    echo ""
    if [ ${#ADMIN_PASSWORD} -ge 8 ]; then
        break
    fi
    echo -e "  ${RED}Password must be at least 8 characters.${NC}"
done

# Bridges
echo ""
read -rp "  Install Discord bridge? (Y/n): " discord_choice
ENABLE_DISCORD=false
if [[ ! "$discord_choice" =~ ^[Nn]$ ]]; then
    ENABLE_DISCORD=true
fi

read -rp "  Install Telegram bridge? (Y/n): " telegram_choice
ENABLE_TELEGRAM=false
if [[ ! "$telegram_choice" =~ ^[Nn]$ ]]; then
    ENABLE_TELEGRAM=true
fi

echo ""
echo -e "${GREEN}Configuration:${NC}"
echo "  Domain:          $DOMAIN"
echo "  Email:           $ACME_EMAIL"
echo "  Discord bridge:  $ENABLE_DISCORD"
echo "  Telegram bridge: $ENABLE_TELEGRAM"
echo ""
read -rp "Proceed with installation? (Y/n): " proceed
if [[ "$proceed" =~ ^[Nn]$ ]]; then
    echo "Aborted."
    exit 0
fi

# ─── [1/11] Install dependencies ─────────────────────────────────────

step "Installing system dependencies..."

export DEBIAN_FRONTEND=noninteractive
if ! apt-get update -qq >/dev/null 2>&1; then
    fail "apt-get update failed. Check your internet connection and package sources."
fi
if ! apt-get install -y -qq curl wget openssl certbot ufw >/dev/null 2>&1; then
    fail "Failed to install system packages (curl, openssl, certbot, ufw)."
fi

# Docker
if ! command -v docker &>/dev/null; then
    if ! curl -fsSL https://get.docker.com | sh >/dev/null 2>&1; then
        fail "Docker installation failed. Install manually: https://docs.docker.com/engine/install/"
    fi
fi

# Verify docker compose plugin
if ! docker compose version &>/dev/null; then
    if ! apt-get install -y -qq docker-compose-plugin >/dev/null 2>&1; then
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
ufw allow 22/tcp >/dev/null 2>&1
ufw allow 80/tcp >/dev/null 2>&1
ufw allow 443/tcp >/dev/null 2>&1
ufw allow 8448/tcp >/dev/null 2>&1
ufw allow 3478/tcp >/dev/null 2>&1
ufw allow 3478/udp >/dev/null 2>&1
ufw allow 5349/tcp >/dev/null 2>&1
ufw allow 5349/udp >/dev/null 2>&1
ufw allow 49152:49200/udp >/dev/null 2>&1
ufw --force enable >/dev/null 2>&1 || true

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
