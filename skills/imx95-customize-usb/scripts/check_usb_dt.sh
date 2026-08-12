#!/bin/bash
# check_usb_dt.sh — Check current USB DT configuration in i.MX 95 overlays
# Part of imx95-bsp-skills
#
# Usage:
#   check_usb_dt.sh [--workspace <path>]
#
# Options:
#   --workspace <path>   BSP workspace root (default: auto-detect)
#   -h, --help           Show this help
#
# Reports:
#   - USB nodes found in overlay files
#   - Current dr_mode for each USB controller
#   - VBUS regulator assignments
#   - PHY status

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

WORKSPACE=""

usage() {
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,1\}//'
    exit 0
}

log()  { echo -e "${CYAN}[check-usb-dt]${NC} $*"; }
ok()   { echo -e "${GREEN}[check-usb-dt] ✓${NC} $*"; }
warn() { echo -e "${YELLOW}[check-usb-dt] ⚠${NC} $*"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace) WORKSPACE="$2"; shift 2 ;;
        -h|--help)   usage ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

find_workspace() {
    if [[ -n "$WORKSPACE" ]]; then echo "$WORKSPACE"; return; fi
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        [[ -f "$dir/targets/active_target.yaml" ]] && { echo "$dir"; return; }
        dir="$(dirname "$dir")"
    done
    echo "$PWD"
}

WORKSPACE="$(find_workspace)"
WORKSPACE="${WORKSPACE/#\~/$HOME}"

ACTIVE_TARGET="$WORKSPACE/targets/active_target.yaml"
read_yaml() {
    local field="$1" default="${2:-}"
    [[ -f "$ACTIVE_TARGET" ]] || { echo "$default"; return; }
    python3 -c "
import sys, re
with open('$ACTIVE_TARGET') as f:
    for line in f:
        m = re.match(r'\s*${field}\s*:\s*[\"\'](.*)[\"\']\s*$', line)
        if m: print(m.group(1)); sys.exit(0)
        m = re.match(r'\s*${field}\s*:\s*(.*)\s*$', line)
        if m:
            v = m.group(1).strip().strip('\"\'')
            if v and v != 'null': print(v); sys.exit(0)
print('${default}')
" 2>/dev/null || echo "$default"
}

DT_OVERLAY_REL="$(read_yaml dt_overlay_dir sources/meta-imx95-custom/recipes-kernel/linux/files/overlays)"
OVERLAY_DIR="$WORKSPACE/$DT_OVERLAY_REL"

echo ""
log "=== check-usb-dt ==="
log "Overlay dir: $OVERLAY_DIR"
echo ""

if [[ ! -d "$OVERLAY_DIR" ]]; then
    warn "Overlay directory not found: $OVERLAY_DIR"
    warn "Run imx95-derive-carrier first."
    exit 0
fi

# Find all DTS files
DTS_FILES=()
while IFS= read -r -d '' f; do
    DTS_FILES+=("$f")
done < <(find "$OVERLAY_DIR" -name "*.dts" -print0 2>/dev/null)

if [[ ${#DTS_FILES[@]} -eq 0 ]]; then
    warn "No .dts overlay files found in $OVERLAY_DIR"
    exit 0
fi

echo -e "${CYAN}  USB Node Summary${NC}"
echo "  ─────────────────────────────────────────────────────────"

# Check each USB-related node
USB_NODES=(usb3_0 usb3_phy0 dwc3_0 usbotg2 ci_hdrc_usb2 usbphynop1)

for node in "${USB_NODES[@]}"; do
    node_found=false
    for f in "${DTS_FILES[@]}"; do
        if grep -q "&${node}" "$f" 2>/dev/null; then
            node_found=true
            fname="$(basename "$f")"
            # Get status
            status=$(grep -A5 "&${node}" "$f" 2>/dev/null | grep -oP 'status\s*=\s*"\K[^"]+' | head -1 || echo "not set")
            # Get dr_mode if present
            dr_mode=$(grep -A10 "&${node}" "$f" 2>/dev/null | grep -oP 'dr_mode\s*=\s*"\K[^"]+' | head -1 || echo "")
            if [[ -n "$dr_mode" ]]; then
                ok "  &${node} in $fname — status=$status, dr_mode=$dr_mode"
            else
                ok "  &${node} in $fname — status=$status"
            fi
        fi
    done
    if [[ "$node_found" == "false" ]]; then
        echo "    &${node} — not configured in overlays (using BSP default)"
    fi
done

echo ""
echo -e "${CYAN}  VBUS Regulators${NC}"
echo "  ─────────────────────────────────────────────────────────"
vbus_found=false
for f in "${DTS_FILES[@]}"; do
    if grep -q "vbus" "$f" 2>/dev/null; then
        vbus_found=true
        fname="$(basename "$f")"
        grep -n "vbus" "$f" 2>/dev/null | sed "s/^/    $fname:/"
    fi
done
[[ "$vbus_found" == "false" ]] && echo "    No VBUS regulator overrides in overlays"

echo ""
echo -e "${CYAN}  i.MX 95 USB Architecture Reference${NC}"
echo "  ─────────────────────────────────────────────────────────"
echo "  USB1 (SuperSpeed OTG):  usb3_0 → dwc3_0 → usb3_phy0"
echo "    Recovery mode VID:PID: 1fc9:0146"
echo "    FRDM connector: J301 (USB-C)"
echo ""
echo "  USB2 (High-Speed Host): usbotg2 → ci_hdrc_usb2 → usbphynop1"
echo "    FRDM connector: J302 (USB-A)"
echo ""
