#!/bin/bash
# validate.sh — Post-flash validation for i.MX 95 board
# Part of imx95-bsp-skills
#
# Usage:
#   validate.sh [--workspace <path>] [--ssh-host <ip>] [--ssh-user <user>]
#               [--ssh-key <path>] [--static-only] [--serial <device>]
#
# Options:
#   --workspace <path>   BSP workspace root (default: auto-detect)
#   --ssh-host <ip>      Board IP address or hostname for SSH checks
#   --ssh-user <user>    SSH username (default: root)
#   --ssh-key <path>     SSH private key path (default: ~/.ssh/id_rsa)
#   --static-only        Run host-side static checks only (no board connection)
#   --serial <device>    Serial device for console checks (e.g. /dev/ttyUSB0)
#   -h, --help           Show this help

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

WORKSPACE=""
SSH_HOST=""
SSH_USER="root"
SSH_KEY="${HOME}/.ssh/id_rsa"
STATIC_ONLY=false
SERIAL_DEV=""

PASS=0
FAIL=0
WARN=0

usage() {
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,1\}//'
    exit 0
}

log()    { echo -e "${CYAN}[validate]${NC} $*"; }
pass()   { echo -e "  ${GREEN}[PASS]${NC} $*"; PASS=$((PASS+1)); }
fail()   { echo -e "  ${RED}[FAIL]${NC} $*"; FAIL=$((FAIL+1)); }
skip()   { echo -e "  ${YELLOW}[SKIP]${NC} $*"; }
section(){ echo ""; echo -e "${BOLD}── $* ──${NC}"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace)   WORKSPACE="$2";   shift 2 ;;
        --ssh-host)    SSH_HOST="$2";    shift 2 ;;
        --ssh-user)    SSH_USER="$2";    shift 2 ;;
        --ssh-key)     SSH_KEY="$2";     shift 2 ;;
        --static-only) STATIC_ONLY=true; shift   ;;
        --serial)      SERIAL_DEV="$2";  shift 2 ;;
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
IMAGE_RECIPE="$(read_yaml image_recipe imx-image-full)"
STAGING_REL="$(read_yaml staging_dir staging)"
DEPLOY_DIR_REL="$(read_yaml deploy_dir build/tmp/deploy/images/$MACHINE)"
PROFILE_NAME="$(read_yaml profile_name unknown)"

STAGING_DIR="$WORKSPACE/$STAGING_REL/latest"
DEPLOY_DIR="$WORKSPACE/$DEPLOY_DIR_REL"

# ── SSH helper ────────────────────────────────────────────────────────────────
ssh_cmd() {
    local cmd="$1"
    local ssh_opts="-o ConnectTimeout=10 -o StrictHostKeyChecking=no -o BatchMode=yes"
    if [[ -f "$SSH_KEY" ]]; then
        ssh_opts="$ssh_opts -i $SSH_KEY"
    fi
    ssh $ssh_opts "${SSH_USER}@${SSH_HOST}" "$cmd" 2>/dev/null
}

ssh_available() {
    [[ -n "$SSH_HOST" ]] && ssh_cmd "echo ok" &>/dev/null 2>&1
}

# ── Static checks ─────────────────────────────────────────────────────────────
static_checks() {
    section "Static Checks (host-side)"

    # 1. Active target
    if [[ -f "$ACTIVE_TARGET" ]]; then
        pass "Active target: $PROFILE_NAME ($MACHINE)"
    else
        fail "No active target found"
    fi

    # 2. Staging manifest checksums
    MANIFEST="$STAGING_DIR/manifest.txt"
    if [[ -f "$MANIFEST" ]]; then
        cd "$STAGING_DIR"
        if grep -v '^#' manifest.txt | grep -v '^$' | sha256sum --check --quiet 2>/dev/null; then
            pass "Staging artifact checksums verified"
        else
            fail "Staging artifact checksum mismatch — re-run imx95-promote-image"
        fi
        cd "$WORKSPACE"
    else
        skip "No manifest.txt in $STAGING_DIR — run imx95-promote-image"
    fi

    # 3. DTB inspection
    DTB_FILE=$(find "$STAGING_DIR" -maxdepth 1 -name "*.dtb" 2>/dev/null | head -1 || \
               find "$DEPLOY_DIR" -maxdepth 1 -name "${MACHINE}.dtb" 2>/dev/null | head -1 || true)
    if [[ -n "$DTB_FILE" ]] && command -v fdtdump &>/dev/null; then
        MODEL=$(fdtdump "$DTB_FILE" 2>/dev/null | grep -oP '(?<=model = ")[^"]+' | head -1 || echo "")
        if [[ -n "$MODEL" ]]; then
            pass "DTB model string: $MODEL"
        else
            fail "Could not read model string from DTB: $DTB_FILE"
        fi
    elif [[ -n "$DTB_FILE" ]]; then
        skip "fdtdump not available — install device-tree-compiler to inspect DTB"
    else
        skip "DTB not found in staging or deploy dir"
    fi

    # 4. overlay-tracker clean
    OT="$WORKSPACE/$(read_yaml overlay_tracker overlay-tracker)"
    if [[ -d "$OT/.git" ]]; then
        STATUS=$(git -C "$OT" status --porcelain 2>/dev/null || echo "")
        if [[ -z "$STATUS" ]]; then
            pass "overlay-tracker: working tree clean"
        else
            fail "overlay-tracker has uncommitted changes"
        fi
        LAST_COMMIT=$(git -C "$OT" log --oneline -1 2>/dev/null || echo "no commits")
        pass "overlay-tracker last commit: $LAST_COMMIT"
    else
        skip "overlay-tracker not initialized"
    fi
}

