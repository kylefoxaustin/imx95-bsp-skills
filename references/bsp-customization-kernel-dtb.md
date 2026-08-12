# Kernel DT Customization Reference — i.MX 95

> **Reference document** for `imx95-customize-pinmux`, `imx95-derive-carrier`, and
> `imx95-build-source`. Covers DT overlay structure, Yocto integration, and dtc/fdtdump usage.

---

## Overview

The i.MX 95 BSP supports two approaches to kernel device tree customization:

| Approach | Recommended? | Description |
|---|---|---|
| **DT Overlay** (`.dtbo`) | ✅ YES | Compiled overlay applied by U-Boot at boot |
| **bbappend + SRC_URI patch** | ⚠️ Sometimes | In-tree DTS patch via Yocto recipe |
| **Direct in-tree edit** | ❌ NO | Lost on `repo sync` |

This skill bundle uses **DT overlays** for all carrier board customizations. Overlays are
the cleanest approach: they are version-controlled in `overlay-tracker`, compiled separately
from the base DTB, and applied by U-Boot at boot time.

---

## DT Overlay Structure

### What is a DT Overlay?

A DT overlay is a partial device tree that modifies the base DTB at boot time. It uses the
`/plugin/` directive and `&node_label {}` syntax to override or extend nodes in the base DTB.

### Minimal Overlay Template

```dts
// SPDX-License-Identifier: GPL-2.0+
/*
 * Copyright (C) 2024 <Your Company>
 * Device tree overlay for i.MX 95 custom carrier board
 * Base: imx95-19x19-lpddr5-evk.dts
 */

/dts-v1/;
/plugin/;

/* Include pad macro definitions */
#include <dt-bindings/pinctrl/pinfunc-imx95.h>
/* Include GPIO definitions */
#include <dt-bindings/gpio/gpio.h>
/* Include clock definitions */
#include <dt-bindings/clock/imx95-clock.h>

/* Override the board model string */
/ {
    model = "NXP i.MX95 Custom Carrier Board";
    compatible = "mycompany,imx95-custom", "nxp,imx95";
};

/* Add pinmux groups */
&iomuxc {
    pinctrl_uart4: uart4grp {
        fsl,pins = <
            MX95_PAD_GPIO_IO04__LPUART4_TX    0x31e
            MX95_PAD_GPIO_IO05__LPUART4_RX    0x31e
        >;
    };
};

/* Enable UART4 */
&lpuart4 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_uart4>;
    status = "okay";
};
```

### Key Overlay Directives

| Directive | Meaning |
|---|---|
| `/dts-v1/;` | DTS format version 1 (required) |
| `/plugin/;` | Marks this as an overlay (required for `.dtbo`) |
| `&node_label { }` | Override/extend an existing node by its label |
| `/ { }` | Override root node properties |
| `status = "okay"` | Enable a disabled node |
| `status = "disabled"` | Disable an enabled node |

---

## How to Add a DT Overlay to the Yocto Build

### Step 1: Create the Overlay File

Place the overlay `.dts` file in `dt_overlay_dir`:
```
sources/meta-imx95-custom/recipes-kernel/linux/files/overlays/imx95-custom.dts
```

### Step 2: Register in `linux-imx_%.bbappend`

```bitbake
# sources/meta-imx95-custom/recipes-kernel/linux/linux-imx_%.bbappend

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# Add the overlay source file to the recipe
SRC_URI += " \
    file://overlays/imx95-custom.dts \
"

# Copy the overlay into the kernel source tree before compilation
do_configure:append() {
    install -d ${S}/arch/arm64/boot/dts/freescale/
    install -m 644 ${WORKDIR}/overlays/imx95-custom.dts \
        ${S}/arch/arm64/boot/dts/freescale/
}

# Add the overlay DTB to the list of DTBs to build
# Note: .dtbo extension for overlays, .dtb for full DTBs
KERNEL_DEVICETREE:append = " freescale/imx95-custom.dtbo"
```

### Step 3: Configure U-Boot to Load the Overlay

U-Boot must be told to apply the overlay at boot. Set the `fdtoverlays` environment variable:

```bash
# In U-Boot prompt (one-time setup):
setenv fdtoverlays imx95-custom.dtbo
saveenv

# Or via fw_setenv from Linux:
fw_setenv fdtoverlays imx95-custom.dtbo
```

For production, set this in the U-Boot default environment via bbappend:

```bitbake
# sources/meta-imx95-custom/recipes-bsp/u-boot/u-boot-imx_%.bbappend

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI += "file://0001-set-fdtoverlays.patch"
```

### Step 4: Build the Overlay

```bash
# Build only the kernel (includes DTB compilation)
bitbake linux-imx

# Or force recompile of just the DTB:
bitbake linux-imx -c compile -f
bitbake linux-imx -c deploy -f

# The compiled overlay will be at:
# build/tmp/deploy/images/<machine>/imx95-custom.dtbo
```

---

## Multiple Overlays

For complex carrier boards, split customizations into multiple overlay files:

```bitbake
# linux-imx_%.bbappend — multiple overlays

SRC_URI += " \
    file://overlays/imx95-custom.dts \
    file://overlays/imx95-custom-pinmux.dts \
    file://overlays/imx95-custom-camera.dts \
"

do_configure:append() {
    install -d ${S}/arch/arm64/boot/dts/freescale/
    for f in imx95-custom.dts imx95-custom-pinmux.dts imx95-custom-camera.dts; do
        install -m 644 ${WORKDIR}/overlays/${f} \
            ${S}/arch/arm64/boot/dts/freescale/
    done
}

KERNEL_DEVICETREE:append = " \
    freescale/imx95-custom.dtbo \
    freescale/imx95-custom-pinmux.dtbo \
    freescale/imx95-custom-camera.dtbo \
"
```

