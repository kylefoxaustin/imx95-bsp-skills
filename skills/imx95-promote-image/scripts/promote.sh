#!/bin/bash
# promote.sh — Stage i.MX 95 build artifacts for flashing
# Part of imx95-bsp-skills
#
# Usage:
#   promote.sh [--workspace <path>] [--tag <label>] [--dry-run]
#
# Options:
#   --workspace <path>   BSP workspace root (default: auto-detect)
#   --tag <label>        Optional tag appended to timestamp dir (e.g. "v1.2")
#   --dry-run            List artifacts without copying
#   -h, --help           Show this help

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

WORKSPACE=""
TAG=""
DRY_RUN=false

usage() {
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,1\}//'
    exit 0
}

log()  { echo -e "${CYAN}[promote]${NC} $*"; }
ok()   { echo -e "${GREEN}[promote] ✓${NC} $*"; }
warn() { echo -e "${YELLOW}[promote] ⚠${NC} $*"; }
err()  { echo -e "${RED}[promote] ✗${NC} $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace) WORKSPACE="$2"; shift 2 ;;
        --tag)       TAG="$2";       shift 2 ;;
        --dry-run)   DRY_RUN=true;   shift   ;;
        -h|--help)   usage ;;
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

# ── Read active target ────────────────────────────────────────────────────────
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
IMAGE_RECIPE="$(read_yaml image_recipe imx-image-full)"
PROFILE_NAME="$(read_yaml profile_name unknown)"
DEPLOY_DIR_REL="$(read_yaml deploy_dir build/tmp/deploy/images/$MACHINE)"
STAGING_REL="$(read_yaml staging_dir staging)"

DEPLOY_DIR="$WORKSPACE/$DEPLOY_DIR_REL"
STAGING_BASE="$WORKSPACE/$STAGING_REL"

# Build timestamped staging dir name
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
if [[ -n "$TAG" ]]; then
    STAGE_DIR="$STAGING_BASE/${TIMESTAMP}-${TAG}"
else
    STAGE_DIR="$STAGING_BASE/$TIMESTAMP"
fi

log "=== imx95-promote-image ==="
log "Profile      : $PROFILE_NAME"
log "MACHINE      : $MACHINE"
log "Image recipe : $IMAGE_RECIPE"
log "Deploy dir   : $DEPLOY_DIR"
log "Staging dir  : $STAGE_DIR"
echo ""

# ── Check deploy dir exists ───────────────────────────────────────────────────
[[ -d "$DEPLOY_DIR" ]] || err "Deploy directory not found: $DEPLOY_DIR — run imx95-build-source first"

# ── Find artifacts ────────────────────────────────────────────────────────────
declare -a ARTIFACTS=()

# Boot image
BOOT_IMG=$(find "$DEPLOY_DIR" -maxdepth 1 -name "imx-boot-${MACHINE}.bin" 2>/dev/null | head -1 || true)
[[ -n "$BOOT_IMG" ]] && ARTIFACTS+=("$BOOT_IMG") || \
    warn "Boot image not found: imx-boot-${MACHINE}.bin"

# WIC image (compressed preferred)
WIC_ZST=$(find "$DEPLOY_DIR" -maxdepth 1 -name "${IMAGE_RECIPE}-${MACHINE}.rootfs.wic.zst" 2>/dev/null | head -1 || true)
WIC=$(find "$DEPLOY_DIR" -maxdepth 1 -name "${IMAGE_RECIPE}-${MACHINE}.rootfs.wic" 2>/dev/null | head -1 || true)
if [[ -n "$WIC_ZST" ]]; then
    ARTIFACTS+=("$WIC_ZST")
elif [[ -n "$WIC" ]]; then
    ARTIFACTS+=("$WIC")
else
    warn "WIC image not found: ${IMAGE_RECIPE}-${MACHINE}.rootfs.wic[.zst]"
fi

# Kernel image
KERNEL=$(find "$DEPLOY_DIR" -maxdepth 1 -name "Image" 2>/dev/null | head -1 || true)
[[ -n "$KERNEL" ]] && ARTIFACTS+=("$KERNEL") || warn "Kernel image not found: Image"

# DTB
DTB=$(find "$DEPLOY_DIR" -maxdepth 1 -name "${MACHINE}.dtb" 2>/dev/null | head -1 || true)
[[ -n "$DTB" ]] && ARTIFACTS+=("$DTB") || warn "DTB not found: ${MACHINE}.dtb"

if [[ ${#ARTIFACTS[@]} -eq 0 ]]; then
    err "No artifacts found in $DEPLOY_DIR — run imx95-build-source first"
fi

log "Found ${#ARTIFACTS[@]} artifact(s):"
for f in "${ARTIFACTS[@]}"; do
    size=$(du -sh "$f" 2>/dev/null | cut -f1 || echo "?")
    echo "  $size  $(basename "$f")"
done
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    log "Dry run — no files copied."
    exit 0
fi

# ── Copy artifacts ────────────────────────────────────────────────────────────
mkdir -p "$STAGE_DIR"

for f in "${ARTIFACTS[@]}"; do
    log "Copying: $(basename "$f") ..."
    cp "$f" "$STAGE_DIR/"
done

# ── Generate manifest ─────────────────────────────────────────────────────────
MANIFEST="$STAGE_DIR/manifest.txt"
{
    echo "# imx95-bsp-skills artifact manifest"
    echo "# Generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "# Profile  : $PROFILE_NAME"
    echo "# MACHINE  : $MACHINE"
    echo "# Recipe   : $IMAGE_RECIPE"
    echo "# Source   : $DEPLOY_DIR"
    echo "#"
    echo "# Format: SHA256  filename"
    echo ""
    cd "$STAGE_DIR"
    sha256sum -- $(ls -1 | grep -v manifest.txt) 2>/dev/null || true
} > "$MANIFEST"

ok "Manifest written: $MANIFEST"
echo ""
cat "$MANIFEST"
echo ""

# ── Update latest symlink ─────────────────────────────────────────────────────
LATEST_LINK="$STAGING_BASE/latest"
ln -sfn "$STAGE_DIR" "$LATEST_LINK"
ok "Updated symlink: $LATEST_LINK → $STAGE_DIR"

echo ""
ok "=== promote complete ==="
echo ""
echo "Staged artifacts: $STAGE_DIR"
echo ""
echo "Next step: run imx95-flash-image to flash the board."
echo "  Tell Claude Code: 'flash the board'"
