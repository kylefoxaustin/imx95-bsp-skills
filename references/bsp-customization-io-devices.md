# Common IO Device DT Patterns — i.MX 95

> **Reference document** for all customize skills. Provides minimal working DT snippets
> for common IO devices on i.MX 95. Use these as starting points for overlay files.

---

## Overview

This document provides copy-paste DT overlay snippets for the most common IO devices on
i.MX 95. Each snippet is a minimal working example that can be placed in an overlay file.

**Before using any snippet:**
1. Verify the pad names against your schematic (never assume pad assignments)
2. Verify the I2C/SPI address against your device datasheet
3. Check that the peripheral node label exists in the base DTS
4. Run `validate_pinmux.sh` after adding pinmux entries

---

## I2C (LPI2C)

### Minimal I2C Bus Enable

```dts
// SPDX-License-Identifier: GPL-2.0+
/dts-v1/;
/plugin/;

#include <dt-bindings/pinctrl/pinfunc-imx95.h>

/* Enable LPI2C3 on GPIO_IO28/29 at 400 kHz */
&iomuxc {
    pinctrl_lpi2c3: lpi2c3grp {
        fsl,pins = <
            /* SCL: open-drain, pull-up, X6 drive */
            MX95_PAD_GPIO_IO28__LPI2C3_SCL    0x1fe
            /* SDA: open-drain, pull-up, X6 drive */
            MX95_PAD_GPIO_IO29__LPI2C3_SDA    0x1fe
        >;
    };
};

&lpi2c3 {
    clock-frequency = <400000>;    /* 400 kHz fast mode */
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_lpi2c3>;
    #address-cells = <1>;
    #size-cells = <0>;
    status = "okay";
};
```

### I2C Bus with a Device (Temperature Sensor Example)

```dts
&lpi2c3 {
    clock-frequency = <400000>;
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_lpi2c3>;
    #address-cells = <1>;
    #size-cells = <0>;
    status = "okay";

    /* TMP102 temperature sensor at address 0x48 */
    tmp102: temperature-sensor@48 {
        compatible = "ti,tmp102";
        reg = <0x48>;
        /* Optional: interrupt GPIO */
        /* interrupt-parent = <&gpio2>; */
        /* interrupts = <10 IRQ_TYPE_LEVEL_LOW>; */
    };
};
```

### I2C Frequency Options

| Mode | Frequency | `clock-frequency` value |
|---|---|---|
| Standard | 100 kHz | `100000` |
| Fast | 400 kHz | `400000` |
| Fast-plus | 1 MHz | `1000000` |

### Common I2C Pad Pairs (i.MX 95)

| I2C Bus | SCL Pad | SDA Pad | SCL Macro | SDA Macro |
|---|---|---|---|---|
| LPI2C1 | GPIO_IO08 | GPIO_IO09 | `MX95_PAD_GPIO_IO08__LPI2C1_SCL` | `MX95_PAD_GPIO_IO09__LPI2C1_SDA` |
| LPI2C2 | GPIO_IO10 | GPIO_IO11 | `MX95_PAD_GPIO_IO10__LPI2C2_SCL` | `MX95_PAD_GPIO_IO11__LPI2C2_SDA` |
| LPI2C3 | GPIO_IO28 | GPIO_IO29 | `MX95_PAD_GPIO_IO28__LPI2C3_SCL` | `MX95_PAD_GPIO_IO29__LPI2C3_SDA` |
| LPI2C4 | GPIO_IO30 | GPIO_IO31 | `MX95_PAD_GPIO_IO30__LPI2C4_SCL` | `MX95_PAD_GPIO_IO31__LPI2C4_SDA` |

---

## SPI (LPSPI)

### Minimal SPI Bus Enable

```dts
// SPDX-License-Identifier: GPL-2.0+
/dts-v1/;
/plugin/;

#include <dt-bindings/pinctrl/pinfunc-imx95.h>

/* Enable LPSPI1 on GPIO_IO00–03 */
&iomuxc {
    pinctrl_lpspi1: lpspi1grp {
        fsl,pins = <
            /* SCK: fast slew for clock signal */
            MX95_PAD_GPIO_IO00__LPSPI1_SCK     0x007
            /* PCS0 (CS): pull-up (active-low) */
            MX95_PAD_GPIO_IO01__LPSPI1_PCS0    0x31e
            /* SOUT (MOSI) */
            MX95_PAD_GPIO_IO02__LPSPI1_SOUT    0x006
            /* SIN (MISO) */
            MX95_PAD_GPIO_IO03__LPSPI1_SIN     0x006
        >;
    };
};

&lpspi1 {
    #address-cells = <1>;
    #size-cells = <0>;
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_lpspi1>;
    status = "okay";
};
```

