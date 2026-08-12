---
name: imx95-customize-pinmux
version: "1.0"
platform: imx95
phase: customize
invoke_when:
  - "change pinmux"
  - "configure IOMUX"
  - "set pin function"
  - "enable UART on pads"
  - "configure SPI pins"
  - "set GPIO direction"
  - "pin conflict"
  - "pad configuration"
requires_host_tools:
  - dtc
  - git
safe: true
destructive: false
commit_gate: true
---

# imx95-customize-pinmux

## Purpose

Modify IOMUX/pinmux configuration in the device tree overlay. Handles pad function
selection, drive strength, pull-up/pull-down, slew rate, and open-drain settings using
the i.MX 95 IOMUX controller DT bindings.

## When to Invoke

- User needs to change a pin's function (e.g., enable UART4 on specific pads)
- User needs to configure SPI CS, I2C, GPIO, PWM, or other peripheral pins
- Bring-up reveals a pin conflict or wrong pad function
- User says "change pinmux", "configure IOMUX", "set pin function"

## Pre-conditions

1. `targets/active_target.yaml` exists with `board.custom_carrier: true` OR user is
   modifying the FRDM-IMX95 base overlay.
2. `overlay-tracker/` git repo is initialized and working tree is clean.
3. `sources/meta-imx95-custom/recipes-kernel/linux/files/overlays/` exists.

## CRITICAL RULE — Commit-Gate

**Every DT change MUST be committed to overlay-tracker before building.**
Show `git diff --staged` and wait for explicit user approval before every `git commit`.
See CLAUDE.md Section 8.

## i.MX 95 IOMUX Model

- IOMUX controller node: `&iomuxc` in DTS
- Pin groups defined as `pinctrl_<peripheral>` sub-nodes under `&iomuxc`
- Property: `fsl,pins = <MX95_PAD_xxx__FUNC  PAD_CTL_value>;`
- PAD_CTL is a 32-bit hex value encoding: DSE (drive strength), PUE (pull enable),
  PUS (pull select), SRE (slew rate), ODE (open drain), FSEL (fast slew)

### Common PAD_CTL Values

| Value  | Meaning |
|--------|---------|
| `0x31e` | DSE=6, PUE=1, PUS=1 (pull-up), SRE=0 — general purpose |
| `0x40000031e` | Same + SION (force input) |
| `0x1fe` | DSE=6, PUE=1, PUS=0 (pull-down) |
| `0x0`   | No pull, low drive strength |
| `0x31f` | DSE=7 (max drive), PUE=1, PUS=1 |

See `references/bsp-customization-iomux-dt.md` for full encoding table.

## Questions to Ask User

Before modifying any DT file:

1. **Which peripheral?** (UART, SPI, I2C, GPIO, PWM, etc.)
2. **Which pad names?** (e.g., `GPIO_IO04`, `GPIO_IO05`) — ask for schematic if unsure
3. **Which function?** (e.g., `LPUART4_TX`, `LPUART4_RX`)
4. **Pull-up, pull-down, or none?**
5. **Drive strength?** (default: DSE=6)
6. **Open drain?** (for I2C: yes; for UART/SPI: no)

**NEVER assume pad assignments from another board's DTS. Always ask for the schematic.**

## Procedure

### Step 1 — Read active target

Extract `paths.dt_overlay_dir` from `targets/active_target.yaml`.
Identify the pinmux overlay file: `imx95-<carrier-name>-pinmux.dts` or main overlay.

### Step 2 — Read existing overlay

Read the current pinmux overlay file to understand existing pin groups.
Check for any existing `pinctrl_<peripheral>` groups that might conflict.

### Step 3 — Run validation (pre-change)

```bash
bash skills/imx95-customize-pinmux/scripts/validate_pinmux.sh --pre-check
```

### Step 4 — Generate new pinmux node

Construct the DT snippet:

```dts
&iomuxc {
    pinctrl_<peripheral>: <peripheral>grp {
        fsl,pins = <
            MX95_PAD_<PAD>__<FUNC>    <PAD_CTL>    /* comment */
            MX95_PAD_<PAD>__<FUNC>    <PAD_CTL>    /* comment */
        >;
    };
};

&<peripheral_node> {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_<peripheral>>;
    status = "okay";
};
```

### STOP — Show generated DT snippet to user

Display the complete DT snippet. State: "Here is the pinmux configuration I will add.
Please review and reply 'approve' to proceed, or tell me what to change."

Wait for explicit approval.

### Step 5 — Apply change to overlay file

Edit the pinmux overlay file to add the new pin group.

### Step 6 — Run validation (post-change)

```bash
bash skills/imx95-customize-pinmux/scripts/validate_pinmux.sh
```

This checks:
- `dtc` compiles the overlay without errors
- No duplicate pad assignments across all overlay files

Fix any errors before proceeding.

### Step 7 — Commit to overlay-tracker (commit-gate)

```bash
cd overlay-tracker/
git add <overlay-file>
git diff --staged
```

**STOP — display complete diff, wait for approval, then commit.**

Commit message format:
```
customize(pinmux): <one-line summary>

Board: <profile_name>
Skill: imx95-customize-pinmux
Files: <overlay-file>

<Description of what was changed and why>

Tested: pending
```

### Step 8 — Report to user

Print:
- Overlay file modified
- Commit SHA
- Recommended next step (build or more customization)

## Files Touched

- `sources/meta-imx95-custom/recipes-kernel/linux/files/overlays/imx95-<name>-pinmux.dts`
- `overlay-tracker/` (committed)

## Safety Rules Applied

- **R2** — Only meta-imx95-custom overlays modified; upstream kernel DTS untouched
- **R3** — DT changes committed to overlay-tracker before building
- **R4** — Commit-gate: full diff shown before every commit
- **R5** — Never assume pad names; always ask for schematic

## Example

```dts
/* Enable UART4 on GPIO_IO04 (TX) and GPIO_IO05 (RX) */
&iomuxc {
    pinctrl_uart4: uart4grp {
        fsl,pins = <
            MX95_PAD_GPIO_IO04__LPUART4_TX    0x31e  /* TX: DSE=6, pull-up */
            MX95_PAD_GPIO_IO05__LPUART4_RX    0x31e  /* RX: DSE=6, pull-up */
        >;
    };
};

&lpuart4 {
    pinctrl-names = "default";
    pinctrl-0 = <&pinctrl_uart4>;
    status = "okay";
};
```

## References

- `references/bsp-customization-iomux-dt.md` — full IOMUX reference
- `references/bsp-customization-io-devices.md` — common IO device DT patterns
- `context/bsp-customization-workflow.md` — workflow context
