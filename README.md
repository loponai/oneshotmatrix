# matrix-discord-killer

**Deploy a full self-hosted Matrix/Element stack in one command.** Encrypted chat, voice/video calls, and Discord/Telegram bridging on your own server.

```bash
curl -fsSL https://raw.githubusercontent.com/loponai/oneshotmatrix/main/install.sh | sudo bash
```

---

## What You Get

- **Element Web** - Modern chat UI at your domain root
- **Synapse** - Matrix homeserver with federation
- **PostgreSQL** - Production database (not SQLite)
- **Coturn** - TURN/STUN server for voice and video calls
- **Nginx** - Reverse proxy with automatic HTTPS and rate limiting
- **Discord Bridge** (optional) - Access Discord servers from Element
- **Telegram Bridge** (optional) - Access Telegram chats from Element

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

## Installation

```bash
curl -fsSL https://raw.githubusercontent.com/loponai/oneshotmatrix/main/install.sh | sudo bash
```

You'll be prompted for:
1. **Domain name** - Your domain with DNS configured
2. **Email** - For Let's Encrypt SSL certificates
3. **Admin password** - For the `@admin` account
4. **Bridge selection** - Optional Discord and Telegram bridges

The installer handles everything: Docker, SSL, firewall, configuration.

## Architecture

```
Internet → Nginx (80/443/8448)
              ├→ Element Web (/)
              ├→ Synapse (/_matrix/)
              │    └→ PostgreSQL
              ├→ Coturn (voice/video, host networking)
              ├→ mautrix-discord (optional)
              └→ mautrix-telegram (optional)
```

All services run as Docker containers. Bridges use Docker Compose profiles and are only started if selected during setup.

| Port | Purpose |
|------|---------|
| 80 | HTTP → HTTPS redirect + ACME challenges |
| 443 | Element Web + Synapse client API |
| 8448 | Matrix federation |
| 3478 | TURN (TCP/UDP) |
| 5349 | TURNS (TCP/UDP) |
| 49152-49200 | TURN relay media (UDP) |

## Using Bridges

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

Public registration is disabled by default. Create accounts manually:

```bash
cd /opt/matrix-discord-killer
docker compose exec synapse register_new_matrix_user -c /data/homeserver.yaml
```

## Troubleshooting

### Check service status
```bash
cd /opt/matrix-discord-killer
docker compose ps
docker compose logs synapse    # Synapse logs
docker compose logs nginx      # Nginx logs
```

### Federation not working
1. Check DNS: `dig A yourdomain.com`
2. Test: https://federationtester.matrix.org
3. Verify port 8448 is open: `ufw status`

### Voice/video calls failing
1. Check Coturn: `docker compose logs coturn`
2. Verify TURN ports are open: `ufw status`
3. Test from Element: Settings → Voice & Video → Test

### SSL certificate issues
```bash
# Manual renewal
certbot renew --webroot -w /opt/matrix-discord-killer/data/certbot/www
cd /opt/matrix-discord-killer && docker compose restart nginx coturn
```

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
├── docker-compose.yml
├── .env                    # Generated secrets (chmod 600)
├── credentials.txt         # Login details (chmod 600)
├── setup.sh
├── uninstall.sh
├── templates/              # Config templates
└── data/
    ├── synapse/            # Homeserver data + media
    ├── postgres/           # Database
    ├── element/            # Element Web config
    ├── nginx/              # Nginx configs
    ├── coturn/             # TURN server config
    ├── mautrix-discord/    # Discord bridge data
    └── mautrix-telegram/   # Telegram bridge data
```

## License

MIT
