#!/bin/bash
# flash.sh — Flash i.MX 95 board artifacts using uuu
# Part of imx95-bsp-skills
#
# Usage:
#   flash.sh [--workspace <path>] [--staging-dir <path>] [--boot-device <emmc|sd>]
#            [--uuu-script <path>]
#
# Options:
#   --workspace <path>     BSP workspace root (default: auto-detect)
#   --staging-dir <path>   Staging directory (default: staging/latest)
#   --boot-device <dev>    Target boot device: emmc or sd (default: from active target)
#   --uuu-script <path>    Custom uuu script path (overrides built-in -b emmc_all)
#   -h, --help             Show this help
#
# SAFETY: This script MUST only be called after the user has typed "flash confirmed".
#         It does NOT prompt for confirmation itself — that is done by Claude Code
#         following the imx95-flash-image SKILL.md procedure.

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

WORKSPACE=""
STAGING_DIR_OVERRIDE=""
BOOT_DEVICE_OVERRIDE=""
UUU_SCRIPT_OVERRIDE=""

usage() {
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,1\}//'
    exit 0
}

log()  { echo -e "${CYAN}[flash]${NC} $*"; }
ok()   { echo -e "${GREEN}[flash] ✓${NC} $*"; }
warn() { echo -e "${YELLOW}[flash] ⚠${NC} $*"; }
err()  { echo -e "${RED}[flash] ✗${NC} $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace)   WORKSPACE="$2";            shift 2 ;;
        --staging-dir) STAGING_DIR_OVERRIDE="$2"; shift 2 ;;
        --boot-device) BOOT_DEVICE_OVERRIDE="$2"; shift 2 ;;
        --uuu-script)  UUU_SCRIPT_OVERRIDE="$2";  shift 2 ;;
        -h|--help)     usage ;;
        *) err "Unknown argument: $1" ;;
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
[[ -f "$ACTIVE_TARGET" ]] || err "No active target at $ACTIVE_TARGET"

read_yaml() {
    local field="$1" default="${2:-}"
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
UUU_SCRIPT_REL="$(read_yaml uuu_script "")"
IMAGE_RECIPE="$(read_yaml image_recipe imx-image-full)"
UUU_VERSION_MIN="$(read_yaml uuu_version_min 1.5.21)"

# Apply overrides
[[ -n "$BOOT_DEVICE_OVERRIDE" ]] && BOOT_DEVICE="$BOOT_DEVICE_OVERRIDE"
[[ -z "$BOOT_DEVICE" ]] && _boot_device_refuse

if [[ -n "$STAGING_DIR_OVERRIDE" ]]; then
    STAGING_DIR="$STAGING_DIR_OVERRIDE"
else
    STAGING_DIR="$WORKSPACE/$STAGING_REL/latest"
fi

# ── Verify uuu ────────────────────────────────────────────────────────────────
command -v uuu &>/dev/null || err "uuu not found on PATH — install from https://github.com/nxp-imx/mfgtools/releases"

UUU_VER=$(uuu --version 2>&1 | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1 || echo "0.0.0")
ok "uuu version: $UUU_VER"

# ── Find artifacts ────────────────────────────────────────────────────────────
BOOT_IMG=$(find "$STAGING_DIR" -maxdepth 1 -name "imx-boot-*.bin" 2>/dev/null | head -1 || true)
[[ -n "$BOOT_IMG" ]] || err "Boot image not found in $STAGING_DIR"

WIC_IMG=$(find "$STAGING_DIR" -maxdepth 1 \( -name "*.wic.zst" -o -name "*.wic" \) 2>/dev/null | head -1 || true)
[[ -n "$WIC_IMG" ]] || err "WIC image not found in $STAGING_DIR"

log "=== imx95-flash-image ==="
log "Board        : $BOARD_NAME"
log "MACHINE      : $MACHINE"
log "Boot device  : $BOOT_DEVICE"
log "Boot image   : $(basename "$BOOT_IMG")"
log "WIC image    : $(basename "$WIC_IMG")"
echo ""

# ── Determine flash command ───────────────────────────────────────────────────
if [[ -n "$UUU_SCRIPT_OVERRIDE" ]]; then
    # Custom uuu script
    [[ -f "$UUU_SCRIPT_OVERRIDE" ]] || err "uuu script not found: $UUU_SCRIPT_OVERRIDE"
    UUU_CMD="uuu $UUU_SCRIPT_OVERRIDE"
    log "Using custom uuu script: $UUU_SCRIPT_OVERRIDE"

elif [[ -n "$UUU_SCRIPT_REL" ]] && [[ -f "$WORKSPACE/$UUU_SCRIPT_REL" ]]; then
    # Target-specified uuu script
    UUU_CMD="uuu $WORKSPACE/$UUU_SCRIPT_REL"
    log "Using target uuu script: $WORKSPACE/$UUU_SCRIPT_REL"

else
    # Built-in uuu flash mode
    case "$BOOT_DEVICE" in
        emmc) UUU_MODE="emmc_all" ;;
        sd)   UUU_MODE="sd_all"   ;;
        *)    err "Unknown boot device: $BOOT_DEVICE (expected emmc or sd)" ;;
    esac
    UUU_CMD="uuu -b $UUU_MODE $BOOT_IMG $WIC_IMG"
    log "Using built-in uuu mode: -b $UUU_MODE"
fi

log "Flash command: $UUU_CMD"
echo ""

# ── Execute flash ─────────────────────────────────────────────────────────────
log "Starting uuu flash..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

START_TIME=$(date +%s)

if $UUU_CMD; then
    END_TIME=$(date +%s)
    ELAPSED=$((END_TIME - START_TIME))
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    ok "Flash SUCCEEDED in ${ELAPSED}s"
    echo ""
    echo -e "${BOLD}Post-flash steps:${NC}"
    echo "  1. Power OFF the board"
    echo "  2. Set SW1 back to eMMC boot: [1]=ON [2]=OFF [3]=OFF [4]=OFF"
    echo "  3. Disconnect and reconnect power"
    echo "  4. Run imx95-validate-image to verify the board boots correctly"
    echo ""
else
    FLASH_EXIT=$?
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    err "Flash FAILED (uuu exit code: $FLASH_EXIT)"
    echo ""
    echo "Troubleshooting:"
    echo "  - Verify board is still in recovery mode: uuu -lsusb"
    echo "  - Check USB cable connection to J301"
    echo "  - Try a different USB port or cable"
    echo "  - Verify uuu version >= $UUU_VERSION_MIN: uuu --version"
    echo "  - Check dmesg for USB errors: dmesg | tail -20"
    exit 1
fi
