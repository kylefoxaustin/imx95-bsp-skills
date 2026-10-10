#!/bin/bash
# preflight_flash.sh — Pre-flight checks before flashing i.MX 95 board with uuu
# Part of imx95-bsp-skills
#
# Usage:
#   preflight_flash.sh [--workspace <path>] [--staging-dir <path>]
#
# Options:
#   --workspace <path>     BSP workspace root (default: auto-detect)
#   --staging-dir <path>   Staging directory (default: staging/latest)
#   -h, --help             Show this help
#
# Checks performed:
#   1. uuu is installed and version >= 1.5.21
#   2. Board detected at USB VID:PID 1fc9:0146 (recovery mode)
#   3. Staging directory exists with required artifacts
#   4. SHA256 checksums match manifest.txt

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

WORKSPACE=""
STAGING_DIR_OVERRIDE=""
ERRORS=0
WARNINGS=0

usage() {
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,1\}//'
    exit 0
}

log()  { echo -e "${CYAN}[preflight-flash]${NC} $*"; }
ok()   { echo -e "${GREEN}[preflight-flash] ✓${NC} $*"; }
warn() { echo -e "${YELLOW}[preflight-flash] ⚠${NC} $*"; WARNINGS=$((WARNINGS+1)); }
fail() { echo -e "${RED}[preflight-flash] ✗${NC} $*"; ERRORS=$((ERRORS+1)); }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace)   WORKSPACE="$2";           shift 2 ;;
        --staging-dir) STAGING_DIR_OVERRIDE="$2"; shift 2 ;;
        -h|--help)     usage ;;
        *) echo "Unknown argument: $1" >&2; exit 1 ;;
    esac
done

# ── Locate workspace ──────────────────────────────────────────────────────────
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

MACHINE="$(read_yaml machine imx95-19x19-lpddr5-evk)"
BOARD_NAME="$(read_yaml name FRDM-IMX95)"

# ─────────────────────────────────────────────────────────────────────────────
# 🔴 BOOT DEVICE IS NOT DEFAULTED. IT IS REFUSED UNTIL STATED.
#
# This used to read:  BOOT_DEVICE="$(read_yaml boot_device emmc)"
# — a silent default of `emmc`, with NOTHING anywhere in this skill verifying
# that the target matches the device the board actually boots from.
#
# MEASURED on the fleet FRDM-IMX95-PRO (2026-10-09): `/` is /dev/mmcblk1p2 on
# the 58 G SD CARD. The eMMC (mmcblk0) holds a SEPARATE, NON-LIVE rootfs at
# mmcblk0p2. So on that board the silent default produced:
#
#   flash --boot-device emmc  (the default)
#     -> writes the eMMC, which the board DOES NOT BOOT FROM
#     -> uuu reports success, the board reboots into the OLD SD image
#     -> NO SIGNAL that anything is wrong. The operator concludes the new
#        image is live. It is not.
#
#   flash --boot-device sd
#     -> DESTROYS THE RUNNING SYSTEM on that board
#
# Two opposite catastrophes selected by one unstated default.
#
# ⚠️ AND IT CANNOT BE AUTO-DETECTED HERE. At flash time the board is in USB
# serial-download (recovery) mode, so it cannot be queried — `findmnt` on the
# HOST describes the host, not the target. That is precisely why this refuses
# instead of guessing: there is no authoritative referent available at the
# moment of the decision, and the convenient one (a default string in a YAML)
# is exactly the wrong thing to trust. See imx95-device-skills
# references/imx95-ground-truth.md §0, reestablish-the-referent-law.
_boot_device_refuse() {
    echo "FATAL: boot_device is not set, and this skill will NOT guess." >&2
    echo "" >&2
    echo "  Set it explicitly:  --boot-device emmc   |   --boot-device sd" >&2
    echo "  or in targets/active_target.yaml:  boot_device: emmc|sd" >&2
    echo "" >&2
    echo "ESTABLISH IT FIRST, WHILE THE BOARD IS STILL BOOTED:" >&2
    echo "    ssh <board> 'findmnt -no SOURCE /'" >&2
    echo "  mmcblk0p2 -> the eMMC is live   => --boot-device emmc" >&2
    echo "  mmcblk1p2 -> the SD card is live => --boot-device sd" >&2
    echo "" >&2
    echo "On the fleet FRDM-IMX95-PRO this reads /dev/mmcblk1p2 (SD) [MEASURED" >&2
    echo "2026-10-09], so --boot-device emmc there writes a device the board" >&2
    echo "does NOT boot from: uuu reports success and nothing changes." >&2
    echo "" >&2
    echo "Once in USB recovery mode the board CANNOT be queried, which is why" >&2
    echo "this must be known before you start." >&2
    exit 5
}

BOOT_DEVICE="$(read_yaml boot_device "")"
STAGING_REL="$(read_yaml staging_dir staging)"
UUU_VERSION_MIN="$(read_yaml uuu_version_min 1.5.21)"
USB_VID_PID="$(read_yaml usb_vid_pid 1fc9:0146)"

if [[ -n "$STAGING_DIR_OVERRIDE" ]]; then
    STAGING_DIR="$STAGING_DIR_OVERRIDE"
else
    STAGING_DIR="$WORKSPACE/$STAGING_REL/latest"
fi

echo ""
log "=== preflight-flash ==="
log "Board        : $BOARD_NAME"
log "MACHINE      : $MACHINE"
[[ -z "$BOOT_DEVICE" ]] && _boot_device_refuse
log "Boot device  : $BOOT_DEVICE"
log "Staging dir  : $STAGING_DIR"
log "USB VID:PID  : $USB_VID_PID"
echo ""

