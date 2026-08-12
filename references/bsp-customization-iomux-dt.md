# i.MX 95 IOMUX Device Tree Customization Reference

> **Reference document** for `imx95-customize-pinmux` and `imx95-derive-carrier`.
> Covers pad naming, PAD_CTL encoding, pinmux group creation, and common mistakes.

---

## Overview

The i.MX 95 uses the **IOMUX Controller (IOMUXC)** to configure pad functions, drive strength,
pull resistors, slew rate, and open-drain mode. All pin configuration is done in the device
tree using `fsl,pins` properties — there is no spreadsheet tool or binary config file.

The IOMUXC DT node is `iomuxc` in the SoC DTSI. Pin groups are defined as sub-nodes of
`iomuxc` and referenced by peripheral nodes via `pinctrl-0`.

---

## Pad Naming Convention

### Format

```
MX95_PAD_<PAD_NAME>__<FUNCTION>
```

- `MX95_PAD_` — fixed prefix for all i.MX 95 pads
- `<PAD_NAME>` — physical pad name from the SoC datasheet (e.g., `GPIO_IO04`, `UART1_TXD`)
- `__` — double underscore separates pad name from function (mux mode)
- `<FUNCTION>` — peripheral function assigned to this pad (e.g., `LPUART4_TX`, `LPSPI1_SCK`)

### Examples

```
MX95_PAD_GPIO_IO04__LPUART4_TX       GPIO_IO04 pad → UART4 TX function
MX95_PAD_GPIO_IO05__LPUART4_RX       GPIO_IO05 pad → UART4 RX function
MX95_PAD_GPIO_IO00__LPSPI1_SCK       GPIO_IO00 pad → SPI1 clock function
MX95_PAD_GPIO_IO01__LPSPI1_PCS0      GPIO_IO01 pad → SPI1 chip select 0
MX95_PAD_GPIO_IO02__LPSPI1_SOUT      GPIO_IO02 pad → SPI1 MOSI
MX95_PAD_GPIO_IO03__LPSPI1_SIN       GPIO_IO03 pad → SPI1 MISO
MX95_PAD_GPIO_IO08__LPI2C1_SCL       GPIO_IO08 pad → I2C1 clock
MX95_PAD_GPIO_IO09__LPI2C1_SDA       GPIO_IO09 pad → I2C1 data
MX95_PAD_GPIO_IO04__GPIO2_IO04       GPIO_IO04 pad → GPIO function (GPIO bank 2, pin 4)
```

### Where to Find Pad Definitions

Pad macros are defined in the kernel header:
```
sources/linux-imx/include/dt-bindings/pinctrl/pinfunc-imx95.h
```

This file lists every valid `MX95_PAD_xxx__FUNC` combination. Always check this file to
confirm a pad/function combination is valid before using it in a DTS.

---

## PAD_CTL Value Encoding

The second value in each `fsl,pins` entry is the PAD_CTL (pad control) register value.
It is a 32-bit hex value encoding drive strength, pull, slew rate, and open-drain settings.

### PAD_CTL Bit Fields (i.MX 95)

```
Bit  31:7  — Reserved (set to 0)
Bit  6     — HYS  : Hysteresis enable (0=CMOS, 1=Schmitt trigger)
Bit  5     — PDE  : Pull-down enable (1=enable pull-down)
Bit  4     — PUE  : Pull-up enable (1=enable pull-up)
Bit  3     — ODE  : Open-drain enable (1=open-drain, 0=push-pull)
Bit  2:1   — DSE  : Drive strength
             00 = X1 (weakest)
             01 = X2
             10 = X4
             11 = X6 (strongest)
Bit  0     — SRE  : Slew rate (0=slow, 1=fast)
```

### Common PAD_CTL Values

| Value | HYS | PDE | PUE | ODE | DSE | SRE | Use case |
|---|---|---|---|---|---|---|---|
| `0x000` | 0 | 0 | 0 | 0 | X1 | slow | GPIO output, minimal drive |
| `0x006` | 0 | 0 | 0 | 0 | X4 | slow | General purpose output |
| `0x01e` | 0 | 0 | 0 | 0 | X6 | slow | High-drive output (LED, power) |
| `0x31e` | 0 | 0 | 1 | 0 | X6 | slow | UART TX/RX with pull-up |
| `0x11e` | 0 | 1 | 0 | 0 | X6 | slow | UART with pull-down |
| `0x400` | 1 | 0 | 0 | 0 | X1 | slow | GPIO input with hysteresis |
| `0x41e` | 1 | 0 | 0 | 0 | X6 | slow | GPIO input, high drive |
| `0x1fe` | 0 | 0 | 1 | 1 | X6 | slow | I2C (open-drain + pull-up) |
| `0x007` | 0 | 0 | 0 | 0 | X4 | fast | High-speed SPI clock |
| `0x317` | 0 | 0 | 1 | 0 | X6 | fast | High-speed UART |

