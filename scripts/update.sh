#!/bin/bash
# =============================================================================
#  Ultimate DNS Shield — update.sh
#  Update Pi-hole and Unbound to their latest Docker images
#
#  Copyright © 2026 Cherif Jebali — Unauthorized redistribution is prohibited.
# =============================================================================
#
#  USAGE:
#    bash update.sh           # Real update
#    bash update.sh --dry-run # Simulate without changing anything
#
# =============================================================================

set -euo pipefail

# =============================================================================
#  CONFIGURATION
# =============================================================================

PIHOLE_DIR="$HOME/services/pihole"

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

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo -e "${CYAN}=============================================="
    echo "   DRY-RUN MODE — Nothing will be changed   "
    echo -e "==============================================${NC}"
fi

echo ""
echo "=============================================="
echo "   Ultimate DNS Shield — Update Containers   "
echo "=============================================="
echo ""
echo "  Directory : $PIHOLE_DIR"
echo "  Mode      : $([ "$DRY_RUN" = true ] && echo 'DRY-RUN (simulation)' || echo 'LIVE')"
echo ""

if [ "$DRY_RUN" = false ] && [ ! -f "$PIHOLE_DIR/docker-compose.yml" ]; then
    print_error "docker-compose.yml not found at $PIHOLE_DIR"
fi

# -----------------------------------------------------------------------------
print_step "Step 1 — Current container status"
if [ "$DRY_RUN" = false ]; then
    docker ps --format "  {{.Names}}\t{{.Image}}\t{{.Status}}" 2>/dev/null || true
else
    print_dry "docker ps"
fi

# -----------------------------------------------------------------------------
print_step "Step 2 — Pull latest images"
run "cd $PIHOLE_DIR && docker compose pull"
print_ok "Images pulled"

# -----------------------------------------------------------------------------
print_step "Step 3 — Recreate containers"
run "cd $PIHOLE_DIR && docker compose up -d --force-recreate"
print_ok "Containers restarted"

# -----------------------------------------------------------------------------
print_step "Step 4 — Verify containers"
if [ "$DRY_RUN" = false ]; then
    sleep 8
    echo ""
    docker ps --format "  {{.Names}}\t{{.Image}}\t{{.Status}}"
    sleep 3
    if dig @127.0.0.1 google.com +short +time=3 &>/dev/null; then
        print_ok "DNS is still responding"
    else
        print_warn "DNS not responding — check: docker logs pihole"
    fi
else
    print_dry "docker ps"
    print_dry "dig @127.0.0.1 google.com"
    print_ok "Verification would be performed"
fi

# -----------------------------------------------------------------------------
print_step "Step 5 — Clean up old images"
run "docker image prune -f"
print_ok "Old images removed"

# -----------------------------------------------------------------------------
echo ""
echo "=============================================="
if [ "$DRY_RUN" = true ]; then
    echo -e "${CYAN}   Dry-run complete — no changes were made${NC}"
    echo ""
    echo "  Run the real update with:"
    echo "    bash update.sh"
else
    echo -e "${GREEN}   Update complete!${NC}"
fi
echo "=============================================="
echo ""
