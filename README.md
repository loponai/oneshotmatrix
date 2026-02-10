# matrix-discord-killer

**Deploy a self-hosted chat platform in one command.** Choose between Matrix/Element (federated, E2EE, bridges) or Stoat/Revolt (modern UI, simple setup).

```bash
curl -fsSL https://raw.githubusercontent.com/loponai/oneshotmatrix/main/install.sh | sudo bash
```

---

## What You Get

Pick one platform per server during setup:

### Matrix/Element
- **Element Web** - Modern chat UI at your domain root
- **Synapse** - Matrix homeserver with federation
- **PostgreSQL** - Production database (not SQLite)
- **Coturn** - TURN/STUN server for voice and video calls
- **Nginx** - Reverse proxy with automatic HTTPS and rate limiting
- **Discord Bridge** (optional) - Access Discord servers from Element
- **Telegram Bridge** (optional) - Access Telegram chats from Element

### Stoat (Revolt)
- **Stoat Web Client** - Discord-like modern chat UI
- **Revolt API Server** - Rust backend with MongoDB
- **Bonfire** - Real-time WebSocket events
- **Autumn** - File upload server with MinIO S3 storage
- **January** - URL metadata and image proxy
- **Caddy** - Reverse proxy with automatic HTTPS (zero config)
- **Push Notifications** - Built-in web push support

## Requirements

- A fresh **Ubuntu 22.04+** or **Debian 12+** VPS (1GB+ RAM, 2GB+ recommended)
- A **domain name** with DNS pointed to your server
- **Root access**

> Need a VPS? [Get $200 free credit →](https://your-affiliate-link-here.example.com)

## DNS Setup

Before running the installer, create a DNS **A record** pointing your domain to your server's IP:

| Type | Name | Value |
|------|------|-------|
| A | chat.example.com | YOUR_SERVER_IP |

Wait for DNS propagation (usually 5-15 minutes) before installing.

> **Stoat note:** No federation, so only one A record is needed. No TURN/STUN ports required.

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/loponai/oneshotmatrix/main/install.sh | sudo bash
```

You'll be prompted for:
1. **Platform** - Matrix/Element or Stoat (Revolt)
2. **Domain name** - Your domain with DNS configured
3. **Email** - For SSL certificates
4. **Admin password** - (Matrix only) For the `@admin` account
5. **Bridge selection** - (Matrix only) Optional Discord and Telegram bridges

The installer handles everything: Docker, SSL, firewall, configuration.

## Architecture

### Matrix/Element
```
Internet → Nginx (80/443/8448)
              ├→ Element Web (/)
              ├→ Synapse (/_matrix/)
              │    └→ PostgreSQL
              ├→ Coturn (voice/video, host networking)
              ├→ mautrix-discord (optional)
              └→ mautrix-telegram (optional)
```

| Port | Purpose |
|------|---------|
| 80 | HTTP → HTTPS redirect + ACME challenges |
| 443 | Element Web + Synapse client API |
| 8448 | Matrix federation |
| 3478 | TURN (TCP/UDP) |
| 5349 | TURNS (TCP/UDP) |
| 49152-49200 | TURN relay media (UDP) |

### Stoat (Revolt)
```
Internet → Caddy (80/443)
              ├→ Web client (/)
              ├→ API server (/api)
              ├→ Bonfire WebSocket (/ws)
              ├→ Autumn file server (/autumn)
              ├→ January metadata proxy (/january)
              ├→ Gifbox (/gifbox)
              ├→ Crond, Pushd (background)
              └→ MongoDB, Redis, RabbitMQ, MinIO
```

| Port | Purpose |
|------|---------|
| 80 | HTTP → HTTPS redirect (Caddy auto-HTTPS) |
| 443 | All services via Caddy reverse proxy |

## Using Bridges (Matrix only)

### Discord Bridge

After installation, open Element and start a DM with `@discordbot:yourdomain.com`:

```
!discord login
```

Follow the prompts to connect your Discord account. Your Discord servers will appear as Matrix rooms.

### Telegram Bridge

Start a DM with `@telegrambot:yourdomain.com`:

```
!tg login
```

Enter your phone number and verification code. Your Telegram chats will sync to Matrix.

## Managing Users

### Matrix
Public registration is disabled by default. Create accounts manually:

```bash
cd /opt/matrix-discord-killer
docker compose exec synapse register_new_matrix_user -c /data/homeserver.yaml
```

### Stoat
Open the web client and register. The first registered account becomes the server owner.

## Troubleshooting

### Check service status
```bash
cd /opt/matrix-discord-killer
docker compose ps
docker compose logs           # All services
```

### Matrix-specific

**Federation not working:**
1. Check DNS: `dig A yourdomain.com`
2. Test: https://federationtester.matrix.org
3. Verify port 8448 is open: `ufw status`

**Voice/video calls failing:**
1. Check Coturn: `docker compose logs coturn`
2. Verify TURN ports are open: `ufw status`
3. Test from Element: Settings → Voice & Video → Test

**SSL certificate issues:**
```bash
certbot renew --webroot -w /opt/matrix-discord-killer/data/certbot/www
cd /opt/matrix-discord-killer && docker compose restart nginx coturn
```

### Stoat-specific

**Web client not loading:**
1. Check Caddy: `docker compose logs caddy`
2. Check API: `docker compose logs api`
3. Verify DNS A record resolves to your server

**File uploads failing:**
1. Check MinIO: `docker compose logs minio`
2. Check Autumn: `docker compose logs autumn`
3. Verify createbuckets ran: `docker compose logs createbuckets`

**API returning errors:**
1. Check MongoDB: `docker compose logs database`
2. Check Redis: `docker compose logs redis`
3. Check RabbitMQ: `docker compose logs rabbit`

### View credentials
```bash
cat /opt/matrix-discord-killer/credentials.txt
```

## Uninstall

```bash
sudo /opt/matrix-discord-killer/uninstall.sh
```

This permanently destroys all data including messages, accounts, and media.

## Files

```
/opt/matrix-discord-killer/
├── docker-compose.yml          # Matrix stack
├── docker-compose.stoat.yml    # Stoat stack
├── .env                        # Generated secrets (chmod 600)
├── credentials.txt             # Login details (chmod 600)
├── setup.sh
├── uninstall.sh
├── templates/                  # Config templates
│   ├── homeserver.yaml.template
│   ├── element-config.json.template
│   ├── nginx.conf.template
│   ├── matrix.conf.template
│   ├── turnserver.conf.template
│   ├── log.config.template
│   ├── revolt.toml.template
│   ├── stoat-env.web.template
│   └── Caddyfile.template
├── Revolt.toml                 # (Stoat only) Generated config
├── .env.web                    # (Stoat only) Caddy/client env
├── Caddyfile                   # (Stoat only) Caddy config
└── data/
    ├── synapse/                # (Matrix) Homeserver data + media
    ├── postgres/               # (Matrix) Database
    ├── element/                # (Matrix) Element Web config
    ├── nginx/                  # (Matrix) Nginx configs
    ├── coturn/                 # (Matrix) TURN server config
    ├── mautrix-discord/        # (Matrix) Discord bridge data
    ├── mautrix-telegram/       # (Matrix) Telegram bridge data
    ├── db/                     # (Stoat) MongoDB data
    ├── rabbit/                 # (Stoat) RabbitMQ data
    ├── minio/                  # (Stoat) S3 file storage
    ├── caddy-data/             # (Stoat) Caddy certificates
    └── caddy-config/           # (Stoat) Caddy runtime config
```

## License

MIT