# ── Dynamic checks via SSH ────────────────────────────────────────────────────
dynamic_checks_ssh() {
    section "Dynamic Checks (SSH: ${SSH_USER}@${SSH_HOST})"

    # Test SSH connectivity
    if ! ssh_available; then
        fail "Cannot connect to ${SSH_USER}@${SSH_HOST} — check board is booted and on network"
        return
    fi
    pass "SSH connection to ${SSH_USER}@${SSH_HOST}"

    # Kernel version
    KVER=$(ssh_cmd "uname -r" 2>/dev/null || echo "")
    if [[ -n "$KVER" ]]; then
        if echo "$KVER" | grep -q "^6\.6"; then
            pass "Kernel version: $KVER (6.6.x LTS)"
        else
            fail "Unexpected kernel version: $KVER (expected 6.6.x)"
        fi
    else
        fail "Could not read kernel version"
    fi

    # Board model
    MODEL=$(ssh_cmd "cat /proc/device-tree/model 2>/dev/null | tr -d '\0'" || echo "")
    if [[ -n "$MODEL" ]]; then
        pass "Board model: $MODEL"
    else
        fail "Could not read /proc/device-tree/model"
    fi

    # dmesg errors
    ERR_COUNT=$(ssh_cmd "dmesg 2>/dev/null | grep -ci ' error' || echo 0" || echo "?")
    if [[ "$ERR_COUNT" == "0" ]]; then
        pass "dmesg: no error messages"
    elif [[ "$ERR_COUNT" == "?" ]]; then
        skip "Could not check dmesg errors"
    else
        fail "dmesg: $ERR_COUNT error message(s) found"
        echo "    Run: ssh ${SSH_USER}@${SSH_HOST} 'dmesg | grep -i error'"
    fi

    # IOMUX init
    IOMUX=$(ssh_cmd "dmesg 2>/dev/null | grep -i iomuxc | head -3" || echo "")
    if echo "$IOMUX" | grep -qi "error"; then
        fail "IOMUX initialization errors in dmesg"
    elif [[ -n "$IOMUX" ]]; then
        pass "IOMUX initialized (no errors)"
    else
        skip "No IOMUX messages in dmesg"
    fi

    # Filesystem writable
    FS_OK=$(ssh_cmd "touch /tmp/.validate_test && rm /tmp/.validate_test && echo ok" || echo "fail")
    if [[ "$FS_OK" == "ok" ]]; then
        pass "Filesystem writable (/tmp)"
    else
        fail "Filesystem not writable"
    fi

    # NPU driver (optional)
    NPU=$(ssh_cmd "lsmod 2>/dev/null | grep -c neutron || echo 0" || echo "?")
    if [[ "$NPU" != "0" ]] && [[ "$NPU" != "?" ]]; then
        pass "NPU driver loaded (neutron)"
    else
        skip "NPU driver not loaded (neutron) — expected if NPU not used"
    fi

    # VPU driver (optional)
    VPU=$(ssh_cmd "lsmod 2>/dev/null | grep -c vpu || echo 0" || echo "?")
    if [[ "$VPU" != "0" ]] && [[ "$VPU" != "?" ]]; then
        pass "VPU driver loaded"
    else
        skip "VPU driver not loaded — expected if VPU not used"
    fi

    # Camera devices (optional)
    CAM=$(ssh_cmd "ls /dev/video* 2>/dev/null | wc -l || echo 0" || echo "0")
    if [[ "$CAM" -gt 0 ]]; then
        pass "Camera devices found: $CAM /dev/video* device(s)"
    else
        skip "No /dev/video* devices — expected if no camera configured"
    fi
}

# ── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  ${BOLD}Validation Summary${NC}"
    echo "  Profile : $PROFILE_NAME  |  Board: $BOARD_NAME  |  MACHINE: $MACHINE"
    echo "  ─────────────────────────────────────────────────────────────────"
    echo -e "  ${GREEN}PASS: $PASS${NC}   ${RED}FAIL: $FAIL${NC}   ${YELLOW}SKIP: $WARN${NC}"
    echo ""
    if [[ $FAIL -eq 0 ]]; then
        echo -e "  ${GREEN}${BOLD}VALIDATION PASSED${NC}"
        echo "  Board is validated and ready for application development."
    else
        echo -e "  ${RED}${BOLD}VALIDATION FAILED: $FAIL check(s) failed${NC}"
        echo "  Review failures above and take corrective action."
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo ""
    log "=== imx95-validate-image ==="
    log "Profile : $PROFILE_NAME"
    log "Board   : $BOARD_NAME ($MACHINE)"
    log "Recipe  : $IMAGE_RECIPE"

    static_checks

    if [[ "$STATIC_ONLY" == "true" ]]; then
        section "Dynamic Checks"
        skip "Skipped (--static-only)"
    elif [[ -n "$SSH_HOST" ]]; then
        dynamic_checks_ssh
    else
        section "Dynamic Checks (SSH)"
        skip "No --ssh-host provided"
        echo ""
        echo "  To run dynamic checks, provide the board IP:"
        echo "    bash validate.sh --ssh-host <board-ip>"
        echo ""
        echo "  Manual checklist (run on board via serial console):"
        echo "    uname -r                          # expect 6.6.x"
        echo "    cat /proc/device-tree/model       # expect board model string"
        echo "    dmesg | grep -i error             # expect no critical errors"
        echo "    dmesg | grep iomuxc               # expect no IOMUX errors"
    fi

    print_summary
    [[ $FAIL -eq 0 ]] || exit 1
}

main "$@"
