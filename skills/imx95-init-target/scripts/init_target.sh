#!/bin/bash
# init_target.sh — Create a new imx95-bsp-skills target profile YAML
#
# Usage:
#   ./init_target.sh --workspace <path> --profile <name> --machine <machine>
#                    --image <recipe> --boot <emmc|sd> [--custom-carrier <name>]
#
# This script is called by the imx95-init-target skill to create the target
# profile YAML non-interactively. Claude Code passes all parameters.
#
# Copyright 2024 imx95-bsp-skills contributors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
WORKSPACE="${HOME}/imx95-workspace"
PROFILE_NAME=""
MACHINE=""
IMAGE_RECIPE="imx-image-full"
DISTRO="fsl-imx-xwayland"
BOOT_DEVICE="emmc"
CUSTOM_CARRIER_NAME=""
BSP_MANIFEST_URL="https://github.com/nxp-imx/imx-manifest"
BSP_MANIFEST_BRANCH="imx-linux-scarthgap"
BSP_MANIFEST_FILE="imx-6.6.52-2.2.0.xml"
DRY_RUN=false

# ── Colors ────────────────────────────────────────────────────────────────────
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
init_target.sh — Create a new imx95-bsp-skills target profile YAML

USAGE
    $0 --workspace <path> --profile <name> --machine <machine> [OPTIONS]

REQUIRED
    --workspace <path>    BSP workspace root directory
    --profile <name>      Profile name slug (e.g., frdm-imx95-base)
    --machine <machine>   Yocto MACHINE value (e.g., imx95-19x19-lpddr5-evk)

OPTIONS
    --image <recipe>      Image recipe [default: imx-image-full]
    --distro <distro>     Yocto DISTRO [default: fsl-imx-xwayland]
    --boot <device>       Boot device: emmc|sd [default: emmc]
    --custom-carrier <n>  Custom carrier name (sets custom_carrier: true)
    --manifest-branch <b> BSP manifest branch [default: imx-linux-scarthgap]
    --manifest-file <f>   BSP manifest file [default: imx-6.6.52-2.2.0.xml]
    --dry-run             Print YAML without writing files
    -h, --help            Show this help

EXAMPLES
    $0 --workspace ~/imx95-workspace --profile frdm-imx95-base \\
       --machine imx95-19x19-lpddr5-evk --image imx-image-full --boot emmc

    $0 --workspace ~/imx95-workspace --profile acme-carrier-v1 \\
       --machine imx95-19x19-lpddr5-evk --custom-carrier acme-carrier-v1
EOF
}

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace)       WORKSPACE="${2:?}"; shift 2 ;;
        --profile)         PROFILE_NAME="${2:?}"; shift 2 ;;
        --machine)         MACHINE="${2:?}"; shift 2 ;;
        --image)           IMAGE_RECIPE="${2:?}"; shift 2 ;;
        --distro)          DISTRO="${2:?}"; shift 2 ;;
        --boot)            BOOT_DEVICE="${2:?}"; shift 2 ;;
        --custom-carrier)  CUSTOM_CARRIER_NAME="${2:?}"; shift 2 ;;
        --manifest-branch) BSP_MANIFEST_BRANCH="${2:?}"; shift 2 ;;
        --manifest-file)   BSP_MANIFEST_FILE="${2:?}"; shift 2 ;;
        --dry-run)         DRY_RUN=true; shift ;;
        -h|--help)         usage; exit 0 ;;
        *) die "Unknown argument: $1" ;;
    esac
done

# ── Validation ────────────────────────────────────────────────────────────────
[[ -n "$PROFILE_NAME" ]] || die "--profile is required"
[[ -n "$MACHINE" ]]      || die "--machine is required"

# Validate profile name: lowercase, hyphens only
if ! echo "$PROFILE_NAME" | grep -qE '^[a-z0-9-]+$'; then
    die "Profile name '$PROFILE_NAME' is invalid. Use lowercase letters, digits, and hyphens only."
fi

# Validate machine name
VALID_MACHINES=("imx95-19x19-lpddr5-evk" "imx95frdm" "imx95-15x15-evk")
MACHINE_VALID=false
for m in "${VALID_MACHINES[@]}"; do
    [[ "$MACHINE" == "$m" ]] && MACHINE_VALID=true && break
done
if ! $MACHINE_VALID; then
    warn "Machine '$MACHINE' is not in the known list: ${VALID_MACHINES[*]}"
    warn "Proceeding anyway — verify this is a valid MACHINE for your BSP."
fi

# Validate boot device
case "$BOOT_DEVICE" in
    emmc|sd|flexspi) ;;
    *) die "Invalid boot device '$BOOT_DEVICE'. Use: emmc, sd, or flexspi" ;;
esac

# Expand workspace path
WORKSPACE="${WORKSPACE/#\~/$HOME}"

# ── Derive dependent fields ───────────────────────────────────────────────────

# UUU script based on boot device and machine
case "$BOOT_DEVICE" in
    emmc)
        if [[ "$MACHINE" == "imx95-15x15-evk" ]]; then
            UUU_SCRIPT="references/uuu-scripts/imx95-15x15-evk-emmc.uuu"
        else
            UUU_SCRIPT="references/uuu-scripts/frdm-imx95-emmc.uuu"
        fi
        ;;
    sd)
        UUU_SCRIPT="references/uuu-scripts/frdm-imx95-sd.uuu"
        ;;
    flexspi)
        UUU_SCRIPT="references/uuu-scripts/frdm-imx95-flexspi.uuu"
        ;;
