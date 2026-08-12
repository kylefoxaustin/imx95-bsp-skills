---
name: imx95-customize-usb
version: "1.0"
platform: imx95
phase: customize
invoke_when:
  - "configure USB"
  - "enable USB3"
  - "USB OTG"
  - "USB host"
  - "USB device mode"
  - "VBUS regulator"
  - "USB role switch"
requires_host_tools:
  - dtc
  - git
safe: true
destructive: false
commit_gate: true
---

# imx95-customize-usb

## Purpose

Configure USB controllers in the device tree overlay. Handles USB3 OTG (SuperSpeed via
`usb3_0`/`dwc3_0` nodes), USB2 host (via `usbotg2`/`ci_hdrc` nodes), VBUS regulator
assignment, and role switching (host/device/OTG).

## When to Invoke

- Enabling or disabling USB ports on a custom carrier
- Changing USB role (host / device / OTG)
- Adding a VBUS regulator GPIO
- Configuring USB for a custom carrier that differs from FRDM-IMX95

## Pre-conditions

1. `targets/active_target.yaml` exists.
2. Carrier overlay file exists (run `imx95-derive-carrier` first for custom boards).
3. `overlay-tracker/` is initialized and clean.

## i.MX 95 USB Architecture

```
USB1 (SuperSpeed OTG):
  usb3_0 (wrapper) → dwc3_0 (DWC3 controller) → usb3_phy0 (SS PHY)
  Connector: USB-C (J301 on FRDM-IMX95)
  Default role: OTG

USB2 (High-Speed Host):
  usbotg2 (wrapper) → ci_hdrc_usb2 (ChipIdea controller) → usbphynop1 (HS PHY)
  Connector: USB-A (J302 on FRDM-IMX95)
  Default role: host
```

## Questions to Ask User

1. **Which USB port?** USB1 (SuperSpeed OTG) or USB2 (HS Host)?
2. **Role?** host / device / otg
3. **VBUS regulator?** GPIO pad name and active-high/low?
4. **USB role switch?** (for OTG: connector type — USB-C with CC detection?)
5. **Any USB peripherals to disable?** (e.g., disable USB2 if not populated on carrier)

## Procedure

### Step 1 — Read active target and existing overlay

Identify the carrier overlay file from `paths.dt_overlay_dir`.

### Step 2 — Run pre-check

```bash
bash skills/imx95-customize-usb/scripts/check_usb_dt.sh
```

### Step 3 — Generate USB DT snippet

Based on user answers, generate the appropriate DT overlay snippet (see examples below).

### STOP — Show generated snippet to user

Display the complete DT snippet. Wait for explicit approval before writing.

### Step 4 — Apply to overlay file

Add the USB configuration to the carrier overlay `.dts` file.

### Step 5 — Validate with dtc

```bash
dtc -@ -I dts -O dtb -o /dev/null <overlay-file>
```

### Step 6 — Commit to overlay-tracker (commit-gate)

Show `git diff --staged`, wait for approval, then commit.

Commit message:
```
customize(usb): <one-line summary>

Board: <profile_name>
Skill: imx95-customize-usb
Files: <overlay-file>

<Description>

Tested: pending
```

## DT Snippet Examples

### USB3 OTG (SuperSpeed, role=otg)

```dts
&usb3_0 {
    status = "okay";
};

&usb3_phy0 {
    status = "okay";
};

&dwc3_0 {
    dr_mode = "otg";
    hnp-disable;
    srp-disable;
    adp-disable;
    usb-role-switch;
    status = "okay";

    port {
        dwc3_0_ep: endpoint {
            remote-endpoint = <&usb_role_switch_ep>;
        };
    };
};
```

### USB3 Host-only (SuperSpeed)

```dts
&usb3_0 {
    status = "okay";
};

&usb3_phy0 {
    status = "okay";
};

&dwc3_0 {
    dr_mode = "host";
    status = "okay";
};
```

### USB3 Device-only (SuperSpeed)

```dts
&usb3_0 {
    status = "okay";
};

&usb3_phy0 {
    status = "okay";
};

&dwc3_0 {
    dr_mode = "peripheral";
    status = "okay";
};
```

### USB2 Host (High-Speed)

```dts
&usbotg2 {
    dr_mode = "host";
    disable-over-current;
    status = "okay";
};
```

### USB2 with VBUS regulator

```dts
/ {
    reg_usb2_vbus: regulator-usb2-vbus {
        compatible = "regulator-fixed";
        regulator-name = "usb2-vbus";
        regulator-min-microvolt = <5000000>;
        regulator-max-microvolt = <5000000>;
        gpio = <&gpio3 28 GPIO_ACTIVE_HIGH>;
        enable-active-high;
    };
};

&usbotg2 {
    dr_mode = "host";
    vbus-supply = <&reg_usb2_vbus>;
    disable-over-current;
    status = "okay";
};
```

### Disable USB port (not populated on carrier)

```dts
&usb3_0 {
    status = "disabled";
};

&usb3_phy0 {
    status = "disabled";
};
```

## Files Touched

- `sources/meta-imx95-custom/recipes-kernel/linux/files/overlays/imx95-<name>.dts`
- `overlay-tracker/` (committed)

## Safety Rules Applied

- **R2** — Only meta-imx95-custom overlays modified
- **R3** — DT changes committed before building
- **R4** — Commit-gate on every commit
- **R5** — Ask user for VBUS GPIO details; never assume

## References

- `references/bsp-customization-iomux-dt.md` — IOMUX for USB VBUS GPIO
- `references/bsp-customization-io-devices.md` — USB DT patterns
- `context/bsp-customization-workflow.md` — workflow context
