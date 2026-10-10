#!/bin/bash
# init_source.sh — Source Yocto build environment and configure workspace
# Part of imx95-bsp-skills
#
# Usage:
#   init_source.sh [--workspace <path>] [--create-custom-layer] [--verify-only]
#
# Options:
#   --workspace <path>      BSP workspace root (default: auto-detect)
#   --create-custom-layer   Create meta-imx95-custom layer if absent
#   --verify-only           Only verify configuration, do not modify
#   -h, --help              Show this help
#
# NOTE: This script configures the workspace but cannot source the Yocto
# environment into the calling shell (sourcing only works in the same shell).
# After running this script, source the environment manually:
#   cd <workspace>/sources/poky
#   MACHINE=<machine> source oe-init-build-env ../../build

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Defaults ──────────────────────────────────────────────────────────────────
WORKSPACE=""
CREATE_CUSTOM_LAYER=false
VERIFY_ONLY=false

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,1\}//'
    exit 0
}

log()  { echo -e "${CYAN}[init-source]${NC} $*"; }
ok()   { echo -e "${GREEN}[init-source] ✓${NC} $*"; }
warn() { echo -e "${YELLOW}[init-source] ⚠${NC} $*"; }
err()  { echo -e "${RED}[init-source] ✗${NC} $*" >&2; exit 1; }

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace)           WORKSPACE="$2";           shift 2 ;;
        --create-custom-layer) CREATE_CUSTOM_LAYER=true; shift   ;;
        --verify-only)         VERIFY_ONLY=true;         shift   ;;
        -h|--help)             usage ;;
        *) err "Unknown argument: $1" ;;
    esac
done

# ── Locate workspace ──────────────────────────────────────────────────────────
find_workspace() {
    if [[ -n "$WORKSPACE" ]]; then echo "$WORKSPACE"; return; fi
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/targets/active_target.yaml" ]]; then
            echo "$dir"; return
        fi
        dir="$(dirname "$dir")"
    done
    echo "$PWD"
}

WORKSPACE="$(find_workspace)"
WORKSPACE="${WORKSPACE/#\~/$HOME}"

# ── Read active target ────────────────────────────────────────────────────────
ACTIVE_TARGET="$WORKSPACE/targets/active_target.yaml"
[[ -f "$ACTIVE_TARGET" ]] || err "No active target found at $ACTIVE_TARGET. Run imx95-init-target first."

read_yaml_field() {
    local field="$1"
    python3 -c "
import sys, re
with open('$ACTIVE_TARGET') as f:
    for line in f:
        m = re.match(r'\s*${field}\s*:\s*[\"\'](.*)[\"\']\s*$', line)
        if m: print(m.group(1)); sys.exit(0)
        m = re.match(r'\s*${field}\s*:\s*(.*)\s*$', line)
        if m:
            v = m.group(1).strip().strip('\"\'')
            if v and v != 'null': print(v)
            sys.exit(0)
" 2>/dev/null || true
}

MACHINE="$(read_yaml_field machine)"
DISTRO="$(read_yaml_field distro)"
PROFILE_NAME="$(read_yaml_field profile_name)"
BUILD_DIR_REL="$(read_yaml_field build_dir)"
CUSTOM_LAYER_REL="$(read_yaml_field custom_layer)"
OVERLAY_TRACKER_REL="$(read_yaml_field overlay_tracker)"

# Apply defaults
# shared guard — see lib/bsp_common.sh (one copy, not five)
_BSP_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." 2>/dev/null && pwd)/lib/bsp_common.sh"
# shellcheck source=/dev/null
[ -r "$_BSP_LIB" ] && source "$_BSP_LIB"
MACHINE="${MACHINE:-}"
# Refuse an empty MACHINE; warn on an unverified guess. Was a SILENT default of
# imx95-19x19-lpddr5-evk — a value ground-truth §7 marks [UNKNOWN] (1 fleet
# reference vs 68 for imx95-19x19-frdm-pro).
if declare -f bsp_machine_or_refuse >/dev/null 2>&1; then
    bsp_machine_or_refuse "$MACHINE" "source tree init" || exit 6
fi
DISTRO="${DISTRO:-fsl-imx-xwayland}"
PROFILE_NAME="${PROFILE_NAME:-unknown}"
BUILD_DIR_REL="${BUILD_DIR_REL:-build}"
CUSTOM_LAYER_REL="${CUSTOM_LAYER_REL:-sources/meta-imx95-custom}"
OVERLAY_TRACKER_REL="${OVERLAY_TRACKER_REL:-overlay-tracker}"

