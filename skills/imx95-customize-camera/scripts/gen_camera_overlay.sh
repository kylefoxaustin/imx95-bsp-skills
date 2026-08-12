#!/bin/bash
# gen_camera_overlay.sh — Generate MIPI-CSI2 camera DT overlay for i.MX 95
# Part of imx95-bsp-skills
#
# Usage:
#   gen_camera_overlay.sh --sensor <model> --csi-port <0|1> --i2c-bus <n>
#                         --i2c-addr <0xNN> --lanes <1|2|4> --mclk-hz <freq>
#                         [--pwdn-gpio "<ref> <pin> <flags>"]
#                         [--reset-gpio "<ref> <pin> <flags>"]
#                         [--workspace <path>] [--dry-run] [--output <file>]
#
# Options:
#   --sensor <model>       Sensor model (e.g. ov5640, imx219, ar0234)
#   --csi-port <0|1>       MIPI CSI port number (0 or 1)
#   --i2c-bus <n>          I2C bus number (1-8, maps to lpi2c<n>)
#   --i2c-addr <0xNN>      Sensor I2C address in hex
#   --lanes <1|2|4>        Number of MIPI data lanes
#   --mclk-hz <freq>       MCLK frequency in Hz (e.g. 24000000)
#   --pwdn-gpio "<r> <p> <f>"  Power-down GPIO: ref pin flags (e.g. "&gpio3 28 GPIO_ACTIVE_HIGH")
#   --reset-gpio "<r> <p> <f>" Reset GPIO: ref pin flags (e.g. "&gpio3 27 GPIO_ACTIVE_LOW")
#   --workspace <path>     BSP workspace root (default: auto-detect)
#   --dry-run              Print overlay without writing to disk
#   --output <file>        Output file path (default: auto from carrier name)
#   -h, --help             Show this help

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SENSOR=""
CSI_PORT=""
I2C_BUS=""
I2C_ADDR=""
LANES=""
MCLK_HZ="24000000"
PWDN_GPIO=""
RESET_GPIO=""
WORKSPACE=""
DRY_RUN=false
OUTPUT_FILE=""

usage() {
    grep '^#' "$0" | grep -v '#!/' | sed 's/^# \{0,1\}//'
    exit 0
}

log()  { echo -e "${CYAN}[gen-camera-overlay]${NC} $*"; }
ok()   { echo -e "${GREEN}[gen-camera-overlay] ✓${NC} $*"; }
warn() { echo -e "${YELLOW}[gen-camera-overlay] ⚠${NC} $*"; }
err()  { echo -e "${RED}[gen-camera-overlay] ✗${NC} $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sensor)      SENSOR="$2";      shift 2 ;;
        --csi-port)    CSI_PORT="$2";    shift 2 ;;
        --i2c-bus)     I2C_BUS="$2";     shift 2 ;;
        --i2c-addr)    I2C_ADDR="$2";    shift 2 ;;
        --lanes)       LANES="$2";       shift 2 ;;
        --mclk-hz)     MCLK_HZ="$2";    shift 2 ;;
        --pwdn-gpio)   PWDN_GPIO="$2";   shift 2 ;;
        --reset-gpio)  RESET_GPIO="$2";  shift 2 ;;
        --workspace)   WORKSPACE="$2";   shift 2 ;;
        --dry-run)     DRY_RUN=true;     shift   ;;
        --output)      OUTPUT_FILE="$2"; shift 2 ;;
        -h|--help)     usage ;;
        *) err "Unknown argument: $1" ;;
    esac
done

# Validate required args
[[ -n "$SENSOR"   ]] || err "--sensor is required"
[[ -n "$CSI_PORT" ]] || err "--csi-port is required (0 or 1)"
[[ -n "$I2C_BUS"  ]] || err "--i2c-bus is required"
[[ -n "$I2C_ADDR" ]] || err "--i2c-addr is required"
[[ -n "$LANES"    ]] || err "--lanes is required (1, 2, or 4)"

# Normalize sensor name to lowercase
SENSOR="$(echo "$SENSOR" | tr '[:upper:]' '[:lower:]')"

# Build lane list string: "1" → "<1>", "2" → "<1 2>", "4" → "<1 2 3 4>"
case "$LANES" in
    1) LANE_LIST="<1>" ;;
    2) LANE_LIST="<1 2>" ;;
    4) LANE_LIST="<1 2 3 4>" ;;
    *) err "--lanes must be 1, 2, or 4" ;;
esac

# Locate workspace
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

DT_OVERLAY_REL="$(read_yaml dt_overlay_dir sources/meta-imx95-custom/recipes-kernel/linux/files/overlays)"
CARRIER_NAME="$(read_yaml carrier_name custom)"
PROFILE_NAME="$(read_yaml profile_name unknown)"
OVERLAY_DIR="$WORKSPACE/$DT_OVERLAY_REL"

# Determine output file
if [[ -z "$OUTPUT_FILE" ]]; then
    OUTPUT_FILE="$OVERLAY_DIR/imx95-${CARRIER_NAME}-camera.dts"
