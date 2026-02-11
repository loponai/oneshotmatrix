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
3. Choose **Ubuntu** or **Rocky Linux** as the operating system (Rocky is the default if SPanel is included)
4. Complete checkout and wait for your welcome email with your server IP and root password

### Step 2: Get a domain and point it to your server

You need a domain name that points to your VPS IP address. You can register one through Scala during checkout, or use one you already own.

**Important:** Do NOT use SPanel or the VPS's built-in nameservers for DNS. In Step 3 we disable SPanel, which would kill the VPS's DNS server and break your domain. Use **external DNS** instead (Cloudflare is free and works great).

#### Set up DNS with Cloudflare (recommended)

1. **Find your VPS IP** — it's in the welcome email from Scala
2. **Create a free [Cloudflare](https://dash.cloudflare.com/sign-up) account** if you don't have one
3. **Add your domain** to Cloudflare — it will give you two nameservers (e.g. `ann.ns.cloudflare.com`, `bob.ns.cloudflare.com`)
4. **Update your domain's nameservers** — go to [my.scalahosting.com](https://my.scalahosting.com) > My Domains > click Manage next to your domain > Manage Nameservers > select "Use custom nameservers" and enter the two Cloudflare nameservers
5. **Add an A record in Cloudflare** — go to your domain in the Cloudflare dashboard > DNS > Add Record:

| Type | Name | Content | Proxy status |
|------|------|---------|-------------|
| A | `@` (or a subdomain like `chat`) | Your VPS IP | **DNS only** (grey cloud) |

> **The proxy must be off (grey cloud, "DNS only").** Cloudflare's proxy doesn't support port 8448 (Matrix federation) and blocks SSL certificate generation.

6. Wait for nameserver changes to propagate (can take up to 24-48 hours, usually faster)

#### Alternative: Use your registrar's DNS

If you don't want to use Cloudflare, you can create the A record in whatever registrar you bought the domain from (Namecheap, Porkbun, etc.) — just make sure you're **not** using the VPS as your nameserver.

### Step 3: SSH in and disable SPanel

SSH is how you remotely control your server from a terminal. You type commands on your computer and they run on the VPS.

**On Mac/Linux:** Open Terminal (it's built in).

**On Windows:** Open **PowerShell** (search for it in the Start menu) or install [Windows Terminal](https://aka.ms/terminal) from the Microsoft Store.

Then connect to your server. Scala uses **port 6543** for SSH (not the default 22):

```bash
ssh root@YOUR_SERVER_IP -p 6543
```

Replace `YOUR_SERVER_IP` with the IP from your Scala welcome email (e.g. `ssh root@142.248.180.64 -p 6543`).

> **Getting "Connection refused"?** If port 6543 doesn't work, try without `-p 6543` (some Scala plans use the default port 22). Check your welcome email for the correct SSH port.

- It will ask "Are you sure you want to continue connecting?" — type `yes` and press Enter
- Enter the **root password** from your Scala welcome email (the cursor won't move as you type — that's normal, it's hidden)

Once you're in, you'll see a command prompt on your server. Now disable SPanel's web server so our installer can use ports 80/443:

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
- **Stoat API** — Rust backend with MongoDB
- **Caddy** — Reverse proxy with auto HTTPS
- File uploads, push notifications, URL previews built in

> **Why does the app say "Revolt"?** Stoat was previously called Revolt before a [rebrand in late 2025](https://wiki.rvlt.gg/index.php/Rebrand_to_Stoat). The web client hasn't been updated with the new branding yet. Same software, same team, just a new name.
>
> **"API error" on first load?** This is normal — the services take 30-60 seconds to fully start after the installer finishes. Wait a moment and refresh the page.

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

## Admin Guide (Stoat)

### Everyday Commands

```bash
cd /opt/matrix-discord-killer

docker compose ps                # See what's running
docker compose logs api          # Check API logs
docker compose logs caddy        # Check reverse proxy logs
docker compose restart           # Restart everything
docker compose down              # Stop everything
docker compose up -d             # Start everything
```

### Update to Latest Version

```bash
cd /opt/matrix-discord-killer
docker compose pull
docker compose up -d
```

### Make Your Server Invite-Only

By default anyone who visits your domain can register. To lock it down:

1. Edit the config:
   ```bash
   nano /opt/matrix-discord-killer/Revolt.toml
   ```
2. Add this line (or change it if it already exists):
   ```toml
   invite_only = true
   ```
3. Restart the API:
   ```bash
   cd /opt/matrix-discord-killer && docker compose restart api
   ```

### Backup Your Data

All persistent data lives in `/opt/matrix-discord-killer/data/`. To backup:

```bash
cd /opt/matrix-discord-killer
docker compose down
tar -czf ~/stoat-backup-$(date +%Y%m%d).tar.gz data/ .env Revolt.toml
docker compose up -d
```

### Key Files

| File | What it does |
|------|-------------|
| `Revolt.toml` | Main config — features, limits, invite-only mode |
| `.env` | Domain, secrets, encryption keys |
| `credentials.txt` | Your saved setup info |
| `docker-compose.stoat.yml` | Container definitions |
| `data/db/` | MongoDB database (messages, accounts) |
| `data/minio/` | Uploaded files and media |

### Using Mobile/Desktop Apps

You can use the official Revolt apps with your self-hosted server:

1. Download [Revolt](https://revolt.chat/download) for your platform
2. On the login screen, look for "custom server" or "self-hosted" option
3. Enter your domain (e.g. `https://tomsparkchat.com`)
4. Log in with your account

### Official Revolt Documentation

- [Self-hosted repo & config reference](https://github.com/stoatchat/self-hosted)
- [Developer FAQ](https://developers.stoat.chat/faq.html/)

---

## Troubleshooting

```bash
cd /opt/matrix-discord-killer
docker compose ps              # Service status
docker compose logs            # All logs
docker compose logs synapse    # Single service
```

**Federation not working?** Check DNS (`dig A yourdomain.com`), test at https://federationtester.matrix.org, verify port 8448 is open (`ufw status` on Ubuntu/Debian, `firewall-cmd --list-ports` on Rocky Linux).

**Voice/video failing?** Check `docker compose logs coturn`, verify TURN ports open (`ufw status` or `firewall-cmd --list-ports`), test in Element under Settings > Voice & Video.

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

- **Ubuntu 22.04+**, **Debian 12+**, or **Rocky Linux 8+** VPS with full root access (4GB RAM recommended)
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
