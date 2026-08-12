#!/bin/bash
# download_bsp.sh — Initialize and sync the NXP i.MX 95 Yocto BSP
# Part of imx95-bsp-skills
#
# Usage:
#   download_bsp.sh [--workspace <path>] [--verify-only] [--jobs <n>]
#
# Options:
#   --workspace <path>   BSP workspace root (default: read from active_target.yaml)
#   --verify-only        Only verify an existing sync, do not download
#   --jobs <n>           Parallel repo sync jobs (default: 8)
#   --manifest-url <url> Override manifest URL
#   --manifest-branch <b> Override manifest branch
#   --manifest-file <f>  Override manifest file
#   -h, --help           Show this help

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
WORKSPACE=""
VERIFY_ONLY=false
JOBS=8
MANIFEST_URL="https://github.com/nxp-imx/imx-manifest"
MANIFEST_BRANCH="imx-linux-scarthgap"
MANIFEST_FILE="imx-6.6.52-2.2.0.xml"
ACTIVE_TARGET_YAML=""

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ── Usage ─────────────────────────────────────────────────────────────────────
usage() {
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,1\}//'
    exit 0
}

log()  { echo -e "${CYAN}[download-bsp]${NC} $*"; }
ok()   { echo -e "${GREEN}[download-bsp] ✓${NC} $*"; }
warn() { echo -e "${YELLOW}[download-bsp] ⚠${NC} $*"; }
err()  { echo -e "${RED}[download-bsp] ✗${NC} $*" >&2; exit 1; }

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace)      WORKSPACE="$2";        shift 2 ;;
        --verify-only)    VERIFY_ONLY=true;       shift   ;;
        --jobs)           JOBS="$2";              shift 2 ;;
        --manifest-url)   MANIFEST_URL="$2";      shift 2 ;;
        --manifest-branch) MANIFEST_BRANCH="$2"; shift 2 ;;
        --manifest-file)  MANIFEST_FILE="$2";     shift 2 ;;
        -h|--help)        usage ;;
        *) err "Unknown argument: $1" ;;
    esac
done

# ── Locate workspace ──────────────────────────────────────────────────────────
find_workspace() {
    # Try --workspace arg first, then active_target.yaml, then CWD
    if [[ -n "$WORKSPACE" ]]; then
        echo "$WORKSPACE"
        return
    fi

    # Search upward for targets/active_target.yaml
    local dir="$PWD"
    while [[ "$dir" != "/" ]]; do
        if [[ -f "$dir/targets/active_target.yaml" ]]; then
            echo "$dir"
            return
        fi
        dir="$(dirname "$dir")"
    done

    # Fall back to CWD
    echo "$PWD"
}

WORKSPACE="$(find_workspace)"
WORKSPACE="${WORKSPACE/#\~/$HOME}"
log "Workspace: $WORKSPACE"

# ── Read active target if present ─────────────────────────────────────────────
ACTIVE_TARGET_YAML="$WORKSPACE/targets/active_target.yaml"
if [[ -f "$ACTIVE_TARGET_YAML" ]]; then
    log "Reading active target: $ACTIVE_TARGET_YAML"
    # Extract fields with python3 (avoids yq dependency)
    _read_yaml() {
        python3 -c "
import sys, re
key = sys.argv[1]
with open('$ACTIVE_TARGET_YAML') as f:
    for line in f:
        m = re.match(r'\s*' + re.escape(key) + r'\s*:\s*[\"\'](.*)[\"\']\s*$', line)
        if m:
            print(m.group(1))
            sys.exit(0)
        m = re.match(r'\s*' + re.escape(key) + r'\s*:\s*(.*)\s*$', line)
        if m:
            val = m.group(1).strip().strip('\"\'')
            if val and val != 'null':
                print(val)
            sys.exit(0)
" "$1" 2>/dev/null || true
    }

    _url="$(_read_yaml bsp_manifest_url)"
    _branch="$(_read_yaml bsp_manifest_branch)"
    _file="$(_read_yaml bsp_manifest_file)"
    _ws="$(_read_yaml workspace_root)"

    [[ -n "$_url"    ]] && MANIFEST_URL="$_url"
    [[ -n "$_branch" ]] && MANIFEST_BRANCH="$_branch"
    [[ -n "$_file"   ]] && MANIFEST_FILE="$_file"
    [[ -n "$_ws"     ]] && WORKSPACE="${_ws/#\~/$HOME}"