BUILD_DIR="$WORKSPACE/$BUILD_DIR_REL"
CUSTOM_LAYER="$WORKSPACE/$CUSTOM_LAYER_REL"
OVERLAY_TRACKER="$WORKSPACE/$OVERLAY_TRACKER_REL"
POKY_DIR="$WORKSPACE/sources/poky"

log "=== imx95-init-source ==="
log "Workspace    : $WORKSPACE"
log "MACHINE      : $MACHINE"
log "DISTRO       : $DISTRO"
log "Build dir    : $BUILD_DIR"
log "Custom layer : $CUSTOM_LAYER"
echo ""

# ── Check not root ────────────────────────────────────────────────────────────
check_not_root() {
    if [[ "$(id -u)" == "0" ]]; then
        err "Do not run bitbake as root. Switch to a non-root user and retry."
    fi
    ok "Running as non-root user: $(whoami)"
}

# ── Check poky exists ─────────────────────────────────────────────────────────
check_poky() {
    if [[ ! -f "$POKY_DIR/oe-init-build-env" ]]; then
        err "oe-init-build-env not found at $POKY_DIR. Run imx95-download-bsp first."
    fi
    ok "Poky found: $POKY_DIR"
}

# ── Configure local.conf ──────────────────────────────────────────────────────
configure_local_conf() {
    local conf="$BUILD_DIR/conf/local.conf"
    if [[ ! -f "$conf" ]]; then
        warn "local.conf not found — it will be created when you source oe-init-build-env"
        warn "Run: cd $POKY_DIR && MACHINE=$MACHINE DISTRO=$DISTRO source oe-init-build-env ../../$BUILD_DIR_REL"
        return
    fi

    log "Configuring $conf ..."

    local nproc
    nproc=$(nproc 2>/dev/null || echo 4)

    # Helper: set or replace a variable in local.conf
    set_conf_var() {
        local var="$1" val="$2"
        if grep -q "^${var}\s*=" "$conf" 2>/dev/null; then
            sed -i "s|^${var}\s*=.*|${var} = \"${val}\"|" "$conf"
        else
            echo "${var} = \"${val}\"" >> "$conf"
        fi
    }

    set_conf_var "MACHINE"           "$MACHINE"
    set_conf_var "DISTRO"            "$DISTRO"
    set_conf_var "BB_NUMBER_THREADS" "$nproc"
    set_conf_var "PARALLEL_MAKE"     "-j $nproc"
    set_conf_var "DL_DIR"            "$WORKSPACE/downloads"
    set_conf_var "SSTATE_DIR"        "$WORKSPACE/sstate-cache"
    set_conf_var "ACCEPT_FSL_EULA"   "1"

    ok "local.conf configured (MACHINE=$MACHINE, DISTRO=$DISTRO, threads=$nproc)"
}

# ── Configure bblayers.conf ───────────────────────────────────────────────────
configure_bblayers_conf() {
    local conf="$BUILD_DIR/conf/bblayers.conf"
    if [[ ! -f "$conf" ]]; then
        warn "bblayers.conf not found — will be created when you source oe-init-build-env"
        return
    fi

    if grep -q "meta-imx95-custom" "$conf"; then
        ok "meta-imx95-custom already in bblayers.conf"
    else
        log "Adding meta-imx95-custom to bblayers.conf ..."
        # Append before the closing quote of BBLAYERS
        sed -i "s|^\(BBLAYERS\s*?=\s*\"\)|\\1\n  $CUSTOM_LAYER \\\\|" "$conf" || \
        echo "  $CUSTOM_LAYER \\" >> "$conf"
        ok "meta-imx95-custom added to bblayers.conf"
    fi
}

