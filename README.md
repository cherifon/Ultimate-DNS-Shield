# Ultimate DNS Shield

**Build your own private, recursive, ad-free DNS server on a Raspberry Pi.**

Pi-hole + Unbound + Docker — no Google, no Cloudflare, no ISP in your DNS chain.

> Licensed under [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/) — free to share with attribution, non-commercial use only.
> Made by [Cherif Jebali](https://github.com/cherifon)

---

## What this project does

Every DNS query you make goes somewhere. By default, that somewhere is Google (8.8.8.8), Cloudflare (1.1.1.1), or your ISP — and they log it.

This project sets up a fully self-hosted DNS stack on a Raspberry Pi 4:

- **Pi-hole** — network-wide ad and tracker blocker
- **Unbound** — recursive resolver that queries root nameservers directly
- **Docker** — both services run in isolated containers on a private bridge network

No third-party resolver ever sees your queries.

---

## Architecture

```
Your devices
    │
    ▼
Pi-hole (172.20.0.3:53)     ← blocks ads & trackers
    │
    ▼
Unbound (172.20.0.2:5335)   ← recursive resolver (no forwarding)
    │
    ▼
Root nameservers             ← authoritative source, no intermediary
```

Unbound is never exposed to the LAN — only Pi-hole can reach it on the internal Docker bridge network.

---

## Requirements

- Raspberry Pi 4 (2GB RAM or more)
- Raspberry Pi OS Lite 64-bit (Debian Bookworm)
- microSD card (32GB, A1 rated)
- Ethernet connection (recommended over Wi-Fi)
- A user account with `sudo` access

---

## Quick Start

### 1. Clone this repo on your Pi

```bash
git clone https://github.com/cherifjebali/ultimate-dns-shield.git
cd ultimate-dns-shield
```

### 2. Edit the configuration

```bash
nano scripts/install.sh
```

Change these values at the top:

```bash
TIMEZONE="Europe/Paris"           # Your timezone
PIHOLE_PASSWORD="ChangeMePlease"  # Choose a strong password
PIHOLE_DIR="$HOME/services/pihole"
```

### 3. Run the installer

```bash
sudo bash scripts/install.sh
```

The script automatically:
- Updates your system
- Installs Docker
- Detects your architecture (ARM vs x86)
- Writes `docker-compose.yml` and `unbound.conf`
- Starts Pi-hole and Unbound
- Verifies DNS is responding

### 4. Harden your Pi

```bash
nano scripts/security.sh
# Set LOCAL_NETWORK to your subnet (e.g. 192.168.0.0/24)

sudo bash scripts/security.sh
```

Configures UFW firewall, Fail2Ban, and automatic security updates.

### 5. Point your router to Pi-hole

In your router's admin panel, set the primary DNS server to your Pi's IP address.
Every device on your network will automatically use Pi-hole.

---

## Verify it works

```bash
# DNS resolves correctly
dig @YOUR_PI_IP google.com

# Ads are blocked (returns 0.0.0.0)
dig @YOUR_PI_IP doubleclick.net

# DNSSEC validation works
dig @YOUR_PI_IP sigfail.verteiltesysteme.net  # → SERVFAIL (correct)
dig @YOUR_PI_IP sigok.verteiltesysteme.net    # → NOERROR (correct)
```

---

## Dry-run mode

All scripts support `--dry-run` — shows exactly what would happen without changing anything:

```bash
bash scripts/install.sh --dry-run
bash scripts/security.sh --dry-run
bash scripts/update.sh --dry-run
```

---

## Update containers

Run monthly to keep Pi-hole and Unbound up to date:

```bash
bash scripts/update.sh
```

---

## Repo structure

```
ultimate-dns-shield/
├── README.md
├── config/
│   ├── docker-compose.yml    # Ready-to-use container config
│   └── unbound.conf          # Recursive resolver config
├── scripts/
│   ├── install.sh            # Full automated installation
│   ├── security.sh           # UFW + Fail2Ban hardening
│   └── update.sh             # Update containers
└── guide/
    └── Ultimate_DNS_Shield_Guide.pdf   # Full step-by-step guide
```

---

## What the guide covers

The PDF guide goes deep into every step:

1. Introduction — how DNS works, why privacy matters
2. Hardware guide — what you need and why
3. Installing Raspberry Pi OS — headless setup
4. Securing SSH — key-based auth, no passwords
5. Installing Docker — official method, post-install
6. Pi-hole + Unbound — architecture, config explained line by line
7. Router configuration — DHCP DNS, testing, DNSSEC
8. Security hardening — UFW, Fail2Ban, auto-updates
9. Bonus — blocklists, testing commands, fallback DNS

[Download the guide (PDF)](guide/Ultimate_DNS_Shield_Guide.pdf)

---

## Recommended blocklists

Add these in Pi-hole under **Adlists > Update Gravity**:

| List | Description |
|------|-------------|
| [Steven Black](https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts) | Gold standard, ~200k entries |
| [Hagezi Pro](https://raw.githubusercontent.com/hagezi/dns-blocklists/main/hosts/pro.txt) | Aggressive, low false positives |
| [OISD Big](https://big.oisd.nl) | Large, tuned for smart home devices |

---

## License

This project is licensed under [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/).

You are free to share and adapt this material for non-commercial purposes, as long as you give appropriate credit to **Cherif Jebali**.

---

## Author

**Cherif Jebali**
- GitHub: [@cherifon](https://github.com/cherifon)

*Built as a practical project to learn Docker, Linux hardening, and DNS privacy.*