### Recommended Values by Peripheral

| Peripheral | Signal | Recommended PAD_CTL | Notes |
|---|---|---|---|
| LPUART (UART) | TX | `0x31e` | Pull-up, X6 drive, slow slew |
| LPUART (UART) | RX | `0x31e` | Pull-up, X6 drive, slow slew |
| LPI2C (I2C) | SCL | `0x1fe` | Open-drain, pull-up, X6 drive |
| LPI2C (I2C) | SDA | `0x1fe` | Open-drain, pull-up, X6 drive |
| LPSPI (SPI) | SCK | `0x007` | Fast slew for clock |
| LPSPI (SPI) | MOSI/MISO | `0x006` | Standard drive |
| LPSPI (SPI) | CS | `0x31e` | Pull-up (active-low CS) |
| GPIO output | — | `0x006` | X4 drive, slow slew |
| GPIO input | — | `0x400` | Hysteresis, no drive |
| PWM | — | `0x01e` | X6 drive, slow slew |
| CAN TX | — | `0x31e` | Pull-up, X6 drive |
| CAN RX | — | `0x31e` | Pull-up, X6 drive |

---

## How to Add a Pinmux Group

### Step 1: Identify the Pad and Function

1. Check the schematic for the physical net name (e.g., "UART4_TX")
2. Find the corresponding SoC pad name in the datasheet (e.g., "GPIO_IO04")
3. Find the mux function in `pinfunc-imx95.h`:
   ```bash
   grep "GPIO_IO04" sources/linux-imx/include/dt-bindings/pinctrl/pinfunc-imx95.h
   ```
   Output example:
   ```
   #define MX95_PAD_GPIO_IO04__LPUART4_TX    0x0068 0x02c8 0x0000 0x1 0x0
   #define MX95_PAD_GPIO_IO04__GPIO2_IO04    0x0068 0x02c8 0x0000 0x5 0x0
   ```

### Step 2: Create the Pinmux Group in the Overlay

Add a `pinctrl_<peripheral>` sub-node inside `&iomuxc`:

```dts
&iomuxc {
    /* UART4 pinmux group */
    pinctrl_uart4: uart4grp {
        fsl,pins = <
            MX95_PAD_GPIO_IO04__LPUART4_TX    0x31e
            MX95_PAD_GPIO_IO05__LPUART4_RX    0x31e
        >;
    };
};
```

### Step 3: Assign the Pinmux Group to the Peripheral Node

Reference the pinmux group from the peripheral node:

```dts
&lpuart4 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_uart4>;
    status = "okay";
};
```

### Step 4: Validate

```bash
# Compile the overlay to check for syntax errors
dtc -I dts -O dtb -o /tmp/test.dtb your-overlay.dts

# Check for warnings (treat all warnings as errors)
dtc -I dts -O dtb -W no-unit_address_vs_reg -o /tmp/test.dtb your-overlay.dts 2>&1 | grep -i "warning\|error"
```

---

## How to Assign a Pinmux Group to a Device Node

### Standard Pattern

```dts
/* In the overlay file */

/* 1. Define the pinmux group */
&iomuxc {
    pinctrl_lpi2c3: lpi2c3grp {
        fsl,pins = <
            MX95_PAD_GPIO_IO28__LPI2C3_SCL    0x1fe
            MX95_PAD_GPIO_IO29__LPI2C3_SDA    0x1fe
        >;
    };
};

/* 2. Assign to the peripheral and enable it */
&lpi2c3 {
    clock-frequency = <400000>;    /* 400 kHz fast mode */
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_lpi2c3>;
    status = "okay";

    /* Add child devices here */
    sensor@48 {
        compatible = "ti,tmp102";
        reg = <0x48>;
    };
};
```

### Multiple Pinmux States

Some peripherals support multiple pinmux states (e.g., default and sleep):

```dts
&iomuxc {
    pinctrl_uart4_default: uart4grp_default {
        fsl,pins = <
            MX95_PAD_GPIO_IO04__LPUART4_TX    0x31e
            MX95_PAD_GPIO_IO05__LPUART4_RX    0x31e
        >;
    };

    pinctrl_uart4_sleep: uart4grp_sleep {
        fsl,pins = <
            MX95_PAD_GPIO_IO04__GPIO2_IO04    0x400  /* Hi-Z in sleep */
            MX95_PAD_GPIO_IO05__GPIO2_IO05    0x400
        >;
    };
};

&lpuart4 {
    pinctrl-names = "default", "sleep";
    pinctrl-0 = <&pinctrl_uart4_default>;
    pinctrl-1 = <&pinctrl_uart4_sleep>;
    status = "okay";
};
```

---

## i.MX 95 Peripheral Node Names