In U-Boot, load all overlays:
```bash
setenv fdtoverlays "imx95-custom.dtbo imx95-custom-pinmux.dtbo imx95-custom-camera.dtbo"
saveenv
```

---

## Testing with `dtc` and `fdtdump`

### Compile a DTS to DTB (syntax check)

```bash
# Basic compile — checks syntax
dtc -I dts -O dtb -o /tmp/test.dtb path/to/overlay.dts

# With include path for dt-bindings headers
dtc -I dts -O dtb \
    -i sources/linux-imx/include \
    -i sources/linux-imx/arch/arm64/boot/dts/freescale \
    -o /tmp/test.dtb \
    path/to/overlay.dts

# Check for warnings (treat as errors in CI)
dtc -I dts -O dtb -W no-unit_address_vs_reg \
    -o /tmp/test.dtb path/to/overlay.dts 2>&1
```

### Decompile a DTB back to DTS (inspect compiled output)

```bash
# Decompile a DTB
dtc -I dtb -O dts -o /tmp/test.dts build/tmp/deploy/images/imx95-19x19-lpddr5-evk/imx95-19x19-lpddr5-evk.dtb

# Decompile an overlay DTBO
dtc -I dtb -O dts -o /tmp/overlay.dts build/tmp/deploy/images/imx95-19x19-lpddr5-evk/imx95-custom.dtbo
```

### Dump DTB contents with `fdtdump`

```bash
# Dump full DTB
fdtdump build/tmp/deploy/images/imx95-19x19-lpddr5-evk/imx95-19x19-lpddr5-evk.dtb

# Search for a specific node
fdtdump build/tmp/deploy/images/imx95-19x19-lpddr5-evk/imx95-19x19-lpddr5-evk.dtb | grep -A 10 "lpuart4"

# Check model string
fdtdump build/tmp/deploy/images/imx95-19x19-lpddr5-evk/imx95-19x19-lpddr5-evk.dtb | grep model
```

### Apply Overlay to Base DTB (host-side merge test)

```bash
# Merge overlay into base DTB to verify compatibility
fdtoverlay -i base.dtb -o merged.dtb overlay.dtbo

# Then inspect the merged result
dtc -I dtb -O dts -o merged.dts merged.dtb
grep -A 20 "lpuart4" merged.dts
```

---

## DT Overlay Kernel Makefile Integration

When the overlay is copied into the kernel source tree by the bbappend, it must also be
listed in the kernel's DTS Makefile. The `KERNEL_DEVICETREE` variable in the bbappend
handles this automatically for Yocto builds. For manual builds:

```makefile
# arch/arm64/boot/dts/freescale/Makefile
# (This is handled automatically by KERNEL_DEVICETREE in bbappend)
dtb-$(CONFIG_ARCH_MXC) += imx95-custom.dtbo
```

---

## Overlay Compatibility Rules

### Rule 1: Overlay Must Reference Valid Node Labels

The overlay uses `&label {}` syntax to reference nodes in the base DTB. The label must
exist in the base DTS or its included DTSI files.

```bash
# Find available node labels in the base DTS:
grep -r "^[a-z].*:" sources/linux-imx/arch/arm64/boot/dts/freescale/imx95-19x19-lpddr5-evk.dts
grep -r "^[a-z].*:" sources/linux-imx/arch/arm64/boot/dts/freescale/imx95.dtsi
```

### Rule 2: Overlay Cannot Add New Top-Level Nodes (Easily)

Adding entirely new hardware nodes (not overriding existing ones) requires using the
`fragment@N` syntax or placing the node under an existing bus node.

```dts
/* Adding a new I2C device under an existing I2C bus — correct */
&lpi2c3 {
    status = "okay";
    my_sensor: sensor@48 {
        compatible = "ti,tmp102";
        reg = <0x48>;
    };
};
```

### Rule 3: Property Override vs. Append

```dts
/* Override a property (replaces existing value) */
&lpuart4 {
    status = "okay";    /* replaces "disabled" */
};

/* Append to a property */
&iomuxc {
    /* Adding a new pinctrl group — this is an append to the iomuxc node */
    pinctrl_uart4: uart4grp {
        fsl,pins = < ... >;
    };
};
```

---

## Troubleshooting

### "undefined node reference" error

```
ERROR: /plugin/: undefined node reference to phandle
```
**Cause:** The overlay references a node label that doesn't exist in the base DTB.  
**Fix:** Check the label name against the base DTS. Use `grep` to find the correct label.

### "duplicate label" warning

```
Warning (duplicate_label): ...
```
**Cause:** Two nodes in the overlay have the same label.  
**Fix:** Rename one of the labels to be unique.

### Overlay not applied at boot

**Symptoms:** `dmesg` shows no evidence of overlay nodes; `cat /proc/device-tree/model` shows
base board model, not custom model.  
**Fix:** Check U-Boot `fdtoverlays` environment variable:
```bash
# In U-Boot:
printenv fdtoverlays
# Should show: imx95-custom.dtbo
```

### Node enabled in overlay but not probed

**Symptoms:** `dmesg` shows no driver probe for the peripheral.  
**Fix:** Verify `status = "okay"` is set in the overlay AND the driver is compiled into the
kernel (check `bitbake linux-imx -c menuconfig`).