fi

# Build GPIO strings
PWDN_STR=""
if [[ -n "$PWDN_GPIO" ]]; then
    PWDN_STR="        powerdown-gpios = <${PWDN_GPIO}>;"
fi

RESET_STR=""
if [[ -n "$RESET_GPIO" ]]; then
    RESET_STR="        reset-gpios = <${RESET_GPIO}>;"
fi

# Determine sensor compatible string
case "$SENSOR" in
    ov5640)  COMPAT="ovti,ov5640" ;;
    ov13858) COMPAT="ovti,ov13858" ;;
    imx219)  COMPAT="sony,imx219" ;;
    imx477)  COMPAT="sony,imx477" ;;
    ar0234)  COMPAT="onnn,ar0234" ;;
    *)       COMPAT="<vendor>,${SENSOR}" ; warn "Unknown sensor '$SENSOR' — set compatible string manually" ;;
esac

YEAR="$(date +%Y)"

# Generate overlay content
generate_overlay() {
cat << DTS
// SPDX-License-Identifier: GPL-2.0+
/*
 * ${SENSOR^^} MIPI-CSI2 camera overlay for NXP i.MX 95
 * Generated by imx95-bsp-skills / imx95-customize-camera
 *
 * Profile  : ${PROFILE_NAME}
 * Sensor   : ${SENSOR^^} (${COMPAT})
 * CSI port : mipi_csi${CSI_PORT}
 * I2C bus  : lpi2c${I2C_BUS} @ ${I2C_ADDR}
 * Lanes    : ${LANES}
 * MCLK     : ${MCLK_HZ} Hz
 *
 * IMPORTANT: Verify GPIO pad assignments against your schematic before building.
 * Use imx95-customize-pinmux to configure PWDN and RESET_N pads as GPIO.
 */

/dts-v1/;
/plugin/;

#include <dt-bindings/gpio/gpio.h>
#include <dt-bindings/clock/imx95-clock.h>

/ {
    /* Fixed MCLK clock for ${SENSOR^^} sensor */
    clk_cam${CSI_PORT}_mclk: clock-cam${CSI_PORT}-mclk {
        compatible = "fixed-clock";
        #clock-cells = <0>;
        clock-frequency = <${MCLK_HZ}>;
    };
};

/* ${SENSOR^^} sensor node on lpi2c${I2C_BUS} */
&lpi2c${I2C_BUS} {
    #address-cells = <1>;
    #size-cells = <0>;
    status = "okay";

    ${SENSOR}_${CSI_PORT}: camera@${I2C_ADDR#0x} {
        compatible = "${COMPAT}";
        reg = <${I2C_ADDR}>;

        clocks = <&clk_cam${CSI_PORT}_mclk>;
        clock-names = "xclk";

$([ -n "$PWDN_STR"  ] && echo "$PWDN_STR")
$([ -n "$RESET_STR" ] && echo "$RESET_STR")

        status = "okay";

        port {
            ${SENSOR}_${CSI_PORT}_ep: endpoint {
                remote-endpoint = <&mipi_csi${CSI_PORT}_ep>;
                data-lanes = ${LANE_LIST};
                clock-lanes = <0>;
            };
        };
    };
};

/* MIPI CSI-2 RX controller ${CSI_PORT} */
&mipi_csi${CSI_PORT} {
    status = "okay";

    port@0 {
        reg = <0>;
        mipi_csi${CSI_PORT}_ep: endpoint {
            remote-endpoint = <&${SENSOR}_${CSI_PORT}_ep>;
            data-lanes = ${LANE_LIST};
            clock-lanes = <0>;
        };
    };
};

/* Image Sensing Interface ${CSI_PORT} */
&isi_${CSI_PORT} {
    status = "okay";
};
DTS
}

OVERLAY_CONTENT="$(generate_overlay)"

log "=== gen-camera-overlay ==="
log "Sensor   : $SENSOR ($COMPAT)"
log "CSI port : mipi_csi${CSI_PORT}"
log "I2C      : lpi2c${I2C_BUS} @ ${I2C_ADDR}"
log "Lanes    : $LANES"
log "MCLK     : ${MCLK_HZ} Hz"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    echo "=== DRY RUN: $(basename "$OUTPUT_FILE") ==="
    echo "$OVERLAY_CONTENT"
    echo ""
    log "Dry run complete — no files written."
    exit 0
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"
echo "$OVERLAY_CONTENT" > "$OUTPUT_FILE"
ok "Camera overlay written: $OUTPUT_FILE"

echo ""
echo "Next steps:"
echo "  1. Review the generated overlay (shown above)"
echo "  2. Configure PWDN and RESET_N pads: run imx95-customize-pinmux"
echo "  3. Add SRC_URI to linux-imx_%.bbappend"
echo "  4. Commit to overlay-tracker (commit-gate will be shown)"
echo "  5. Build: run imx95-build-source"
