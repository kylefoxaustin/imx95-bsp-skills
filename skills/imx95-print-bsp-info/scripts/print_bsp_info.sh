#!/bin/bash
# print_bsp_info.sh — Print i.MX 95 BSP workspace state summary
# Part of imx95-bsp-skills
#
# Usage:
#   print_bsp_info.sh [--workspace <path>] [--json]
#
# Options:
#   --workspace <path>   BSP workspace root (default: auto-detect)
#   --json               Output as JSON instead of human-readable
#   -h, --help           Show this help

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Defaults ──────────────────────────────────────────────────────────────────
WORKSPACE=""
JSON_OUTPUT=false

usage() {
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace) WORKSPACE="$2"; shift 2 ;;
        --json)      JSON_OUTPUT=true; shift ;;
        -h|--help)   usage ;;
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

# ── YAML reader ───────────────────────────────────────────────────────────────
ACTIVE_TARGET="$WORKSPACE/targets/active_target.yaml"

read_yaml() {
    local field="$1" default="${2:-}"
    if [[ ! -f "$ACTIVE_TARGET" ]]; then echo "$default"; return; fi
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

# ── Helper: check path ────────────────────────────────────────────────────────
path_status() {
    local p="${1/#\~/$HOME}"
    p="${p//<workspace>/$WORKSPACE}"
    [[ -e "$p" ]] && echo "[present]" || echo "[absent]"
}

# ── Helper: tool version ──────────────────────────────────────────────────────
tool_version() {
    local tool="$1"
    if ! command -v "$tool" &>/dev/null; then
        echo "NOT FOUND"
        return
    fi
    case "$tool" in
        uuu)     uuu --version 2>&1 | head -1 | grep -oP '[\d.]+' | head -1 ;;
        dtc)     dtc --version 2>&1 | grep -oP '[\d.]+' | head -1 ;;
        repo)    repo --version 2>&1 | grep -oP '[\d.]+' | head -1 ;;
        git)     git --version | grep -oP '[\d.]+' | head -1 ;;
        bitbake) bitbake --version 2>&1 | grep -oP '[\d.]+' | head -1 ;;
        python3) python3 --version 2>&1 | grep -oP '[\d.]+' | head -1 ;;
        *)       command -v "$tool" ;;
    esac
}

tool_ok() {
    local tool="$1" ver
    ver="$(tool_version "$tool")"
    if [[ "$ver" == "NOT FOUND" ]]; then
        echo -e "  ${RED}✗${NC} $tool : NOT FOUND"
    else
        echo -e "  ${GREEN}✓${NC} $tool : $ver"
    fi
}

