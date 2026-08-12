---
name: imx95-customize-clocks
version: "1.0"
platform: imx95
phase: customize
invoke_when:
  - "change clock"
  - "set clock frequency"
  - "clock assignment"
  - "CLKO output"
  - "assigned-clocks"
  - "clock parent"
  - "peripheral clock"
requires_host_tools:
  - dtc
  - git
safe: true
destructive: false
commit_gate: true
---

# imx95-customize-clocks

## Purpose

Modify clock assignments in the device tree overlay. Handles `assigned-clocks`,
`assigned-clock-parents`, `assigned-clock-rates` patterns, enabling CLKO1/CLKO2 clock
output pads, and overriding peripheral clock frequencies.

## When to Invoke

- A peripheral needs a non-default clock frequency
- Enabling a clock output pin (CLKO1/CLKO2) for an external device (e.g., camera MCLK)
- Debugging a clock-related boot failure or peripheral malfunction
- User says "change clock", "set clock frequency", "CLKO output"

## Pre-conditions

1. `targets/active_target.yaml` exists.
2. Carrier overlay file exists.
3. `overlay-tracker/` is initialized and clean.
4. User knows the target frequency and which peripheral needs it.

## CRITICAL SAFETY RULE

**NEVER change PLL frequencies or core clock rates (A55 CPU, DDR, NOC) without explicit
user confirmation and thermal/power analysis.** Only modify leaf peripheral clocks unless
the user explicitly requests and understands the implications of changing a PLL.

## i.MX 95 Clock Model

The i.MX 95 uses the **CCM (Clock Control Module)** to manage all peripheral clocks.

### Clock Controller Node

```dts
clk: clock-controller@44450000 {
    compatible = "nxp,imx95-ccm";
    /* ... */
};
```

### assigned-clocks Pattern

```dts
&<peripheral> {
    assigned-clocks = <&clk IMX95_CLK_<NAME>>;
    assigned-clock-parents = <&clk IMX95_CLK_<PARENT>>;
    assigned-clock-rates = <FREQ_HZ>;
};
```

### Common Clock IDs (imx95-clock.h)

| Clock ID | Description |
|---|---|
| `IMX95_CLK_CCM_CKO1` | CLKO1 output pad clock |
| `IMX95_CLK_CCM_CKO2` | CLKO2 output pad clock |
| `IMX95_CLK_LPUART1` | LPUART1 clock |
| `IMX95_CLK_LPI2C1` | LPI2C1 clock |
| `IMX95_CLK_LPSPI1` | LPSPI1 clock |
| `IMX95_CLK_SAI1` | SAI1 audio clock |
| `IMX95_CLK_ENET` | Ethernet clock |
| `IMX95_CLK_USDHC1` | USDHC1 (eMMC) clock |
| `IMX95_CLK_SYS_PLL1_PFD0` | SYS PLL1 PFD0 (800 MHz) |
| `IMX95_CLK_SYS_PLL1_PFD1` | SYS PLL1 PFD1 (1000 MHz) |
| `IMX95_CLK_24M` | 24 MHz oscillator |

### CLKO1/CLKO2 Output Pads

CLKO1 and CLKO2 are configurable clock output pads useful for providing MCLK to
external devices (cameras, audio codecs, etc.).

```dts
/* Enable CLKO1 at 24 MHz for camera MCLK */
&clk {
    assigned-clocks = <&clk IMX95_CLK_CCM_CKO1>;
    assigned-clock-parents = <&clk IMX95_CLK_24M>;
    assigned-clock-rates = <24000000>;
};
```

The CLKO pad must also be configured in IOMUX:
```dts
&iomuxc {
    pinctrl_clko1: clko1grp {
        fsl,pins = <
            MX95_PAD_CCM_CLKO1__CCMSRCGPCMIX_CLKO1    0x31e
        >;
    };
};
```

## Questions to Ask User

1. **Which peripheral or output?** (UART, I2C, SPI, SAI, CLKO1, CLKO2, etc.)
2. **Target frequency?** (in Hz)
3. **Clock parent?** (usually `IMX95_CLK_24M` or a PLL PFD — ask if unsure)
4. **Why is the default frequency insufficient?** (helps validate the request)

## Procedure

### Step 1 — Read active target and existing overlay

### Step 2 — Generate clock DT snippet

Based on user answers, construct the `assigned-clocks` snippet.

### STOP — Show generated snippet to user

Display the complete DT snippet. Wait for explicit approval.

### Step 3 — Apply to overlay file

### Step 4 — Validate with dtc

```bash
dtc -@ -I dts -O dtb -o /dev/null <overlay-file>
```

### Step 5 — Commit to overlay-tracker (commit-gate)

Show `git diff --staged`, wait for approval, then commit.

Commit message:
```
customize(clocks): <one-line summary>

Board: <profile_name>
Skill: imx95-customize-clocks
Files: <overlay-file>

<Description of clock change and reason>

Tested: pending
```

## DT Snippet Examples

### CLKO1 at 24 MHz (camera MCLK)

```dts
/* Configure CLKO1 as 24 MHz output for camera MCLK */
&clk {
    assigned-clocks        = <&clk IMX95_CLK_CCM_CKO1>;
    assigned-clock-parents = <&clk IMX95_CLK_24M>;
    assigned-clock-rates   = <24000000>;
};

&iomuxc {
    pinctrl_clko1: clko1grp {
        fsl,pins = <
            MX95_PAD_CCM_CLKO1__CCMSRCGPCMIX_CLKO1    0x31e
        >;
    };
};
```

### LPUART4 clock at 80 MHz

```dts
&lpuart4 {
    assigned-clocks        = <&clk IMX95_CLK_LPUART4>;
    assigned-clock-parents = <&clk IMX95_CLK_SYS_PLL1_PFD0_DIV2>;
    assigned-clock-rates   = <80000000>;
};
```

### SAI1 audio clock from audio PLL

```dts
&sai1 {
    assigned-clocks        = <&clk IMX95_CLK_SAI1>;
    assigned-clock-parents = <&clk IMX95_CLK_AUDIO_PLL1>;
    assigned-clock-rates   = <12288000>;
};
```

## Files Touched

- `sources/meta-imx95-custom/recipes-kernel/linux/files/overlays/imx95-<name>.dts`
- `overlay-tracker/` (committed)

## Safety Rules Applied

- **R2** — Only meta-imx95-custom overlays modified
- **R3** — DT changes committed before building
- **R4** — Commit-gate on every commit
- **R5** — Never change PLL/core clocks without explicit user confirmation

## References

- `references/bsp-customization-iomux-dt.md` — CLKO pad configuration
- `references/bsp-customization-kernel-dtb.md` — overlay structure
- `context/bsp-customization-workflow.md` — workflow context
