#!/bin/bash
# =============================================================================
#  Ultimate DNS Shield — security.sh
#  Harden your Raspberry Pi: UFW firewall + Fail2Ban
#
#  Copyright © 2026 Cherif Jebali — Unauthorized redistribution is prohibited.
# =============================================================================
#
#  USAGE:
#    sudo bash security.sh           # Real hardening
#    bash security.sh --dry-run      # Simulate without changing anything
#
# =============================================================================

set -euo pipefail

# =============================================================================
#  CONFIGURATION — Edit before running
# =============================================================================

LOCAL_NETWORK="192.168.1.0/24"
SSH_PORT="22"
F2B_BANTIME="2h"
F2B_FINDTIME="10m"
F2B_MAXRETRY="3"

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

if [ "$DRY_RUN" = false ] && [ "$EUID" -ne 0 ]; then
    print_error "Run as root: sudo bash security.sh"
fi

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo -e "${CYAN}=============================================="
    echo "   DRY-RUN MODE — Nothing will be changed   "
    echo -e "==============================================${NC}"
fi

echo ""
echo "=============================================="
echo "   Ultimate DNS Shield — Security Hardening  "
echo "=============================================="
echo ""
echo "  Local network : $LOCAL_NETWORK"
echo "  SSH port      : $SSH_PORT"
echo "  Fail2Ban ban  : $F2B_BANTIME after $F2B_MAXRETRY attempts"
echo "  Mode          : $([ "$DRY_RUN" = true ] && echo 'DRY-RUN (simulation)' || echo 'LIVE')"
echo ""

if [ "$DRY_RUN" = false ]; then
    print_warn "Make sure SSH port $SSH_PORT is correct before continuing!"
    read -rp "Press Enter to continue or Ctrl+C to abort..."
fi

# -----------------------------------------------------------------------------
print_step "Step 1 — Install UFW and Fail2Ban"
run "apt-get update -qq"
run "apt-get install -y -qq ufw fail2ban"
print_ok "Packages ready"

# -----------------------------------------------------------------------------
print_step "Step 2 — Configure UFW rules"
run "ufw --force reset"
run "ufw default deny incoming"
run "ufw default allow outgoing"
run "ufw allow $SSH_PORT/tcp"
print_ok "SSH rule added (port $SSH_PORT)"
run "ufw allow from $LOCAL_NETWORK to any port 53"
print_ok "DNS rule added (port 53 from $LOCAL_NETWORK only)"
run "ufw allow from $LOCAL_NETWORK to any port 80"
run "ufw allow from $LOCAL_NETWORK to any port 443"
print_ok "Pi-hole web interface rules added"
run "ufw --force enable"
print_ok "UFW enabled"

if [ "$DRY_RUN" = false ]; then
    echo ""
    ufw status verbose
fi

# -----------------------------------------------------------------------------
print_step "Step 3 — Configure Fail2Ban"

JAIL_CONTENT="[DEFAULT]
bantime  = ${F2B_BANTIME}
findtime = ${F2B_FINDTIME}
maxretry = ${F2B_MAXRETRY}

[sshd]
enabled  = true
port     = ${SSH_PORT}
logpath  = %(sshd_log)s
backend  = %(sshd_backend)s
maxretry = ${F2B_MAXRETRY}
bantime  = ${F2B_BANTIME}"

if [ "$DRY_RUN" = true ]; then
    print_dry "Write /etc/fail2ban/jail.local"
    echo "  --- Content preview ---"
    echo "$JAIL_CONTENT"
    echo "  -----------------------"
else
    echo "$JAIL_CONTENT" > /etc/fail2ban/jail.local
    systemctl restart fail2ban
    systemctl enable fail2ban
    sleep 2
    if systemctl is-active --quiet fail2ban; then
        print_ok "Fail2Ban running"
        fail2ban-client status sshd 2>/dev/null || true
    else
        print_warn "Check: systemctl status fail2ban"
    fi
fi
print_ok "Fail2Ban configured"

# -----------------------------------------------------------------------------
print_step "Step 4 — Automatic security updates"
run "apt-get install -y -qq unattended-upgrades"

AUTO_UPGRADES_CONTENT='APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";'

if [ "$DRY_RUN" = true ]; then
    print_dry "Write /etc/apt/apt.conf.d/20auto-upgrades"
else
    echo "$AUTO_UPGRADES_CONTENT" > /etc/apt/apt.conf.d/20auto-upgrades
    systemctl enable unattended-upgrades
    systemctl restart unattended-upgrades
fi
print_ok "Auto-updates enabled"

# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
if [ "$DRY_RUN" = true ]; then
    echo -e "${CYAN}   Dry-run complete — no changes were made${NC}"
    echo ""
    echo "  Run the real hardening with:"
    echo "    sudo bash security.sh"
else
    echo -e "${GREEN}   Security hardening complete!${NC}"
    echo ""
    echo "  UFW      : $(ufw status | head -1)"
    echo "  Fail2Ban : $(systemctl is-active fail2ban)"
    echo "  Updates  : $(systemctl is-active unattended-upgrades)"
fi
echo "=============================================="
echo ""
