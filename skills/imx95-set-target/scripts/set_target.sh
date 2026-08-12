#!/bin/bash
# set_target.sh — Switch the active imx95-bsp-skills target profile
#
# Usage:
#   ./set_target.sh --workspace <path> --profile <name>
#   ./set_target.sh --workspace <path> --list
#
# Copyright 2024 imx95-bsp-skills contributors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
die()     { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }

usage() {
    cat <<EOF
set_target.sh — Switch the active imx95-bsp-skills target profile

USAGE
    $0 --workspace <path> --profile <name>
    $0 --workspace <path> --list

OPTIONS
    --workspace <path>   BSP workspace root directory
    --profile <name>     Profile name to activate
    --list               List available profiles and exit
    -h, --help           Show this help

EXAMPLES
    $0 --workspace ~/imx95-workspace --list
    $0 --workspace ~/imx95-workspace --profile acme-carrier-v1
EOF
}

WORKSPACE=""
PROFILE_NAME=""
LIST_ONLY=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace) WORKSPACE="${2:?}"; shift 2 ;;
        --profile)   PROFILE_NAME="${2:?}"; shift 2 ;;
        --list)      LIST_ONLY=true; shift ;;
        -h|--help)   usage; exit 0 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

[[ -n "$WORKSPACE" ]] || die "--workspace is required"
WORKSPACE="${WORKSPACE/#\~/$HOME}"
TARGETS_DIR="${WORKSPACE}/targets"

[[ -d "$TARGETS_DIR" ]] || die "targets/ directory not found at ${TARGETS_DIR}"

# ── List available profiles ───────────────────────────────────────────────────
list_profiles() {
    local active_name=""
    if [[ -f "${TARGETS_DIR}/active_target.yaml" ]]; then
        active_name=$(grep '^profile_name:' "${TARGETS_DIR}/active_target.yaml" \
            | sed 's/profile_name: *"\?\([^"]*\)"\?/\1/' | tr -d ' ')
    fi

    echo ""
    echo "Available target profiles in ${TARGETS_DIR}:"
    echo ""

    local i=1
    local found=false
    for yaml_file in "${TARGETS_DIR}"/*.yaml; do
        [[ -f "$yaml_file" ]] || continue
        local fname
        fname=$(basename "$yaml_file" .yaml)
        [[ "$fname" == "active_target" ]] && continue

        # Parse key fields
        local pname machine image boot
        pname=$(grep '^profile_name:' "$yaml_file" | sed 's/profile_name: *"\?\([^"]*\)"\?/\1/' | tr -d ' ')
        machine=$(grep '^ *machine:' "$yaml_file" | head -1 | sed 's/.*machine: *"\?\([^"]*\)"\?/\1/' | tr -d ' ')
        image=$(grep '^ *image_recipe:' "$yaml_file" | sed 's/.*image_recipe: *"\?\([^"]*\)"\?/\1/' | tr -d ' ')
        boot=$(grep '^ *boot_device:' "$yaml_file" | sed 's/.*boot_device: *"\?\([^"]*\)"\?/\1/' | tr -d ' ')

        local active_marker=""
        [[ "$pname" == "$active_name" ]] && active_marker=" [ACTIVE]"

        printf "  %2d. %-30s (%s, %s, %s)%s\n" \
            "$i" "$pname" "$machine" "$boot" "$image" "$active_marker"
        ((i++))
        found=true
    done

    if ! $found; then
        echo "  (no profiles found — run imx95-init-target to create one)"
    fi
    echo ""
}

list_profiles

$LIST_ONLY && exit 0

# ── Switch to specified profile ───────────────────────────────────────────────
[[ -n "$PROFILE_NAME" ]] || die "--profile is required (or use --list)"

PROFILE_FILE="${TARGETS_DIR}/${PROFILE_NAME}.yaml"
[[ -f "$PROFILE_FILE" ]] || die "Profile not found: ${PROFILE_FILE}"

ACTIVE_FILE="${TARGETS_DIR}/active_target.yaml"

# Show current active
if [[ -f "$ACTIVE_FILE" ]]; then
    CURRENT=$(grep '^profile_name:' "$ACTIVE_FILE" \
        | sed 's/profile_name: *"\?\([^"]*\)"\?/\1/' | tr -d ' ')
    if [[ "$CURRENT" == "$PROFILE_NAME" ]]; then
        info "Profile '${PROFILE_NAME}' is already the active target."
        exit 0
    fi
    info "Switching from '${CURRENT}' to '${PROFILE_NAME}'"
fi

# Copy profile to active_target.yaml
cp "$PROFILE_FILE" "$ACTIVE_FILE"
success "Active target set to: ${PROFILE_NAME}"

# Parse new target fields for display
NEW_MACHINE=$(grep '^ *machine:' "$ACTIVE_FILE" | head -1 \
    | sed 's/.*machine: *"\?\([^"]*\)"\?/\1/' | tr -d ' ')
NEW_IMAGE=$(grep '^ *image_recipe:' "$ACTIVE_FILE" \
    | sed 's/.*image_recipe: *"\?\([^"]*\)"\?/\1/' | tr -d ' ')
NEW_BOOT=$(grep '^ *boot_device:' "$ACTIVE_FILE" \
    | sed 's/.*boot_device: *"\?\([^"]*\)"\?/\1/' | tr -d ' ')

echo ""
info "  MACHINE : ${NEW_MACHINE}"
info "  Image   : ${NEW_IMAGE}"
info "  Boot    : ${NEW_BOOT}"
echo ""

# Check for MACHINE mismatch in local.conf
LOCAL_CONF="${WORKSPACE}/build/conf/local.conf"
if [[ -f "$LOCAL_CONF" ]]; then
    CONF_MACHINE=$(grep '^MACHINE' "$LOCAL_CONF" \
        | sed 's/MACHINE *= *"\?\([^"]*\)"\?/\1/' | tr -d ' ' || echo "")
    if [[ -n "$CONF_MACHINE" && "$CONF_MACHINE" != "$NEW_MACHINE" ]]; then
        warn "MACHINE mismatch:"
        warn "  local.conf MACHINE : ${CONF_MACHINE}"
        warn "  New target MACHINE : ${NEW_MACHINE}"
        warn "  Run imx95-init-source to update local.conf before building."
    fi
fi
