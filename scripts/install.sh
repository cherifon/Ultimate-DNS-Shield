#!/bin/bash
# =============================================================================
#  Ultimate DNS Shield — install.sh
#  Automated installation: Docker + Pi-hole + Unbound
#
#  Copyright © 2026 Cherif Jebali — Unauthorized redistribution is prohibited.
# =============================================================================
#
#  USAGE:
#    sudo bash install.sh           # Real installation
#    bash install.sh --dry-run      # Simulate without changing anything
#
# =============================================================================

set -euo pipefail

# =============================================================================
#  CONFIGURATION — Edit these values before running
# =============================================================================

TIMEZONE="Europe/Paris"
PIHOLE_PASSWORD="ChangeMePlease"
PIHOLE_DIR="$HOME/services/pihole"

# =============================================================================
#  DO NOT EDIT BELOW THIS LINE
# =============================================================================

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_step()  { echo -e "\n${BLUE}==>${NC} $1"; }
print_ok()    { echo -e "${GREEN}  [OK]${NC} $1"; }
print_dry()   { echo -e "${CYAN}  [DRY-RUN]${NC} Would run: $1"; }
print_warn()  { echo -e "${YELLOW}  [WARN]${NC} $1"; }
print_error() { echo -e "${RED}  [ERROR]${NC} $1"; exit 1; }

run() {
    if [ "$DRY_RUN" = true ]; then
        print_dry "$*"
    else
        eval "$@"
    fi
}

write_file() {
    local path="$1"
    local content="$2"
    if [ "$DRY_RUN" = true ]; then
        echo -e "${CYAN}  [DRY-RUN]${NC} Would write file: $path"
        echo "  --- Content preview ---"
        echo "$content" | head -10
        echo "  --- (truncated) ---"
    else
        echo "$content" > "$path"
    fi
}

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo -e "${CYAN}=============================================="
    echo "   DRY-RUN MODE — Nothing will be changed   "
    echo -e "==============================================${NC}"
else
    if [ "$EUID" -eq 0 ] && [ -z "${SUDO_USER:-}" ]; then
        print_error "Do not run as root directly. Use: sudo bash install.sh"
    fi
fi

ACTUAL_USER="${SUDO_USER:-${USER:-$(whoami)}}"

echo ""
echo "=============================================="
echo "   Ultimate DNS Shield — Automated Install   "
echo "=============================================="
echo ""
echo "  Timezone   : $TIMEZONE"
echo "  Install dir: $PIHOLE_DIR"
echo "  User       : $ACTUAL_USER"
echo "  Mode       : $([ "$DRY_RUN" = true ] && echo 'DRY-RUN (simulation)' || echo 'LIVE')"
echo ""

if [ "$DRY_RUN" = false ]; then
    read -rp "Press Enter to continue or Ctrl+C to abort..."
fi

# -----------------------------------------------------------------------------
print_step "Step 1 — System update"
run "apt-get update -qq"
run "apt-get upgrade -y -qq"
run "apt-get install -y -qq curl ca-certificates gnupg dnsutils"
print_ok "System updated"

# -----------------------------------------------------------------------------
print_step "Step 2 — Install Docker"

if command -v docker &>/dev/null && [ "$DRY_RUN" = false ]; then
    print_warn "Docker already installed — skipping"
else
    run "install -m 0755 -d /etc/apt/keyrings"
    curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    rm -f /etc/apt/sources.list.d/docker.list
    ARCH=$(dpkg --print-architecture)
    CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
    echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${CODENAME} stable" \
        > /etc/apt/sources.list.d/docker.list

    run "apt-get update -qq"
    run "apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    run "usermod -aG docker $ACTUAL_USER"
    print_ok "Docker installed"
fi

# -----------------------------------------------------------------------------
print_step "Step 3 — Create directory structure"
run "mkdir -p $PIHOLE_DIR/etc-pihole"
run "mkdir -p $PIHOLE_DIR/etc-unbound"
print_ok "Directories: $PIHOLE_DIR"

# -----------------------------------------------------------------------------
print_step "Step 4 — Write docker-compose.yml"