### SPI Bus with a Device (SPI Flash Example)

```dts
&lpspi1 {
    #address-cells = <1>;
    #size-cells = <0>;
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_lpspi1>;
    status = "okay";

    /* Winbond W25Q128 SPI NOR flash at CS0 */
    flash@0 {
        compatible = "winbond,w25q128", "jedec,spi-nor";
        reg = <0>;                      /* CS0 */
        spi-max-frequency = <50000000>; /* 50 MHz */
        spi-tx-bus-width = <1>;
        spi-rx-bus-width = <1>;
    };
};
```

### SPI with Software CS (GPIO CS)

```dts
#include <dt-bindings/gpio/gpio.h>

&lpspi1 {
    #address-cells = <1>;
    #size-cells = <0>;
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_lpspi1>;
    /* Use GPIO for chip select instead of hardware CS */
    cs-gpios = <&gpio2 4 GPIO_ACTIVE_LOW>;
    status = "okay";

    device@0 {
        compatible = "your,device";
        reg = <0>;
        spi-max-frequency = <10000000>;
    };
};
```

### Common SPI Pad Groups (i.MX 95)

| SPI Bus | SCK | PCS0 (CS) | SOUT (MOSI) | SIN (MISO) |
|---|---|---|---|---|
| LPSPI1 | GPIO_IO00 | GPIO_IO01 | GPIO_IO02 | GPIO_IO03 |
| LPSPI2 | GPIO_IO12 | GPIO_IO13 | GPIO_IO14 | GPIO_IO15 |
| LPSPI3 | GPIO_IO20 | GPIO_IO21 | GPIO_IO22 | GPIO_IO23 |

---

## UART (LPUART)

### Minimal UART Enable (TX/RX only)

```dts
// SPDX-License-Identifier: GPL-2.0+
/dts-v1/;
/plugin/;

#include <dt-bindings/pinctrl/pinfunc-imx95.h>

/* Enable LPUART4 on GPIO_IO04/05 */
&iomuxc {
    pinctrl_lpuart4: lpuart4grp {
        fsl,pins = <
            MX95_PAD_GPIO_IO04__LPUART4_TX    0x31e
            MX95_PAD_GPIO_IO05__LPUART4_RX    0x31e
        >;
    };
};

&lpuart4 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_lpuart4>;
    status = "okay";
};
```

### UART with Hardware Flow Control (RTS/CTS)

```dts
&iomuxc {
    pinctrl_lpuart4_rtscts: lpuart4grp_rtscts {
        fsl,pins = <
            MX95_PAD_GPIO_IO04__LPUART4_TX     0x31e
            MX95_PAD_GPIO_IO05__LPUART4_RX     0x31e
            MX95_PAD_GPIO_IO06__LPUART4_CTS_B  0x31e
            MX95_PAD_GPIO_IO07__LPUART4_RTS_B  0x31e
        >;
    };
};

&lpuart4 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_lpuart4_rtscts>;
    uart-has-rtscts;
    status = "okay";
};
```

### RS-485 UART

```dts
#include <dt-bindings/gpio/gpio.h>

&iomuxc {
    pinctrl_lpuart4_rs485: lpuart4grp_rs485 {
        fsl,pins = <
            MX95_PAD_GPIO_IO04__LPUART4_TX    0x31e
            MX95_PAD_GPIO_IO05__LPUART4_RX    0x31e
            /* DE/RE control GPIO */
            MX95_PAD_GPIO_IO06__GPIO2_IO06    0x006
        >;
    };
};

&lpuart4 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_lpuart4_rs485>;
    linux,rs485-enabled-at-boot-time;
    rs485-rts-active-high;
    /* GPIO for DE/RE (direction enable) */
    rts-gpios = <&gpio2 6 GPIO_ACTIVE_HIGH>;
    status = "okay";
};
```

### Common UART Pad Pairs (i.MX 95)

| UART | TX Pad | RX Pad |
|---|---|---|
| LPUART1 | UART1_TXD | UART1_RXD |
| LPUART2 | UART2_TXD | UART2_RXD |
| LPUART4 | GPIO_IO04 | GPIO_IO05 |
| LPUART5 | GPIO_IO06 | GPIO_IO07 |
| LPUART6 | GPIO_IO20 | GPIO_IO21 |
| LPUART7 | GPIO_IO22 | GPIO_IO23 |

---

## GPIO

### GPIO Output (LED or Enable Signal)