| Peripheral | DT node name | Notes |
|---|---|---|
| UART 1–8 | `lpuart1` – `lpuart8` | Low-power UART |
| I2C 1–8 | `lpi2c1` – `lpi2c8` | Low-power I2C |
| SPI 1–8 | `lpspi1` – `lpspi8` | Low-power SPI |
| GPIO bank 1 | `gpio1` | Pads GPIO_IO00–GPIO_IO07 |
| GPIO bank 2 | `gpio2` | Pads GPIO_IO08–GPIO_IO15 |
| GPIO bank 3 | `gpio3` | Pads GPIO_IO16–GPIO_IO23 |
| GPIO bank 4 | `gpio4` | Pads GPIO_IO24–GPIO_IO31 |
| PWM 1–4 | `tpm1` – `tpm4` | Timer/PWM module |
| CAN 1–2 | `flexcan1` – `flexcan2` | FlexCAN |
| USB3 OTG | `usb3_0` / `dwc3_0` | USB3.0 SuperSpeed |
| USB2 Host | `usbotg2` | USB2.0 HS |
| PCIe 1 | `pcie0` | PCIe Gen3 x1 |
| PCIe 2 | `pcie1` | PCIe Gen3 x1 |
| MIPI CSI 0 | `mipi_csi0` | MIPI-CSI2 receiver |
| MIPI CSI 1 | `mipi_csi1` | MIPI-CSI2 receiver |
| MIPI DSI | `mipi_dsi` | MIPI-DSI transmitter |
| Ethernet 1 | `eqos` | EQOS GbE |
| Ethernet 2 | `fec` | FEC GbE |
| SAI (I2S) 1–4 | `sai1` – `sai4` | Serial Audio Interface |
| IOMUXC | `iomuxc` | Pin mux controller |

---

## Common Mistakes

### Mistake 1: Using Wrong Pad Macro Name

```dts
/* WRONG — macro does not exist */
fsl,pins = <MX95_PAD_GPIO_IO4__LPUART4_TX  0x31e>;

/* CORRECT — use exact name from pinfunc-imx95.h */
fsl,pins = <MX95_PAD_GPIO_IO04__LPUART4_TX  0x31e>;
```

Always verify the exact macro name with:
```bash
grep "GPIO_IO04" sources/linux-imx/include/dt-bindings/pinctrl/pinfunc-imx95.h
```

### Mistake 2: Duplicate Pad Assignment

Assigning the same physical pad to two different functions causes a kernel warning and
unpredictable behavior. The `validate_pinmux.sh` script checks for this.

```dts
/* WRONG — GPIO_IO04 assigned twice */
pinctrl_uart4: uart4grp {
    fsl,pins = <MX95_PAD_GPIO_IO04__LPUART4_TX  0x31e>;
};
pinctrl_spi1: spi1grp {
    fsl,pins = <MX95_PAD_GPIO_IO04__LPSPI1_SCK  0x007>;  /* CONFLICT! */
};
```

### Mistake 3: Missing `#include` for Pad Macros

The overlay DTS must include the pad macro header:

```dts
/* CORRECT — include at top of overlay file */
#include <dt-bindings/pinctrl/pinfunc-imx95.h>
```

Without this include, the compiler will fail with "undefined identifier" errors.

### Mistake 4: Wrong PAD_CTL for I2C (Missing Open-Drain)

I2C requires open-drain mode. Forgetting `ODE=1` causes I2C bus contention.

```dts
/* WRONG — no open-drain for I2C */
MX95_PAD_GPIO_IO28__LPI2C3_SCL    0x01e

/* CORRECT — open-drain (bit 3 = 1) + pull-up (bit 4 = 1) */
MX95_PAD_GPIO_IO28__LPI2C3_SCL    0x1fe
```

### Mistake 5: Forgetting `status = "okay"`

A peripheral node with correct pinmux but no `status = "okay"` will not be probed by the
kernel. The default status in the base DTS is often `"disabled"`.

```dts
/* WRONG — peripheral disabled */
&lpuart4 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_uart4>;
    /* status not set — defaults to "disabled" */
};

/* CORRECT */
&lpuart4 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_uart4>;
    status = "okay";
};
```

### Mistake 6: Editing Base DTS Instead of Overlay

Never edit `sources/linux-imx/arch/arm64/boot/dts/freescale/imx95-19x19-lpddr5-evk.dts`.
Changes there are lost on `repo sync`. Always create an overlay in `dt_overlay_dir`.

---

## Validation Script

Use `skills/imx95-customize-pinmux/scripts/validate_pinmux.sh` to check an overlay file:

```bash
./validate_pinmux.sh path/to/overlay.dts
```

The script checks:
1. `dtc` compiles the file without errors
2. No duplicate pad assignments across all overlay files in `dt_overlay_dir`
3. All referenced pad macros exist in `pinfunc-imx95.h`
4. All peripheral nodes with pinctrl have `status = "okay"`