# ── Check 1: uuu installed ────────────────────────────────────────────────────
log "Check 1: uuu installed and version >= $UUU_VERSION_MIN"
if ! command -v uuu &>/dev/null; then
    fail "uuu not found on PATH"
    echo "    Install from: https://github.com/nxp-imx/mfgtools/releases"
    echo "    sudo install -m 755 uuu /usr/local/bin/uuu"
else
    UUU_VER=$(uuu --version 2>&1 | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1 || echo "0.0.0")
    # Version comparison using python3
    VER_OK=$(python3 -c "
from packaging.version import Version
try:
    print('ok' if Version('$UUU_VER') >= Version('$UUU_VERSION_MIN') else 'old')
except:
    # fallback: simple string compare
    print('ok' if '$UUU_VER' >= '$UUU_VERSION_MIN' else 'old')
" 2>/dev/null || echo "ok")
    if [[ "$VER_OK" == "ok" ]]; then
        ok "uuu version: $UUU_VER (>= $UUU_VERSION_MIN)"
    else
        fail "uuu version $UUU_VER is too old — need >= $UUU_VERSION_MIN"
        echo "    Download from: https://github.com/nxp-imx/mfgtools/releases"
    fi
fi

# ── Check 2: Board in recovery mode ──────────────────────────────────────────
log "Check 2: Board detected at USB VID:PID $USB_VID_PID (recovery mode)"
BOARD_DETECTED=false

# Try uuu -lsusb first
if command -v uuu &>/dev/null; then
    if uuu -lsusb 2>/dev/null | grep -qi "$USB_VID_PID"; then
        BOARD_DETECTED=true
        ok "Board detected via uuu -lsusb (VID:PID $USB_VID_PID)"
    fi
fi

# Try lsusb as fallback
if [[ "$BOARD_DETECTED" == "false" ]] && command -v lsusb &>/dev/null; then
    if lsusb 2>/dev/null | grep -qi "${USB_VID_PID/:/.*}"; then
        BOARD_DETECTED=true
        ok "Board detected via lsusb (VID:PID $USB_VID_PID)"
    fi
fi

if [[ "$BOARD_DETECTED" == "false" ]]; then
    fail "Board NOT detected at VID:PID $USB_VID_PID"
    echo ""
    echo "    Put the board in USB Serial Download (recovery) mode:"
    echo "    1. Power OFF the board"
    echo "    2. Set SW1: [1]=OFF [2]=OFF [3]=OFF [4]=OFF  (USB boot)"
    echo "    3. Connect USB-C to J301 (USB OTG port)"
    echo "    4. Power ON the board"
    echo "    5. Run: uuu -lsusb  (should show SDP: $USB_VID_PID)"
    echo ""
fi

# ── Check 3: Staging directory and artifacts ──────────────────────────────────
log "Check 3: Staging directory and artifacts"
if [[ ! -d "$STAGING_DIR" ]]; then
    fail "Staging directory not found: $STAGING_DIR"
    echo "    Run imx95-promote-image first"
else
    ok "Staging directory: $STAGING_DIR"

    # Check for boot image
    BOOT_IMG=$(find "$STAGING_DIR" -maxdepth 1 -name "imx-boot-*.bin" 2>/dev/null | head -1 || true)
    if [[ -n "$BOOT_IMG" ]]; then
        ok "Boot image: $(basename "$BOOT_IMG")"
    else
        fail "Boot image not found in $STAGING_DIR (imx-boot-*.bin)"
    fi

    # Check for WIC image
    WIC_IMG=$(find "$STAGING_DIR" -maxdepth 1 \( -name "*.wic.zst" -o -name "*.wic" \) 2>/dev/null | head -1 || true)
    if [[ -n "$WIC_IMG" ]]; then
        ok "WIC image: $(basename "$WIC_IMG")"
    else
        fail "WIC image not found in $STAGING_DIR (*.wic or *.wic.zst)"
    fi

    # Check manifest
    MANIFEST="$STAGING_DIR/manifest.txt"
    if [[ -f "$MANIFEST" ]]; then
        ok "Manifest: manifest.txt"
    else
        warn "manifest.txt not found — checksums cannot be verified"
    fi
fi

# ── Check 4: SHA256 checksum verification ─────────────────────────────────────
log "Check 4: SHA256 checksum verification"
if [[ -f "$STAGING_DIR/manifest.txt" ]] && command -v sha256sum &>/dev/null; then
    cd "$STAGING_DIR"
    # Extract checksum lines (skip comments)
    CHECKSUM_LINES=$(grep -v '^#' manifest.txt | grep -v '^$' || true)
    if [[ -n "$CHECKSUM_LINES" ]]; then
        if echo "$CHECKSUM_LINES" | sha256sum --check --quiet 2>/dev/null; then
            ok "All checksums verified"
        else
            fail "Checksum verification FAILED — artifacts may be corrupted"
            echo "    Re-run imx95-promote-image to re-stage artifacts"
        fi
    else
        warn "No checksum entries in manifest.txt"
    fi
    cd "$WORKSPACE"
else
    warn "Skipping checksum verification (no manifest or sha256sum not available)"
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ $ERRORS -gt 0 ]]; then
    echo -e "  ${RED}${BOLD}PRE-FLIGHT FAILED: $ERRORS error(s), $WARNINGS warning(s)${NC}"
    echo "  Fix all errors before flashing."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    exit 1
elif [[ $WARNINGS -gt 0 ]]; then
    echo -e "  ${YELLOW}${BOLD}PRE-FLIGHT PASSED WITH $WARNINGS WARNING(S)${NC}"
    echo "  Review warnings before proceeding."
else
    echo -e "  ${GREEN}${BOLD}PRE-FLIGHT PASSED — ready to flash${NC}"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
