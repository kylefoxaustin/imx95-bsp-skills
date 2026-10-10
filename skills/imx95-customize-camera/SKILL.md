---
name: imx95-customize-camera
version: "1.0"
platform: imx95
phase: customize
invoke_when:
  - "add camera"
  - "MIPI CSI"
  - "configure sensor"
  - "camera pipeline"
  - "OV5640"
  - "IMX219"
  - "CSI2 receiver"
  - "ISP pipeline"
requires_host_tools:
  - dtc
  - git
safe: true
destructive: false
commit_gate: true
---

# imx95-customize-camera

## Purpose

Configure a MIPI-CSI2 camera pipeline in the device tree overlay. Handles the CSI2
receiver (`mipi_csi`), ISP pipeline (`isi`), sensor I2C node, MCLK clock, and
power/reset GPIOs. Includes a working OV5640 example.

## When to Invoke

- Adding a MIPI-CSI2 camera sensor to a custom carrier or FRDM expansion header
- User says "add camera", "MIPI CSI", "configure sensor", "OV5640", "IMX219"

## Pre-conditions

1. `targets/active_target.yaml` exists.
2. Carrier overlay file exists (run `imx95-derive-carrier` first).
3. `overlay-tracker/` is initialized and clean.
4. User has the camera sensor datasheet or knows: sensor model, I2C address, CSI port,
   lane count, MCLK frequency, power/reset GPIO pads.

## i.MX 95 Camera Pipeline

```
Sensor (I2C slave)
    │  MIPI CSI-2 D-PHY (1/2/4 lanes)
    ▼
mipi_csi0 or mipi_csi1   (MIPI CSI-2 RX controller)
    │
    ▼
isi0 or isi1             (Image Sensing Interface — DMA to memory)
    │
    ▼
V4L2 video device        (/dev/video0, /dev/video1, ...)
```

## Questions to Ask User

Before generating any DT:

1. **Sensor model** (e.g., OV5640, IMX219, AR0234, OV13858)
2. **I2C bus number** (e.g., 1 = `&lpi2c1`, 2 = `&lpi2c2`, etc.)
3. **I2C address** (e.g., 0x3c for OV5640)
4. **CSI port** (CSI0 = `mipi_csi0`, CSI1 = `mipi_csi1`)
5. **Number of MIPI data lanes** (1, 2, or 4)
6. **MCLK frequency** (typically 24000000 Hz)
7. **PWDN GPIO** — pad name and active-high/low
8. **RESET_N GPIO** — pad name and active-high/low
9. **MCLK frequency** — the sensor's external clock, in Hz (commonly 24000000).
   ⚠️ **NOT a CCM clock constant.** An earlier version of this line said *"which CCM clock
   output (typically `IMX95_CLK_CCM_CKO1`)"* — part of the **fabricated CCM model** that was
   deleted from `imx95-customize-clocks` (ground-truth §6: clocks on this SoC are
   **SCMI-mediated**, 24 of 26 `assigned-clocks` nodes reference `scmi_clk`, and v1's
   `IMX95_CLK_*` constants do not describe this part).
   **The generator already does the right thing** — `gen_camera_overlay.sh` emits a
   `fixed-clock` node with `clock-frequency = <MCLK_HZ>` and points the sensor's
   `clocks`/`clock-names = "xclk"` at it, which sidesteps the SCMI question entirely. Only this
   documentation was wrong, and a reader following it would have hand-edited the overlay to
   reference a constant that does not exist.

**NEVER assume GPIO numbers or I2C addresses. Always ask for the schematic.**

## Procedure

### Step 1 — Read active target

Extract `paths.dt_overlay_dir` from `targets/active_target.yaml`.

### Step 2 — Generate camera overlay

Run:
```bash
bash skills/imx95-customize-camera/scripts/gen_camera_overlay.sh \
    --sensor <model> \
    --csi-port <0|1> \
    --i2c-bus <n> \
    --i2c-addr <0xNN> \
    --lanes <1|2|4> \
    --mclk-hz <freq> \
    --pwdn-gpio "<gpio-ref> <pin> <flags>" \
    --reset-gpio "<gpio-ref> <pin> <flags>"
```

