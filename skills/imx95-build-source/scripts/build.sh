#!/bin/bash
# build.sh — Run bitbake build for the active i.MX 95 target
# Part of imx95-bsp-skills
#
# Usage:
#   build.sh [--workspace <path>] [--kernel-only] [--dtb-only]
#            [--preflight-only] [--recipe <name>] [--clean <recipe>]
#
# Options:
#   --workspace <path>   BSP workspace root (default: auto-detect)
#   --kernel-only        Build linux-imx only (faster, for DT/driver changes)
#   --dtb-only           Force recompile and deploy DTBs only (fastest)
#   --preflight-only     Run pre-flight checks only, do not build
#   --recipe <name>      Override image recipe (default: from active target)
#   --clean <recipe>     Run cleansstate on recipe before building
#   -h, --help           Show this help

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

WORKSPACE=""
KERNEL_ONLY=false
DTB_ONLY=false
PREFLIGHT_ONLY=false
RECIPE_OVERRIDE=""
CLEAN_RECIPE=""
PREFLIGHT_ERRORS=0

usage() {
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,1\}//'
    exit 0
}

log()  { echo -e "${CYAN}[build]${NC} $*"; }
ok()   { echo -e "${GREEN}[build] ✓${NC} $*"; }
warn() { echo -e "${YELLOW}[build] ⚠${NC} $*"; }
err()  { echo -e "${RED}[build] ✗${NC} $*" >&2; }
fail() { err "$*"; PREFLIGHT_ERRORS=$((PREFLIGHT_ERRORS+1)); }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace)     WORKSPACE="$2";       shift 2 ;;
        --kernel-only)   KERNEL_ONLY=true;     shift   ;;
        --dtb-only)      DTB_ONLY=true;        shift   ;;
        --preflight-only) PREFLIGHT_ONLY=true; shift   ;;
        --recipe)        RECIPE_OVERRIDE="$2"; shift 2 ;;
        --clean)         CLEAN_RECIPE="$2";    shift 2 ;;
        -h|--help)       usage ;;
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

# ── Read active target ────────────────────────────────────────────────────────
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

# shared guard — see lib/bsp_common.sh (one copy, not five)
_BSP_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." 2>/dev/null && pwd)/lib/bsp_common.sh"
# shellcheck source=/dev/null
[ -r "$_BSP_LIB" ] && source "$_BSP_LIB"
MACHINE="$(read_yaml machine "")"
# Refuse an empty MACHINE; warn on an unverified guess. Was a SILENT default of
# imx95-19x19-lpddr5-evk — a value ground-truth §7 marks [UNKNOWN] (1 fleet
# reference vs 68 for imx95-19x19-frdm-pro).
if declare -f bsp_machine_or_refuse >/dev/null 2>&1; then
    bsp_machine_or_refuse "$MACHINE" "bitbake build" || exit 6
fi
IMAGE_RECIPE="$(read_yaml image_recipe imx-image-full)"
BUILD_DIR_REL="$(read_yaml build_dir build)"
OVERLAY_TRACKER_REL="$(read_yaml overlay_tracker overlay-tracker)"
DEPLOY_DIR_REL="$(read_yaml deploy_dir build/tmp/deploy/images/$MACHINE)"

[[ -n "$RECIPE_OVERRIDE" ]] && IMAGE_RECIPE="$RECIPE_OVERRIDE"

BUILD_DIR="$WORKSPACE/$BUILD_DIR_REL"
OVERLAY_TRACKER="$WORKSPACE/$OVERLAY_TRACKER_REL"
DEPLOY_DIR="$WORKSPACE/$DEPLOY_DIR_REL"

