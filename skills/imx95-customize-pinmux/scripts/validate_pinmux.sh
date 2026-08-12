#!/bin/bash
# validate_pinmux.sh — Validate i.MX 95 DT overlay pinmux configuration
# Part of imx95-bsp-skills
#
# Usage:
#   validate_pinmux.sh [--workspace <path>] [--overlay <file>] [--pre-check]
#
# Options:
#   --workspace <path>   BSP workspace root (default: auto-detect)
#   --overlay <file>     Specific overlay file to validate (default: all overlays)
#   --pre-check          Run pre-change check only (no compile)
#   -h, --help           Show this help
#
# Checks performed:
#   1. dtc compiles each overlay file without errors or warnings
#   2. No duplicate MX95_PAD_xxx assignments across all overlay files
#   3. Each pinctrl group is referenced by at least one peripheral node

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

WORKSPACE=""
OVERLAY_FILE=""
PRE_CHECK=false
ERRORS=0
WARNINGS=0

usage() {
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,1\}//'
    exit 0
}

log()  { echo -e "${CYAN}[validate-pinmux]${NC} $*"; }
ok()   { echo -e "${GREEN}[validate-pinmux] ✓${NC} $*"; }
warn() { echo -e "${YELLOW}[validate-pinmux] ⚠${NC} $*"; WARNINGS=$((WARNINGS+1)); }
fail() { echo -e "${RED}[validate-pinmux] ✗${NC} $*"; ERRORS=$((ERRORS+1)); }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace)  WORKSPACE="$2";    shift 2 ;;
        --overlay)    OVERLAY_FILE="$2"; shift 2 ;;
        --pre-check)  PRE_CHECK=true;    shift   ;;
        -h|--help)    usage ;;
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

DT_OVERLAY_REL="$(read_yaml dt_overlay_dir sources/meta-imx95-custom/recipes-kernel/linux/files/overlays)"
OVERLAY_DIR="$WORKSPACE/$DT_OVERLAY_REL"

log "=== validate-pinmux ==="
log "Overlay dir: $OVERLAY_DIR"
echo ""

# ── Check dtc is available ────────────────────────────────────────────────────
check_dtc() {
    if ! command -v dtc &>/dev/null; then
        fail "dtc not found — install device-tree-compiler"
        echo ""
        echo "  sudo apt-get install device-tree-compiler"
        exit 1
    fi
    ok "dtc found: $(dtc --version 2>&1 | head -1)"
}

# ── Pre-check: overlay directory exists ──────────────────────────────────────
pre_check() {
    if [[ ! -d "$OVERLAY_DIR" ]]; then
        warn "Overlay directory does not exist yet: $OVERLAY_DIR"
        warn "Run imx95-derive-carrier first to create the overlay structure."
        return
    fi

    local count
    count=$(find "$OVERLAY_DIR" -name "*.dts" 2>/dev/null | wc -l)
    ok "Overlay directory exists with $count .dts file(s)"

    # List existing files
    if [[ $count -gt 0 ]]; then
        find "$OVERLAY_DIR" -name "*.dts" | while read -r f; do
            log "  Found: $(basename "$f")"
        done
    fi
}