### STOP — Show generated DT snippet to user

Display the complete generated overlay. Wait for explicit approval before writing.

### Step 3 — Apply to overlay file

Write the camera overlay to `imx95-<carrier-name>-camera.dts` and add `SRC_URI` to bbappend.

### Step 4 — Add pinmux for PWDN and RESET GPIOs

Invoke `imx95-customize-pinmux` to configure the PWDN and RESET_N pad functions as GPIO.

### Step 5 — Validate with dtc

```bash
dtc -@ -I dts -O dtb -o /dev/null <camera-overlay-file>
```

### Step 6 — Commit to overlay-tracker (commit-gate)

Show `git diff --staged`, wait for approval, then commit.

Commit message:
```
customize(camera): add <sensor-model> on CSI<n> / I2C<n>

Board: <profile_name>
Skill: imx95-customize-camera
Files: imx95-<name>-camera.dts

Added <sensor-model> MIPI-CSI2 camera:
  CSI port : mipi_csi<n>
  I2C bus  : lpi2c<n> @ <addr>
  Lanes    : <n>
  MCLK     : <freq> Hz

Tested: pending
```

## OV5640 Example (CSI0, I2C1, 2 lanes, 24 MHz MCLK)

```dts
// SPDX-License-Identifier: GPL-2.0+
/*
 * OV5640 MIPI-CSI2 camera overlay for i.MX 95
 * CSI port: mipi_csi0, I2C: lpi2c1 @ 0x3c, 2 lanes
 */

/dts-v1/;
/plugin/;

#include <dt-bindings/gpio/gpio.h>
#include <dt-bindings/clock/imx95-clock.h>

/ {
    /* MCLK clock output for camera sensor */
    clk_cam0_mclk: clock-cam0-mclk {
        compatible = "fixed-clock";
        #clock-cells = <0>;
        clock-frequency = <24000000>;
    };
};

/* Camera sensor node on I2C1 */
&lpi2c1 {
    #address-cells = <1>;
    #size-cells = <0>;

    ov5640_0: camera@3c {
        compatible = "ovti,ov5640";
        reg = <0x3c>;

        clocks = <&clk_cam0_mclk>;
        clock-names = "xclk";

        /* PWDN: active-high (GPIO3_IO28) */
        powerdown-gpios = <&gpio3 28 GPIO_ACTIVE_HIGH>;
        /* RESET_N: active-low (GPIO3_IO27) */
        reset-gpios = <&gpio3 27 GPIO_ACTIVE_LOW>;

        status = "okay";

        port {
            ov5640_0_ep: endpoint {
                remote-endpoint = <&mipi_csi0_ep>;
                data-lanes = <1 2>;
                clock-lanes = <0>;
            };
        };
    };
};

/* MIPI CSI-2 RX controller */
&mipi_csi0 {
    status = "okay";

    port@0 {
        reg = <0>;
        mipi_csi0_ep: endpoint {
            remote-endpoint = <&ov5640_0_ep>;
            data-lanes = <1 2>;
            clock-lanes = <0>;
        };
    };
};

/* Image Sensing Interface */
&isi_0 {
    status = "okay";
};
```

## Files Touched

- `sources/meta-imx95-custom/recipes-kernel/linux/files/overlays/imx95-<name>-camera.dts`
- `sources/meta-imx95-custom/recipes-kernel/linux/linux-imx_%.bbappend`
- `overlay-tracker/` (committed)

## Safety Rules Applied

- **R2** — Only meta-imx95-custom overlays modified
- **R3** — DT changes committed before building
- **R4** — Commit-gate on every commit
- **R5** — Never assume GPIO/I2C details; always ask for schematic

## References

- `references/bsp-customization-iomux-dt.md` — GPIO pad configuration
- `references/bsp-customization-io-devices.md` — I2C device DT patterns
- `references/bsp-customization-kernel-dtb.md` — overlay structure