# Auto-detect architecture: ARM (Raspberry Pi) vs x86 (VM/other)
MACHINE_ARCH=$(uname -m)
if [[ "$MACHINE_ARCH" == "aarch64" || "$MACHINE_ARCH" == "armv7l" ]]; then
    UNBOUND_IMAGE="mvance/unbound-rpi:latest"
    print_ok "ARM detected — using mvance/unbound-rpi"
else
    UNBOUND_IMAGE="mvance/unbound:latest"
    print_ok "x86 detected — using mvance/unbound"
fi

COMPOSE_CONTENT="services:

  unbound:
    container_name: unbound
    image: ${UNBOUND_IMAGE}
    volumes:
      - ./etc-unbound/unbound.conf:/opt/unbound/etc/unbound/unbound.conf:ro
    networks:
      pihole_net:
        ipv4_address: 172.20.0.2
    restart: unless-stopped

  pihole:
    container_name: pihole
    image: pihole/pihole:latest
    depends_on:
      - unbound
    networks:
      pihole_net:
        ipv4_address: 172.20.0.3
    ports:
      - \"53:53/tcp\"
      - \"53:53/udp\"
      - \"80:80/tcp\"
      - \"443:443/tcp\"
    environment:
      - TZ=${TIMEZONE}
      - FTLCONF_webserver_api_password=${PIHOLE_PASSWORD}
      - FTLCONF_dns_listeningMode=all
      - FTLCONF_dns_upstreams=172.20.0.2#5335
      - FTLCONF_dns_dnssec=true
    volumes:
      - ./etc-pihole:/etc/pihole
    restart: unless-stopped

networks:
  pihole_net:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/24"

write_file "$PIHOLE_DIR/docker-compose.yml" "$COMPOSE_CONTENT"
print_ok "docker-compose.yml ready"

# -----------------------------------------------------------------------------
print_step "Step 5 — Write unbound.conf"

UNBOUND_CONTENT="server:
    interface: 0.0.0.0
    port: 5335
    do-ip4: yes
    do-ip6: yes
    do-udp: yes
    do-tcp: yes

    access-control: 0.0.0.0/0 refuse
    access-control: 127.0.0.0/8 allow
    access-control: 172.20.0.0/24 allow

    incoming-num-tcp: 100
    outgoing-num-tcp: 100
    tcp-idle-timeout: 30000

    edns-buffer-size: 1232
    verbosity: 1

    hide-identity: yes
    hide-version: yes

    domain-insecure: \"verteiltesysteme.net\""

write_file "$PIHOLE_DIR/etc-unbound/unbound.conf" "$UNBOUND_CONTENT"
print_ok "unbound.conf ready"

# -----------------------------------------------------------------------------
print_step "Step 6 — Start containers"
run "cd $PIHOLE_DIR && docker compose up -d"

if [ "$DRY_RUN" = false ]; then
    sleep 5
    if docker ps | grep -q "pihole" && docker ps | grep -q "unbound"; then
        print_ok "Both containers running"
    else
        print_warn "Check logs: docker logs pihole"
    fi
else
    print_ok "Containers would be started"
fi

# -----------------------------------------------------------------------------
print_step "Step 7 — Verify DNS"
if [ "$DRY_RUN" = false ]; then
    sleep 3
    if dig @127.0.0.1 google.com +short +time=3 &>/dev/null; then
        print_ok "DNS is responding"
    else
        print_warn "DNS not responding — check: docker logs pihole"
    fi
else
    print_dry "dig @127.0.0.1 google.com"
    print_ok "DNS check would be performed"
fi

# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
if [ "$DRY_RUN" = true ]; then
    echo -e "${CYAN}   Dry-run complete — no changes were made${NC}"
    echo ""
    echo "  Run the real install with:"
    echo "    sudo bash install.sh"
else
    echo -e "${GREEN}   Installation complete!${NC}"
    echo ""
    echo "  Pi-hole admin : http://$(hostname -I | awk '{print $1}')/admin"
    echo "  Password      : $PIHOLE_PASSWORD"
    echo ""
    echo -e "${YELLOW}  Log out and back in for Docker group changes.${NC}"
fi
echo "=============================================="
echo ""