fi

# ── Check required tools ──────────────────────────────────────────────────────
check_tools() {
    local missing=()
    for tool in git python3 curl; do
        command -v "$tool" &>/dev/null || missing+=("$tool")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        err "Missing required tools: ${missing[*]}"
    fi
    ok "Required tools present (git, python3, curl)"
}

# ── Ensure repo tool ──────────────────────────────────────────────────────────
ensure_repo() {
    if command -v repo &>/dev/null; then
        ok "repo tool found: $(command -v repo)"
        return
    fi

    warn "repo tool not found on PATH — installing to ~/bin/repo"
    mkdir -p "$HOME/bin"
    curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo \
        -o "$HOME/bin/repo"
    chmod a+x "$HOME/bin/repo"
    export PATH="$HOME/bin:$PATH"

    if ! command -v repo &>/dev/null; then
        err "Failed to install repo. Add ~/bin to PATH and retry."
    fi
    ok "repo installed: $(repo --version 2>&1 | head -1)"
}

# ── Check disk space ──────────────────────────────────────────────────────────
check_disk_space() {
    local available_kb
    available_kb=$(df -k "$WORKSPACE" 2>/dev/null | awk 'NR==2{print $4}' || echo 0)
    local available_gb=$(( available_kb / 1024 / 1024 ))
    if [[ $available_gb -lt 50 ]]; then
        warn "Only ${available_gb} GB free in $WORKSPACE — BSP sync + build needs ≥ 50 GB"
        warn "Proceeding anyway; build may fail if space runs out."
    else
        ok "Disk space: ${available_gb} GB free"
    fi
}

# ── Verify existing sync ──────────────────────────────────────────────────────
verify_sync() {
    log "Verifying BSP sync in $WORKSPACE/sources/ ..."
    local expected_layers=(
        meta-imx
        meta-freescale
        poky
        linux-imx
        u-boot-imx
    )
    local missing=()
    for layer in "${expected_layers[@]}"; do
        if [[ -d "$WORKSPACE/sources/$layer" ]]; then
            local sha
            sha=$(git -C "$WORKSPACE/sources/$layer" rev-parse --short HEAD 2>/dev/null || echo "unknown")
            ok "  sources/$layer  @ $sha"
        else
            warn "  sources/$layer  MISSING"
            missing+=("$layer")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        warn "Missing layers: ${missing[*]} — run without --verify-only to sync"
        return 1
    fi

    # Show disk usage
    local usage
    usage=$(du -sh "$WORKSPACE/sources" 2>/dev/null | cut -f1 || echo "unknown")
    ok "sources/ total size: $usage"
    return 0
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo ""
    log "=== imx95-download-bsp ==="
    log "Manifest URL   : $MANIFEST_URL"
    log "Manifest branch: $MANIFEST_BRANCH"
    log "Manifest file  : $MANIFEST_FILE"
    log "Workspace      : $WORKSPACE"
    echo ""

    check_tools

    if [[ "$VERIFY_ONLY" == "true" ]]; then
        verify_sync
        exit $?
    fi

    ensure_repo
    check_disk_space

    # Create workspace if needed
    mkdir -p "$WORKSPACE"
    cd "$WORKSPACE"

    # repo init
    log "Running: repo init -u $MANIFEST_URL -b $MANIFEST_BRANCH -m $MANIFEST_FILE"
    repo init \
        -u "$MANIFEST_URL" \
        -b "$MANIFEST_BRANCH" \
        -m "$MANIFEST_FILE" \
        --no-repo-verify \
        || err "repo init failed. Check network connectivity and proxy settings."

    ok "repo init complete"

    # repo sync
    log "Running: repo sync -j${JOBS} --no-clone-bundle"
    log "This downloads ~10–20 GB and may take 30–60 minutes..."
    echo ""

    if ! repo sync -j"${JOBS}" --no-clone-bundle; then
        warn "repo sync failed with -j${JOBS}. Retrying with -j4..."
        repo sync -j4 --no-clone-bundle \
            || err "repo sync failed. Check network and disk space, then retry."
    fi

    ok "repo sync complete"
    echo ""

    # Verify
    verify_sync

    echo ""
    ok "=== BSP download complete ==="
    echo ""
    echo "Next step: run imx95-init-source to configure the Yocto build environment."
    echo "  Tell Claude Code: 'source the Yocto environment'"
}

main "$@"