```dts
// SPDX-License-Identifier: GPL-2.0+
/dts-v1/;
/plugin/;

#include <dt-bindings/pinctrl/pinfunc-imx95.h>
#include <dt-bindings/gpio/gpio.h>

/* Configure GPIO_IO16 as output for an LED */
&iomuxc {
    pinctrl_gpio_led: gpio_ledgrp {
        fsl,pins = <
            /* GPIO output: X4 drive, slow slew, no pull */
            MX95_PAD_GPIO_IO16__GPIO3_IO16    0x006
        >;
    };
};

/* Add LED node to root */
/ {
    leds {
        compatible = "gpio-leds";
        pinctrl-names = "default";
        pinctrl-0 = <&pinctrl_gpio_led>;

        user-led {
            label = "user-led";
            gpios = <&gpio3 16 GPIO_ACTIVE_HIGH>;
            default-state = "off";
            linux,default-trigger = "heartbeat";
        };
    };
};
```

### GPIO Input (Button or Interrupt)

```dts
#include <dt-bindings/interrupt-controller/irq.h>

&iomuxc {
    pinctrl_gpio_btn: gpio_btngrp {
        fsl,pins = <
            /* GPIO input: hysteresis, no drive */
            MX95_PAD_GPIO_IO17__GPIO3_IO17    0x400
        >;
    };
};

/ {
    gpio-keys {
        compatible = "gpio-keys";
        pinctrl-names = "default";
        pinctrl-0 = <&pinctrl_gpio_btn>;

        user-button {
            label = "User Button";
            gpios = <&gpio3 17 GPIO_ACTIVE_LOW>;
            linux,code = <KEY_USER>;
            debounce-interval = <20>;
            wakeup-source;
        };
    };
};
```

### GPIO Bank Reference (i.MX 95)

| GPIO Bank | DT node | Pad range | GPIO numbers |
|---|---|---|---|
| GPIO1 | `gpio1` | GPIO_IO00–GPIO_IO07 | gpio1 0–7 |
| GPIO2 | `gpio2` | GPIO_IO08–GPIO_IO15 | gpio2 0–7 |
| GPIO3 | `gpio3` | GPIO_IO16–GPIO_IO23 | gpio3 0–7 |
| GPIO4 | `gpio4` | GPIO_IO24–GPIO_IO31 | gpio4 0–7 |

**Note:** GPIO_IO04 maps to `gpio1 4` (bank 1, pin 4). GPIO_IO16 maps to `gpio3 0` (bank 3,
pin 0). The GPIO bank number is `(pad_number / 8) + 1` and the pin within the bank is
`pad_number % 8`.

---

## PWM (TPM — Timer/PWM Module)

### Minimal PWM Enable

```dts
// SPDX-License-Identifier: GPL-2.0+
/dts-v1/;
/plugin/;

#include <dt-bindings/pinctrl/pinfunc-imx95.h>

/* Enable TPM3 channel 0 on GPIO_IO24 */
&iomuxc {
    pinctrl_tpm3: tpm3grp {
        fsl,pins = <
            /* PWM output: X4 drive, slow slew */
            MX95_PAD_GPIO_IO24__TPM3_CH0    0x006
        >;
    };
};

&tpm3 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_tpm3>;
    status = "okay";
};
```

### PWM Consumer (Backlight Example)

```dts
/ {
    backlight: backlight {
        compatible = "pwm-backlight";
        pwms = <&tpm3 0 50000 0>;   /* TPM3 ch0, 50us period (20kHz), normal polarity */
        brightness-levels = <0 4 8 16 32 64 128 255>;
        default-brightness-level = <6>;
        power-supply = <&reg_5v>;
    };
};
```

### Common PWM Pads (i.MX 95)

| TPM | Channel | Pad | Macro |
|---|---|---|---|
| TPM1 | CH0 | GPIO_IO00 | `MX95_PAD_GPIO_IO00__TPM1_CH0` |
| TPM2 | CH0 | GPIO_IO02 | `MX95_PAD_GPIO_IO02__TPM2_CH0` |
| TPM3 | CH0 | GPIO_IO24 | `MX95_PAD_GPIO_IO24__TPM3_CH0` |
| TPM4 | CH0 | GPIO_IO26 | `MX95_PAD_GPIO_IO26__TPM4_CH0` |

---

## CAN (FlexCAN)

### Minimal CAN Bus Enable

```dts
// SPDX-License-Identifier: GPL-2.0+
/dts-v1/;
/plugin/;

#include <dt-bindings/pinctrl/pinfunc-imx95.h>

/* Enable FlexCAN1 */
&iomuxc {
    pinctrl_flexcan1: flexcan1grp {
        fsl,pins = <
            MX95_PAD_GPIO_IO20__CAN1_TX    0x31e
            MX95_PAD_GPIO_IO21__CAN1_RX    0x31e
        >;
    };
};

&flexcan1 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_flexcan1>;
    status = "okay";
};
```

### CAN with Transceiver Enable GPIO