# ── Separator ─────────────────────────────────────────────────────────────────
SEP="━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo -e "${BOLD}${SEP}${NC}"
    echo -e "${BOLD}  imx95-bsp-skills — Workspace Info${NC}"
    echo -e "${BOLD}${SEP}${NC}"

    # ── Active Target ──────────────────────────────────────────────────────────
    echo ""
    echo -e "${CYAN}  Active Target${NC}"
    if [[ -f "$ACTIVE_TARGET" ]]; then
        PROFILE_NAME="$(read_yaml profile_name unknown)"
        BOARD_NAME="$(read_yaml name unknown)"
        MACHINE="$(read_yaml machine unknown)"
        DISTRO="$(read_yaml distro unknown)"
        IMAGE_RECIPE="$(read_yaml image_recipe unknown)"
        BOOT_DEVICE="$(read_yaml boot_device unknown)"
        CUSTOM_CARRIER="$(read_yaml custom_carrier false)"
        BUILD_DIR_REL="$(read_yaml build_dir build)"
        CUSTOM_LAYER_REL="$(read_yaml custom_layer sources/meta-imx95-custom)"
        DT_OVERLAY_REL="$(read_yaml dt_overlay_dir sources/meta-imx95-custom/recipes-kernel/linux/files/overlays)"
        STAGING_REL="$(read_yaml staging_dir staging)"
        OVERLAY_TRACKER_REL="$(read_yaml overlay_tracker overlay-tracker)"
        DEPLOY_DIR_REL="$(read_yaml deploy_dir build/tmp/deploy/images/$MACHINE)"
        MANIFEST_URL="$(read_yaml bsp_manifest_url https://github.com/nxp-imx/imx-manifest)"
        MANIFEST_BRANCH="$(read_yaml bsp_manifest_branch imx-linux-scarthgap)"
        MANIFEST_FILE="$(read_yaml bsp_manifest_file imx-6.6.52-2.2.0.xml)"

        echo "    Profile      : $PROFILE_NAME"
        echo "    Board        : $BOARD_NAME"
        echo "    MACHINE      : $MACHINE"
        echo "    DISTRO       : $DISTRO"
        echo "    Image recipe : $IMAGE_RECIPE"
        echo "    Boot device  : $BOOT_DEVICE"
        echo "    Custom carrier: $CUSTOM_CARRIER"
    else
        echo -e "    ${YELLOW}⚠ No active target found at $ACTIVE_TARGET${NC}"
        echo "    Run: imx95-init-target"
        MACHINE="unknown"
        BUILD_DIR_REL="build"
        CUSTOM_LAYER_REL="sources/meta-imx95-custom"
        DT_OVERLAY_REL="sources/meta-imx95-custom/recipes-kernel/linux/files/overlays"
        STAGING_REL="staging"
        OVERLAY_TRACKER_REL="overlay-tracker"
        DEPLOY_DIR_REL="build/tmp/deploy/images/unknown"
        MANIFEST_URL="https://github.com/nxp-imx/imx-manifest"
        MANIFEST_BRANCH="imx-linux-scarthgap"
        MANIFEST_FILE="imx-6.6.52-2.2.0.xml"
    fi

    # ── BSP Manifest ──────────────────────────────────────────────────────────
    echo ""
    echo -e "${CYAN}  BSP Manifest${NC}"
    echo "    URL    : $MANIFEST_URL"
    echo "    Branch : $MANIFEST_BRANCH"
    echo "    File   : $MANIFEST_FILE"

    # ── Workspace Paths ───────────────────────────────────────────────────────
    echo ""
    echo -e "${CYAN}  Workspace Paths${NC}"
    echo "    Root         : $WORKSPACE"
    echo "    Sources      : sources/  $(path_status "$WORKSPACE/sources")"
    echo "    Build dir    : $BUILD_DIR_REL/  $(path_status "$WORKSPACE/$BUILD_DIR_REL")"
    echo "    Custom layer : $CUSTOM_LAYER_REL/  $(path_status "$WORKSPACE/$CUSTOM_LAYER_REL")"
    echo "    Overlay dir  : $DT_OVERLAY_REL/"
    echo "    Staging dir  : $STAGING_REL/  $(path_status "$WORKSPACE/$STAGING_REL")"

    # ── Layer Stack ───────────────────────────────────────────────────────────
    echo ""
    echo -e "${CYAN}  Layer Stack${NC}"
    local bblayers_conf="$WORKSPACE/$BUILD_DIR_REL/conf/bblayers.conf"
    if [[ -f "$bblayers_conf" ]]; then
        grep -E '^\s+/' "$bblayers_conf" 2>/dev/null | \
            awk '{print "    " $1}' | head -20 || \
            echo "    (run bitbake-layers show-layers for full list)"
    else
        echo "    (build dir not initialized — run imx95-init-source)"
    fi

    # ── Overlay Tracker ───────────────────────────────────────────────────────
    echo ""
    echo -e "${CYAN}  Overlay Tracker${NC}"
    local ot="$WORKSPACE/$OVERLAY_TRACKER_REL"
    if [[ -d "$ot/.git" ]]; then
        local status
        status=$(git -C "$ot" status --porcelain 2>/dev/null || echo "")
        if [[ -n "$status" ]]; then
            echo -e "    ${YELLOW}⚠ Uncommitted changes:${NC}"
            git -C "$ot" status --short 2>/dev/null | sed 's/^/    /'
        else
            echo "    Working tree: clean"
        fi
        echo "    Last 5 commits:"
        git -C "$ot" log --oneline -5 2>/dev/null | sed 's/^/      /' || \
            echo "      (no commits yet)"
    else
        echo "    (not initialized — run imx95-init-source)"
    fi

    # ── Build Artifacts ───────────────────────────────────────────────────────
    echo ""
    echo -e "${CYAN}  Build Artifacts ($DEPLOY_DIR_REL/)${NC}"
    local deploy_dir="$WORKSPACE/$DEPLOY_DIR_REL"
    if [[ -d "$deploy_dir" ]]; then
        local artifacts
        artifacts=$(find "$deploy_dir" -maxdepth 1 \
            \( -name "imx-boot*.bin" -o -name "*.wic.zst" -o -name "*.wic" \
               -o -name "Image" -o -name "*.dtb" \) \
            -printf "    %f  [%TY-%Tm-%Td %TH:%TM]\n" 2>/dev/null | sort)
        if [[ -n "$artifacts" ]]; then
            echo "$artifacts"
        else
            echo "    (no artifacts yet — run imx95-build-source)"
        fi
    else
        echo "    (deploy dir absent — run imx95-build-source)"
    fi

    # ── Host Tools ────────────────────────────────────────────────────────────
    echo ""
    echo -e "${CYAN}  Host Tools${NC}"
    tool_ok uuu
    tool_ok dtc
    tool_ok repo
    tool_ok git
    tool_ok python3
    if command -v bitbake &>/dev/null; then
        tool_ok bitbake
    else
        echo -e "  ${YELLOW}⚠${NC} bitbake : not on PATH (source oe-init-build-env first)"
    fi

    # ── Disk Space ────────────────────────────────────────────────────────────
    echo ""
    echo -e "${CYAN}  Disk Space${NC}"
    local avail total
    avail=$(df -BG "$WORKSPACE" 2>/dev/null | awk 'NR==2{print $4}' | tr -d 'G' || echo "?")
    total=$(df -BG "$WORKSPACE" 2>/dev/null | awk 'NR==2{print $2}' | tr -d 'G' || echo "?")
    if [[ "$avail" != "?" ]] && [[ "$avail" -lt 50 ]]; then
        echo -e "    ${YELLOW}⚠ ${avail} GB free of ${total} GB — build needs ≥ 50 GB${NC}"
    else
        echo "    ${avail} GB free of ${total} GB"
    fi

    echo ""
    echo -e "${BOLD}${SEP}${NC}"
    echo ""
}

main "$@"
