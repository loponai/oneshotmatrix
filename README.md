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
- Enter the **root password** from your Scala welcome email
  - **The screen will stay completely blank as you type or paste** — no dots, no stars, nothing. This is normal! Just paste your password and press Enter. It's there, you just can't see it.

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

Open your domain in a browser — or install it as a desktop app (see [Desktop & Mobile Apps](#desktop--mobile-apps) below).

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

### Desktop & Mobile Apps (Matrix)

You don't have to use the browser — Element has apps for every platform, and they all support custom homeservers out of the box.

**Desktop (Windows, macOS, Linux):**

1. Download [Element Desktop](https://element.io/download) for your platform
2. On the login screen, click **"Edit"** next to the homeserver URL
3. Change it to `https://yourdomain.com`
4. Log in with your account

**Mobile:**

- **Android** — [Google Play](https://play.google.com/store/apps/details?id=im.vector.app) or [F-Droid](https://f-droid.org/packages/im.vector.app/)
- **iOS** — [App Store](https://apps.apple.com/app/element-messenger/id1083446067)
- On the login screen, tap **"Edit"** next to the homeserver and enter `https://yourdomain.com`

**Install as a PWA (alternative):**

If you prefer not to install an app, you can turn the web client into a standalone desktop window:
- **Chrome/Edge:** Visit your domain → click the install icon in the address bar (or menu → "Install app")

### View credentials
```bash
cat /opt/matrix-discord-killer/credentials.txt
```

---

## Using Element

After installation, open your domain in a browser and log in with the admin account you created during setup.

### Create Rooms

1. Click the **+** next to any section in the left sidebar
2. Choose **New room**
3. Give it a name and optionally set it to private (encrypted by default)
4. Your room appears in the sidebar, ready for messages

### Create Spaces (like Discord servers)

Spaces are groups of rooms — think of them as folders or communities.

1. Click the **+** in the left sidebar → **Create a space**
2. Name it and choose public or private
3. Add existing rooms or create new ones inside the space

### Invite People

You need to create accounts for them first (public registration is off by default):

```bash
cd /opt/matrix-discord-killer
docker compose exec synapse register_new_matrix_user -c /data/homeserver.yaml
```

Then share your server address — they log in at `https://yourdomain.com` or using any Matrix app pointed at your server.

### End-to-End Encryption

Private rooms are **encrypted by default**. Element will prompt you to set up a Security Key (cross-signing) on first login — do this, it protects your message history if you log in from a new device.

### Voice & Video Calls

Click the phone or camera icon in any room. Calls use your Coturn server (set up by the installer) for NAT traversal. Group calls work in rooms with video room features enabled.

---

## Admin Guide (Matrix)

### Everyday Commands

```bash
cd /opt/matrix-discord-killer

docker compose ps                # See what's running
docker compose logs synapse      # Check Matrix server logs
docker compose logs nginx        # Check reverse proxy logs
docker compose logs coturn       # Check voice/video relay logs
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

### Create User Accounts

Public registration is off by default (recommended). Create accounts from the command line:

```bash
cd /opt/matrix-discord-killer
docker compose exec synapse register_new_matrix_user -c /data/homeserver.yaml
```

It will ask for a username, password, and whether to make them an admin.

### Enable Public Registration

If you want anyone to be able to sign up without you creating accounts:

1. Edit the config:
   ```bash
   nano /opt/matrix-discord-killer/data/synapse/homeserver.yaml
   ```
2. Change this line:
   ```yaml
   enable_registration: true
   ```
3. Restart Synapse:
   ```bash
   cd /opt/matrix-discord-killer && docker compose restart synapse
   ```

> **Warning:** Open registration means anyone can create accounts on your server. Consider adding a CAPTCHA or rate limiting if you enable this.

### Test Federation

Federation lets your users communicate with people on other Matrix servers (like matrix.org).

```bash
# Check if federation is working
curl -sf https://yourdomain.com/.well-known/matrix/server
# Should return: {"m.server": "yourdomain.com:443"}

# Or use the online tester
# https://federationtester.matrix.org/#yourdomain.com
```

### Backup Your Data

All persistent data lives in `/opt/matrix-discord-killer/data/`. To backup:

```bash
cd /opt/matrix-discord-killer
docker compose down
tar -czf ~/matrix-backup-$(date +%Y%m%d).tar.gz data/ .env docker-compose.yml
docker compose up -d
```

### SSL Certificate Renewal

Certificates auto-renew via a cron job. To check or manually renew:

```bash
# Check when the cert expires
certbot certificates

# Manual renewal
certbot renew --webroot -w /opt/matrix-discord-killer/data/certbot/www
cd /opt/matrix-discord-killer && docker compose restart nginx coturn
```

### Key Files

| File | What it does |
|------|-------------|
| `data/synapse/homeserver.yaml` | Main Synapse config — registration, federation, database |
| `.env` | Domain, secrets, bridge toggles |
| `credentials.txt` | Your saved admin login and secrets |
| `docker-compose.yml` | Container definitions |
| `data/synapse/media_store/` | Uploaded files, avatars, media |
| `data/postgres/` | PostgreSQL database (messages, accounts) |
| `data/coturn/turnserver.conf` | Voice/video relay configuration |
| `data/nginx/matrix.conf` | Nginx reverse proxy rules |

### Official Matrix Documentation

- [Synapse admin guide](https://element-hq.github.io/synapse/latest/usage/administration/)
- [Element Web docs](https://element.io/help)
- [Matrix spec](https://spec.matrix.org/)

---

## Using Stoat

After installation, open your domain in a browser and register your account. The first account becomes the server owner.

### Create a Server

1. Click the **+** button in the left sidebar
2. Choose **Create a server**
3. Give it a name — this is your community space
4. Your server appears in the sidebar with a default **General** channel

### Create Channels

1. Click the **+** next to "Text Channels" (or "Voice Channels") in your server
2. Name the channel and click **Create**

### Invite People

- **Quick invite:** Right-click any channel name → **Create Invite** — copy and share the link
- **Manage invites:** Go to **Server Settings** → **Invites** to view, copy, or revoke existing invite links

> If you enabled `invite_only = true` (see Admin Guide below), people will need an invite link to register. If registration is open, they can just visit your domain and sign up.

### Customize Your Server

- **Server icon:** Server Settings → Overview → click the server icon to upload
- **Roles & permissions:** Server Settings → Roles → create roles and assign permissions
- **Categories:** Right-click in the channel list → Create Category to organize channels into groups

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

### Enable Email (Password Resets & Verification)

By default, Stoat **cannot send emails** — there is no built-in mail server. This means "Forgot password" won't work until you configure SMTP. You need credentials from an email provider:

| Provider | Free tier | Sign up |
|----------|-----------|---------|
| **Brevo** (Sendinblue) | 300 emails/day | [brevo.com](https://www.brevo.com/) |
| **Resend** | 100 emails/day | [resend.com](https://resend.com/) |
| **Mailgun** | 100 emails/day | [mailgun.com](https://www.mailgun.com/) |
| **Gmail** | Use with app password | [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords) |

Once you have SMTP credentials, add this to your `Revolt.toml`:

1. Edit the config:
   ```bash
   nano /opt/matrix-discord-killer/Revolt.toml
   ```
2. Add the `[api.smtp]` section (replace the values with your provider's details):
   ```toml
   [api.smtp]
   host = "smtp.brevo.com"
   port = 587
   username = "your-smtp-username"
   password = "your-smtp-password"
   from_address = "noreply@yourdomain.com"
   use_tls = true
   ```
3. Restart the API:
   ```bash
   cd /opt/matrix-discord-killer && docker compose restart api
   ```

> **Gmail example:** Use `host = "smtp.gmail.com"`, `port = 587`, your Gmail address as `username`, and an [app password](https://myaccount.google.com/apppasswords) (not your regular Gmail password) as `password`.

After this, password reset emails, email verification, and other notifications will work.

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

### Desktop & Mobile Apps

The web client works great in a browser, but you can also get a desktop-app experience:

**Install as a desktop app (recommended):**

This turns your self-hosted web client into a standalone window — no browser tabs, no URL bar, just your chat.

- **Chrome/Edge:** Visit your domain → click the install icon in the address bar (or ⋮ menu → "Install app" / "Create shortcut" → check "Open as window")
- **Firefox:** Not supported natively — use Chrome or Edge for this

The installed app launches from your Start menu / Applications folder like any other program, and it's already connected to your server.

**Official Stoat desktop app:**

Stoat also has a [standalone desktop app](https://stoat.chat/download) for Windows, macOS, and Linux. This app connects to the official `stoat.chat` servers by default. To point it at your self-hosted server, launch it with:

```bash
# Windows (from the install directory)
stoat-desktop.exe --force-server https://yourdomain.com

# macOS
/Applications/Stoat.app/Contents/MacOS/Stoat --force-server https://yourdomain.com

# Linux
./stoat-desktop --force-server https://yourdomain.com
```

> The `--force-server` flag is a developer option and may not work reliably in all versions. The PWA install method above is simpler and always works.

**Mobile:**

- **Android** (beta) — [Google Play](https://play.google.com/store/apps/details?id=chat.revolt)
- **iOS** (beta) — [TestFlight](https://stoat.chat/download/ios)
- Mobile apps may not support custom server URLs yet. As an alternative, use your phone's browser and "Add to Home Screen" for an app-like experience.

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