# ── Pre-flight checks ─────────────────────────────────────────────────────────
preflight() {
    echo ""
    log "=== Pre-flight checks ==="

    # 1. Active target exists
    if [[ -f "$ACTIVE_TARGET" ]]; then
        ok "Active target: $ACTIVE_TARGET"
    else
        fail "No active target at $ACTIVE_TARGET — run imx95-init-target"
    fi

    # 2. Not running as root
    if [[ "$(id -u)" == "0" ]]; then
        fail "Running as root — bitbake must not run as root"
    else
        ok "Running as non-root: $(whoami)"
    fi

    # 3. bitbake on PATH
    if command -v bitbake &>/dev/null; then
        ok "bitbake found: $(bitbake --version 2>&1 | head -1)"
    else
        fail "bitbake not on PATH — source oe-init-build-env first"
        echo "    cd $WORKSPACE/sources/poky"
        echo "    MACHINE=$MACHINE source oe-init-build-env ../../$BUILD_DIR_REL"
    fi

    # 4. local.conf MACHINE matches
    local conf="$BUILD_DIR/conf/local.conf"
    if [[ -f "$conf" ]]; then
        local conf_machine
        conf_machine=$(grep '^MACHINE\s*=' "$conf" 2>/dev/null | \
            grep -oP '"\K[^"]+' | head -1 || echo "")
        if [[ "$conf_machine" == "$MACHINE" ]]; then
            ok "MACHINE in local.conf: $conf_machine"
        elif [[ -z "$conf_machine" ]]; then
            warn "MACHINE not set in local.conf — will use environment variable"
        else
            fail "MACHINE mismatch: local.conf=$conf_machine, active target=$MACHINE"
            echo "    Run imx95-init-source to fix local.conf"
        fi
    else
        fail "local.conf not found at $conf — run imx95-init-source"
    fi

    # 5. overlay-tracker clean
    if [[ -d "$OVERLAY_TRACKER/.git" ]]; then
        local status
        status=$(git -C "$OVERLAY_TRACKER" status --porcelain 2>/dev/null || echo "")
        if [[ -z "$status" ]]; then
            ok "overlay-tracker: working tree clean"
        else
            fail "overlay-tracker has uncommitted changes — commit or discard before building"
            git -C "$OVERLAY_TRACKER" status --short 2>/dev/null | sed 's/^/    /'
        fi
    else
        warn "overlay-tracker not initialized — run imx95-init-source"
    fi

    # 6. Disk space
    local avail_gb
    avail_gb=$(df -BG "$WORKSPACE" 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G' || echo 0)
    if [[ "$avail_gb" -ge 80 ]]; then
        ok "Disk space: ${avail_gb} GB free"
    elif [[ "$avail_gb" -ge 50 ]]; then
        warn "Disk space: ${avail_gb} GB free (≥ 80 GB recommended for full build)"
    else
        fail "Disk space: ${avail_gb} GB free — need ≥ 50 GB for build"
    fi

    echo ""
    if [[ $PREFLIGHT_ERRORS -gt 0 ]]; then
        echo -e "${RED}${BOLD}Pre-flight FAILED: $PREFLIGHT_ERRORS error(s)${NC}"
        echo "Fix the errors above before building."
        return 1
    else
        echo -e "${GREEN}${BOLD}Pre-flight PASSED${NC}"
        return 0
    fi
}

# ── Report artifacts ──────────────────────────────────────────────────────────
report_artifacts() {
    echo ""
    log "=== Build Artifacts ==="
    if [[ -d "$DEPLOY_DIR" ]]; then
        find "$DEPLOY_DIR" -maxdepth 1 \
            \( -name "imx-boot*.bin" -o -name "*.wic.zst" -o -name "*.wic" \
               -o -name "Image" -o -name "*.dtb" -o -name "*.ext4" \) \
            -printf "  %f  (%s bytes)  [%TY-%Tm-%Td %TH:%TM]\n" 2>/dev/null | sort
        echo ""
        ok "Artifacts in: $DEPLOY_DIR"
        echo ""
        echo "Next step: run imx95-promote-image to stage artifacts for flashing."
    else
        warn "Deploy directory not found: $DEPLOY_DIR"
    fi
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    log "=== imx95-build-source ==="
    log "Workspace    : $WORKSPACE"
    log "MACHINE      : $MACHINE"
    log "Image recipe : $IMAGE_RECIPE"
    log "Build dir    : $BUILD_DIR"

    preflight || exit 1

    if [[ "$PREFLIGHT_ONLY" == "true" ]]; then
        log "Pre-flight only — not building."
        exit 0
    fi

    # Optional: clean a recipe first
    if [[ -n "$CLEAN_RECIPE" ]]; then
        log "Cleaning recipe: $CLEAN_RECIPE"
        bitbake "$CLEAN_RECIPE" -c cleansstate
        ok "Cleaned: $CLEAN_RECIPE"
    fi

    # Determine build command
    if [[ "$DTB_ONLY" == "true" ]]; then
        log "Building DTBs only (force compile + deploy)..."
        log "Running: bitbake linux-imx -c compile -f"
        bitbake linux-imx -c compile -f
        log "Running: bitbake linux-imx -c deploy -f"
        bitbake linux-imx -c deploy -f
        ok "DTB build complete"

    elif [[ "$KERNEL_ONLY" == "true" ]]; then
        log "Building kernel only..."
        log "Running: bitbake linux-imx"
        bitbake linux-imx
        ok "Kernel build complete"

    else
        log "Building full image: $IMAGE_RECIPE"
        log "Running: bitbake $IMAGE_RECIPE"
        log "(This may take 2–4 hours for a first build)"
        bitbake "$IMAGE_RECIPE"
        ok "Image build complete: $IMAGE_RECIPE"
    fi

    report_artifacts
}

main "$@"