esac

# Base DTS based on machine
case "$MACHINE" in
    imx95-19x19-lpddr5-evk) BASE_DTS="imx95-19x19-lpddr5-evk.dts" ;;
    imx95frdm)               BASE_DTS="imx95frdm.dts" ;;
    imx95-15x15-evk)         BASE_DTS="imx95-15x15-evk.dts" ;;
    *)                       BASE_DTS="${MACHINE}.dts" ;;
esac

# Deploy dir
DEPLOY_DIR="build/tmp/deploy/images/${MACHINE}"

# Custom carrier fields
if [[ -n "$CUSTOM_CARRIER_NAME" ]]; then
    CUSTOM_CARRIER_BOOL="true"
    CARRIER_NAME_YAML="  carrier_name: \"${CUSTOM_CARRIER_NAME}\""
    BASE_OVERLAY_YAML="  base_overlay: \"imx95-${CUSTOM_CARRIER_NAME}.dts\""
else
    CUSTOM_CARRIER_BOOL="false"
    CARRIER_NAME_YAML="  carrier_name: null"
    BASE_OVERLAY_YAML="  base_overlay: null"
fi

# Board name from machine
case "$MACHINE" in
    imx95-19x19-lpddr5-evk|imx95frdm) BOARD_NAME="FRDM-IMX95"; BOARD_VARIANT="19x19-lpddr5-evk" ;;
    imx95-15x15-evk)                   BOARD_NAME="i.MX95-15x15-EVK"; BOARD_VARIANT="15x15-evk" ;;
    *)                                 BOARD_NAME="Custom-${MACHINE}"; BOARD_VARIANT="custom" ;;
esac

# ── Generate YAML ─────────────────────────────────────────────────────────────
YAML_CONTENT="# imx95-bsp-skills target profile
# Generated by init_target.sh on $(date -u +%Y-%m-%dT%H:%M:%SZ)
# Schema version: 1.0

schema_version: \"1.0\"

profile_name: \"${PROFILE_NAME}\"
description: \"${BOARD_NAME}, ${BOOT_DEVICE} boot, ${IMAGE_RECIPE}\"

board:
  name: \"${BOARD_NAME}\"
  variant: \"${BOARD_VARIANT}\"
  soc: \"imx95\"
  boot_device: \"${BOOT_DEVICE}\"
  custom_carrier: ${CUSTOM_CARRIER_BOOL}

yocto:
  machine: \"${MACHINE}\"
  image_recipe: \"${IMAGE_RECIPE}\"
  distro: \"${DISTRO}\"
  bsp_manifest_url: \"${BSP_MANIFEST_URL}\"
  bsp_manifest_branch: \"${BSP_MANIFEST_BRANCH}\"
  bsp_manifest_file: \"${BSP_MANIFEST_FILE}\"

paths:
  workspace_root: \"${WORKSPACE}\"
  bsp_sources: \"sources\"
  build_dir: \"build\"
  custom_layer: \"sources/meta-imx95-custom\"
  dt_overlay_dir: \"sources/meta-imx95-custom/recipes-kernel/linux/files/overlays\"
  overlay_tracker: \"overlay-tracker\"
  deploy_dir: \"${DEPLOY_DIR}\"
  staging_dir: \"staging\"

flash:
  tool: \"uuu\"
  uuu_script: \"${UUU_SCRIPT}\"
  uuu_version_min: \"1.5.21\"
  recovery_mode_jumper: \"J301\"
  usb_vid_pid: \"1fc9:0146\"

device_tree:
  base_dts: \"${BASE_DTS}\"
  overlay_prefix: \"imx95-custom\"
  kernel_dt_path: \"sources/linux-imx/arch/arm64/boot/dts/freescale/\"

custom_carrier:
${CARRIER_NAME_YAML}
${BASE_OVERLAY_YAML}
  schematic_pdf: null

notes: |
  Created by init_target.sh.
  Profile: ${PROFILE_NAME}
  Machine: ${MACHINE}
"

# ── Output ────────────────────────────────────────────────────────────────────
if $DRY_RUN; then
    echo "=== DRY RUN — would write to ${WORKSPACE}/targets/${PROFILE_NAME}.yaml ==="
    echo ""
    echo "$YAML_CONTENT"
    exit 0
fi

# Create targets directory
mkdir -p "${WORKSPACE}/targets"

# Write profile YAML
PROFILE_PATH="${WORKSPACE}/targets/${PROFILE_NAME}.yaml"
echo "$YAML_CONTENT" > "$PROFILE_PATH"
success "Created ${PROFILE_PATH}"

# Set as active target
ACTIVE_PATH="${WORKSPACE}/targets/active_target.yaml"
cp "$PROFILE_PATH" "$ACTIVE_PATH"
success "Set as active target: ${ACTIVE_PATH}"

echo ""
info "Active target: ${PROFILE_NAME}"
info "  Board   : ${BOARD_NAME}"
info "  MACHINE : ${MACHINE}"
info "  Image   : ${IMAGE_RECIPE}"
info "  Boot    : ${BOOT_DEVICE}"