# ── Create meta-imx95-custom layer ───────────────────────────────────────────
create_custom_layer() {
    if [[ -d "$CUSTOM_LAYER" ]]; then
        ok "meta-imx95-custom already exists: $CUSTOM_LAYER"
        return
    fi

    log "Creating meta-imx95-custom layer at $CUSTOM_LAYER ..."

    mkdir -p "$CUSTOM_LAYER/conf"
    mkdir -p "$CUSTOM_LAYER/recipes-kernel/linux/files/overlays"

    # layer.conf
    cat > "$CUSTOM_LAYER/conf/layer.conf" << 'LAYERCONF'
# meta-imx95-custom layer configuration
# This layer contains custom bbappend recipes and device tree overlays
# for the i.MX 95 BSP. Never modify upstream layers directly.

BBPATH .= ":${LAYERDIR}"
BBFILES += "${LAYERDIR}/recipes-*/*/*.bb \
            ${LAYERDIR}/recipes-*/*/*.bbappend"

BBFILE_COLLECTIONS += "imx95-custom"
BBFILE_PATTERN_imx95-custom = "^${LAYERDIR}/"
BBFILE_PRIORITY_imx95-custom = "10"

LAYERSERIES_COMPAT_imx95-custom = "scarthgap"
LAYERDEPENDS_imx95-custom = "core freescale-layer imx"
LAYERVERSION_imx95-custom = "1"
LAYERCONF

    # README
    cat > "$CUSTOM_LAYER/README" << 'README'
meta-imx95-custom
=================

Custom Yocto layer for i.MX 95 BSP customizations.

Rules:
- Never modify upstream layers (meta-imx, meta-freescale, poky).
- All kernel customizations go in recipes-kernel/linux/linux-imx_%.bbappend
- All device tree overlays go in recipes-kernel/linux/files/overlays/
- All DT overlay changes must be committed to overlay-tracker/ before building.

Managed by imx95-bsp-skills.
README

    # Skeleton linux-imx bbappend
    cat > "$CUSTOM_LAYER/recipes-kernel/linux/linux-imx_%.bbappend" << 'BBAPPEND'
# linux-imx bbappend — custom kernel configuration and DT overlays
# Managed by imx95-bsp-skills

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# Device tree overlay files — add entries here as overlays are created
# SRC_URI += "file://overlays/imx95-custom-pinmux.dts"

# Kernel config fragments — add entries here as needed
# SRC_URI += "file://imx95-custom.cfg"
BBAPPEND

    ok "meta-imx95-custom layer created at $CUSTOM_LAYER"
}

# ── Initialize overlay-tracker ────────────────────────────────────────────────
init_overlay_tracker() {
    mkdir -p "$OVERLAY_TRACKER"
    cd "$OVERLAY_TRACKER"

    if [[ ! -d ".git" ]]; then
        git init
        log "overlay-tracker git repo initialized"
    fi

    # Create initial empty commit if repo has no commits
    if ! git log --oneline -1 &>/dev/null 2>&1; then
        git commit --allow-empty \
            -m "init: overlay tracker for ${PROFILE_NAME}"
        ok "overlay-tracker initial commit created"
    else
        ok "overlay-tracker already initialized ($(git log --oneline -1))"
    fi

    cd "$WORKSPACE"
}

# ── Print sourcing instructions ───────────────────────────────────────────────
print_source_instructions() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  NEXT STEP: Source the Yocto environment in your shell"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  cd $POKY_DIR"
    echo "  MACHINE=$MACHINE DISTRO=$DISTRO source oe-init-build-env ../../$BUILD_DIR_REL"
    echo ""
    echo "  Then verify layers:"
    echo "  bitbake-layers show-layers"
    echo ""
    echo "  Then build:"
    echo "  bitbake <image_recipe>"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    check_not_root
    check_poky

    if [[ "$VERIFY_ONLY" == "true" ]]; then
        log "Verify-only mode — checking configuration..."
        [[ -f "$BUILD_DIR/conf/local.conf" ]]   && ok "local.conf exists"   || warn "local.conf missing"
        [[ -f "$BUILD_DIR/conf/bblayers.conf" ]] && ok "bblayers.conf exists" || warn "bblayers.conf missing"
        [[ -d "$CUSTOM_LAYER" ]]                 && ok "meta-imx95-custom exists" || warn "meta-imx95-custom missing"
        [[ -d "$OVERLAY_TRACKER/.git" ]]         && ok "overlay-tracker initialized" || warn "overlay-tracker not initialized"
        return
    fi

    configure_local_conf
    configure_bblayers_conf

    if [[ "$CREATE_CUSTOM_LAYER" == "true" ]]; then
        create_custom_layer
    fi

    init_overlay_tracker
    print_source_instructions

    echo ""
    ok "=== imx95-init-source complete ==="
}

main "$@"