```dts
#include <dt-bindings/gpio/gpio.h>

&iomuxc {
    pinctrl_flexcan1: flexcan1grp {
        fsl,pins = <
            MX95_PAD_GPIO_IO20__CAN1_TX    0x31e
            MX95_PAD_GPIO_IO21__CAN1_RX    0x31e
            /* Transceiver standby/enable GPIO */
            MX95_PAD_GPIO_IO22__GPIO3_IO06 0x006
        >;
    };
};

&flexcan1 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_flexcan1>;
    /* Transceiver enable: active-low standby */
    xceiver-supply = <&reg_can_stby>;
    status = "okay";
};

/ {
    reg_can_stby: regulator-can-stby {
        compatible = "regulator-fixed";
        regulator-name = "can-stby";
        regulator-min-microvolt = <3300000>;
        regulator-max-microvolt = <3300000>;
        gpio = <&gpio3 6 GPIO_ACTIVE_LOW>;
        enable-active-low;
    };
};
```

---

## Regulator (Fixed Voltage Rail)

### Fixed Regulator (GPIO-controlled power rail)

```dts
// SPDX-License-Identifier: GPL-2.0+
/dts-v1/;
/plugin/;

#include <dt-bindings/pinctrl/pinfunc-imx95.h>
#include <dt-bindings/gpio/gpio.h>

&iomuxc {
    pinctrl_reg_3v3: reg_3v3grp {
        fsl,pins = <
            /* Power enable GPIO: X4 drive */
            MX95_PAD_GPIO_IO25__GPIO4_IO01    0x006
        >;
    };
};

/ {
    reg_3v3_periph: regulator-3v3-periph {
        compatible = "regulator-fixed";
        regulator-name = "3v3-periph";
        regulator-min-microvolt = <3300000>;
        regulator-max-microvolt = <3300000>;
        gpio = <&gpio4 1 GPIO_ACTIVE_HIGH>;
        enable-active-high;
        regulator-boot-on;
        pinctrl-names = "default";
        pinctrl-0 = <&pinctrl_reg_3v3>;
    };
};
```

---

## Complete Multi-Peripheral Overlay Example

This example enables UART4, I2C3, SPI1, and a GPIO LED in a single overlay file:

```dts
// SPDX-License-Identifier: GPL-2.0+
/*
 * Copyright (C) 2024 ACME Corporation
 * Multi-peripheral overlay for ACME Carrier Board v1
 */

/dts-v1/;
/plugin/;

#include <dt-bindings/pinctrl/pinfunc-imx95.h>
#include <dt-bindings/gpio/gpio.h>

/ {
    model = "NXP i.MX95 ACME Carrier Board v1";
    compatible = "acme,imx95-carrier-v1", "nxp,imx95";
};

&iomuxc {
    /* UART4 */
    pinctrl_lpuart4: lpuart4grp {
        fsl,pins = <
            MX95_PAD_GPIO_IO04__LPUART4_TX    0x31e
            MX95_PAD_GPIO_IO05__LPUART4_RX    0x31e
        >;
    };

    /* I2C3 */
    pinctrl_lpi2c3: lpi2c3grp {
        fsl,pins = <
            MX95_PAD_GPIO_IO28__LPI2C3_SCL    0x1fe
            MX95_PAD_GPIO_IO29__LPI2C3_SDA    0x1fe
        >;
    };

    /* SPI1 */
    pinctrl_lpspi1: lpspi1grp {
        fsl,pins = <
            MX95_PAD_GPIO_IO00__LPSPI1_SCK     0x007
            MX95_PAD_GPIO_IO01__LPSPI1_PCS0    0x31e
            MX95_PAD_GPIO_IO02__LPSPI1_SOUT    0x006
            MX95_PAD_GPIO_IO03__LPSPI1_SIN     0x006
        >;
    };

    /* LED GPIO */
    pinctrl_gpio_led: gpio_ledgrp {
        fsl,pins = <
            MX95_PAD_GPIO_IO16__GPIO3_IO00    0x006
        >;
    };
};

&lpuart4 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_lpuart4>;
    status = "okay";
};

&lpi2c3 {
    clock-frequency = <400000>;
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_lpi2c3>;
    #address-cells = <1>;
    #size-cells = <0>;
    status = "okay";
};

&lpspi1 {
    #address-cells = <1>;
    #size-cells = <0>;
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_lpspi1>;
    status = "okay";
};

/ {
    leds {
        compatible = "gpio-leds";
        pinctrl-names = "default";
        pinctrl-0 = <&pinctrl_gpio_led>;

        user-led {
            label = "acme:green:user";
            gpios = <&gpio3 0 GPIO_ACTIVE_HIGH>;
            default-state = "off";
            linux,default-trigger = "heartbeat";
        };
    };
};
```