# ── Compile check: dtc each overlay ──────────────────────────────────────────
compile_check() {
    local files=()

    if [[ -n "$OVERLAY_FILE" ]]; then
        files=("$OVERLAY_FILE")
    else
        while IFS= read -r -d '' f; do
            files+=("$f")
        done < <(find "$OVERLAY_DIR" -name "*.dts" -print0 2>/dev/null)
    fi

    if [[ ${#files[@]} -eq 0 ]]; then
        warn "No .dts files found in $OVERLAY_DIR"
        return
    fi

    log "Compiling ${#files[@]} overlay file(s) with dtc..."
    for f in "${files[@]}"; do
        local fname
        fname="$(basename "$f")"
        local tmpout
        tmpout="$(mktemp /tmp/dtc-out-XXXXXX.dtbo)"

        # dtc compile: -@ enables symbols for overlays, -I dts -O dtb
        local dtc_out
        if dtc_out=$(dtc -@ -I dts -O dtb -o "$tmpout" "$f" 2>&1); then
            ok "$fname — compiled OK"
            # Check for warnings in output
            if echo "$dtc_out" | grep -qi "warning"; then
                warn "$fname — dtc warnings:"
                echo "$dtc_out" | grep -i "warning" | sed 's/^/    /'
            fi
        else
            fail "$fname — dtc FAILED:"
            echo "$dtc_out" | sed 's/^/    /'
        fi
        rm -f "$tmpout"
    done
}

# ── Duplicate pad check ───────────────────────────────────────────────────────
duplicate_pad_check() {
    log "Checking for duplicate MX95_PAD_xxx assignments..."

    local all_pads=()
    local dts_files=()

    while IFS= read -r -d '' f; do
        dts_files+=("$f")
    done < <(find "$OVERLAY_DIR" -name "*.dts" -print0 2>/dev/null)

    if [[ ${#dts_files[@]} -eq 0 ]]; then
        warn "No .dts files to check for duplicates"
        return
    fi

    # Extract all MX95_PAD_xxx tokens
    local pad_list
    pad_list=$(grep -h -oP 'MX95_PAD_[A-Z0-9_]+__[A-Z0-9_]+' "${dts_files[@]}" 2>/dev/null | sort)

    if [[ -z "$pad_list" ]]; then
        ok "No MX95_PAD assignments found yet"
        return
    fi

    # Find duplicates
    local duplicates
    duplicates=$(echo "$pad_list" | sort | uniq -d)

    if [[ -n "$duplicates" ]]; then
        fail "Duplicate pad assignments detected:"
        echo "$duplicates" | while read -r pad; do
            echo "    $pad"
            grep -rn "$pad" "${dts_files[@]}" 2>/dev/null | sed 's/^/      /'
        done
    else
        local total
        total=$(echo "$pad_list" | wc -l)
        ok "No duplicate pad assignments ($total unique pads)"
    fi
}

# ── Orphan pinctrl check ──────────────────────────────────────────────────────
orphan_pinctrl_check() {
    log "Checking for unreferenced pinctrl groups..."

    local dts_files=()
    while IFS= read -r -d '' f; do
        dts_files+=("$f")
    done < <(find "$OVERLAY_DIR" -name "*.dts" -print0 2>/dev/null)

    [[ ${#dts_files[@]} -eq 0 ]] && return

    # Find all defined pinctrl groups
    local defined
    defined=$(grep -h -oP 'pinctrl_\w+(?=\s*:)' "${dts_files[@]}" 2>/dev/null | sort -u)

    [[ -z "$defined" ]] && { ok "No pinctrl groups defined yet"; return; }

    local orphans=0
    while read -r group; do
        # Check if referenced via <&group>
        if ! grep -qh "<&${group}>" "${dts_files[@]}" 2>/dev/null; then
            warn "Pinctrl group '$group' defined but not referenced by any peripheral"
            orphans=$((orphans+1))
        fi
    done <<< "$defined"

    [[ $orphans -eq 0 ]] && ok "All pinctrl groups are referenced"
}

# ── Summary ───────────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [[ $ERRORS -gt 0 ]]; then
        echo -e "  ${RED}VALIDATION FAILED: $ERRORS error(s), $WARNINGS warning(s)${NC}"
        echo "  Fix errors before committing or building."
    elif [[ $WARNINGS -gt 0 ]]; then
        echo -e "  ${YELLOW}VALIDATION PASSED WITH WARNINGS: $WARNINGS warning(s)${NC}"
        echo "  Review warnings before building."
    else
        echo -e "  ${GREEN}VALIDATION PASSED: no errors, no warnings${NC}"
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    check_dtc
    pre_check

    if [[ "$PRE_CHECK" == "true" ]]; then
        print_summary
        exit 0
    fi

    compile_check
    duplicate_pad_check
    orphan_pinctrl_check
    print_summary

    [[ $ERRORS -eq 0 ]] || exit 1
}

main "$@"
