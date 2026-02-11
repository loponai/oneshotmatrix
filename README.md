# matrix-discord-killer

**Deploy a self-hosted chat platform in one command.** Choose between Matrix/Element (federated, E2EE, bridges) or Stoat/Revolt (modern UI, simple setup).

```bash
curl -fsSL https://raw.githubusercontent.com/loponai/oneshotmatrix/main/install.sh | sudo bash
```

---

## Quick Start (Scala Hosting)

We recommend [Scala Hosting](http://scala.tomspark.tech/) because their self-managed VPS gives you **full root access** out of the box — which is required for our Docker, firewall, and SSL configurations. KVM virtualization means Docker runs natively with zero issues.

### Step 1: Get a VPS

1. Go to [Scala Hosting Self-Managed VPS](http://scala.tomspark.tech/)
2. Pick **Build #1** (2 cores, 4GB RAM, 50GB NVMe) — $19.95/mo, plenty for a personal/small-community server
3. Choose **Ubuntu** as the operating system
4. Complete checkout and wait for your welcome email with your server IP and root password

### Step 2: Get a domain and point it to your server

You need a domain name (like `chat.example.com`) that points to your VPS. If you don't already have one:

1. **Buy a domain** from a registrar like [Namecheap](https://www.namecheap.com), [Porkbun](https://porkbun.com), or [Cloudflare Domains](https://www.cloudflare.com/products/registrar/) — usually ~$10/year for a `.com`
2. **Go to your registrar's DNS settings** (or Cloudflare if you use it for DNS)
3. **Create an A record** pointing to your Scala VPS IP address:

| Type | Name | Value |
|------|------|-------|
| A | chat.example.com | YOUR_SERVER_IP |

Your server IP is in the welcome email from Scala. If you want to use a subdomain like `chat.example.com`, put `chat` in the Name field. If you want the whole domain (like `example.com`), put `@`.

Wait 5-15 minutes for DNS to propagate before moving on.

> **Cloudflare users:** Set the proxy to **DNS only** (grey cloud). Cloudflare doesn't support port 8448 (Matrix federation) and can interfere with SSL certificate generation.

### Step 3: SSH in and disable SPanel

Scala includes their SPanel control panel by default, which runs a web server on ports 80/443. We need those ports, so disable it first:

```bash
ssh root@YOUR_SERVER_IP
```

Use the root password from your Scala welcome email. Then run:

```bash
systemctl mask --now httpd
systemctl mask --now nginx
```

> This disables SPanel's web admin UI, but you won't need it — everything is managed via SSH after the installer runs.

### Step 4: Run the installer

```bash
curl -fsSL https://raw.githubusercontent.com/loponai/oneshotmatrix/main/install.sh | sudo bash
```

You'll be asked for:
1. **Platform** — Matrix/Element or Stoat (Revolt)
2. **Domain** — the domain you set up in Step 2
3. **Email** — for SSL certificates
4. **Admin password** — (Matrix only) for the `@admin` account
5. **Bridges** — (Matrix only) optional Discord and Telegram bridges

The installer handles Docker, firewall, SSL, and all configuration automatically.

### Step 5: Log in

Open your domain in a browser. That's it.

---

## What You Get

### Matrix/Element
- **Element Web** — Modern chat UI at your domain
- **Synapse** — Matrix homeserver with federation
- **PostgreSQL** — Production database
- **Coturn** — TURN/STUN for voice and video calls
- **Nginx** — Reverse proxy with auto HTTPS
- **Discord Bridge** (optional) — Access Discord from Element
- **Telegram Bridge** (optional) — Access Telegram from Element

### Stoat (Revolt)
- **Stoat Web Client** — Discord-like chat UI
- **Revolt API** — Rust backend with MongoDB
- **Caddy** — Reverse proxy with auto HTTPS
- File uploads, push notifications, URL previews built in

## Why Scala Hosting?

| Feature | Why it matters |
|---------|---------------|
| **Full root access** | Required for Docker, firewall, and SSL configuration |
| **KVM virtualization** | Docker runs natively — no issues like OpenVZ |
| **Unmetered bandwidth** | No surprise bills from federation traffic |
| **NVMe storage** | Fast database reads/writes for Synapse + PostgreSQL |
| **Free snapshots** | Backup before changes, roll back if needed |
| **Scalable** | Add RAM ($3/GB) or CPU ($10/core) anytime |

**Recommended plan:** [Self-Managed Build #1](http://scala.tomspark.tech/) — 2 cores, 4GB RAM, 50GB NVMe at **$19.95/mo**. Step up to Build #2 (4 cores, 8GB) for heavier usage.

---

## After Installation

### Using Bridges (Matrix only)

**Discord** — Open Element, DM `@discordbot:yourdomain.com`:
```
!discord login
```
Follow the prompts. Your Discord servers will appear as Matrix rooms.

**Telegram** — DM `@telegrambot:yourdomain.com`:
```
!tg login
```
Enter your phone number and verification code. Telegram chats sync to Matrix.

### Managing Users

**Matrix** — Public registration is off by default. Create accounts with:
```bash
cd /opt/matrix-discord-killer
docker compose exec synapse register_new_matrix_user -c /data/homeserver.yaml
```

**Stoat** — Open the web client and register. First account becomes server owner.

### View credentials
```bash
cat /opt/matrix-discord-killer/credentials.txt
```

---

## Troubleshooting

```bash
cd /opt/matrix-discord-killer
docker compose ps              # Service status
docker compose logs            # All logs
docker compose logs synapse    # Single service
```

**Federation not working?** Check DNS (`dig A yourdomain.com`), test at https://federationtester.matrix.org, verify port 8448 is open (`ufw status`).

**Voice/video failing?** Check `docker compose logs coturn`, verify TURN ports open (`ufw status`), test in Element under Settings > Voice & Video.

**SSL issues?**
```bash
certbot renew --webroot -w /opt/matrix-discord-killer/data/certbot/www
cd /opt/matrix-discord-killer && docker compose restart nginx coturn
```

**Stoat not loading?** Check `docker compose logs caddy` and `docker compose logs api`.

**Stoat uploads failing?** Check `docker compose logs minio` and `docker compose logs autumn`.

---

## Uninstall

```bash
sudo /opt/matrix-discord-killer/uninstall.sh
```

Permanently destroys all data including messages, accounts, and media.

---

## Reference

### Requirements

- **Ubuntu 22.04+** or **Debian 12+** VPS with full root access (4GB RAM recommended)
- A domain name with DNS pointed to your server
- Ports 80/443 free (disable SPanel's web server first — see Step 3)

### Architecture

**Matrix/Element:**
```
Internet → Nginx (80/443/8448)
              ├→ Element Web (/)
              ├→ Synapse (/_matrix/)
              │    └→ PostgreSQL
              ├→ Coturn (voice/video)
              ├→ mautrix-discord (optional)
              └→ mautrix-telegram (optional)
```

**Stoat (Revolt):**
```
Internet → Caddy (80/443)
              ├→ Web client, API, WebSocket
              ├→ File server, URL proxy
              └→ MongoDB, Redis, RabbitMQ, MinIO
```

### Ports

| Port | Purpose |
|------|---------|
| 80 | HTTP → HTTPS redirect + ACME |
| 443 | Element/Synapse or Stoat client |
| 8448 | Matrix federation (Matrix only) |
| 3478 | TURN TCP/UDP (Matrix only) |
| 5349 | TURNS TCP/UDP (Matrix only) |
| 49152-49200 | TURN relay media UDP (Matrix only) |

> Stoat only needs ports 80 and 443.

### File layout

```
/opt/matrix-discord-killer/
├── docker-compose.yml / docker-compose.stoat.yml
├── .env                    # Generated secrets
├── credentials.txt         # Login details
├── setup.sh / uninstall.sh
├── templates/              # Config templates
└── data/                   # All persistent data
```

## License

MIT
