---
name: imx95-validate-image
version: "1.0"
platform: imx95
phase: deploy
invoke_when:
  - "validate the image"
  - "check the board"
  - "did it work"
  - "verify boot"
  - "post-flash validation"
  - "check kernel version"
  - "board booted"
requires_host_tools:
  - ssh
  - dtc
safe: true
destructive: false
commit_gate: false
---

# imx95-validate-image

## Purpose

Run a post-flash validation checklist to confirm the board booted correctly and key
subsystems are functional. Combines host-side static checks (artifact checksums, DTB
inspection) with dynamic checks via SSH or serial console to the board.

## When to Invoke

- After `imx95-flash-image` and board has been powered on with eMMC boot jumpers set
- User says "validate the image", "check the board", "did it work?"

## Pre-conditions

1. Board has been flashed and powered on with correct boot jumpers (SW1[1]=ON for eMMC).
2. Board has had time to boot (typically 30–60 seconds to login prompt).
3. Either:
   - Serial console connected (USB-UART via J1003, 115200 8N1), OR
   - SSH access available (board on network, default IP or DHCP)

## Serial Console Connection (FRDM-IMX95)

```bash
# USB-UART debug port: J1003 (micro-USB)
# Baud rate: 115200 8N1
screen /dev/ttyUSB0 115200
# or
minicom -D /dev/ttyUSB0 -b 115200
```

## Procedure

### Step 1 — Host-side static checks

Run without board connection:
```bash
bash skills/imx95-validate-image/scripts/validate.sh --static-only
```

### Step 2 — Ask user for board access method

Ask: "Is the board accessible via SSH or serial console?"
- SSH → ask for IP address or hostname
- Serial → ask for serial device path (e.g., `/dev/ttyUSB0`)
- Neither → run static checks only and provide manual checklist

### Step 3 — Run dynamic checks via SSH

```bash
bash skills/imx95-validate-image/scripts/validate.sh --ssh-host <ip> [--ssh-user root]
```

### Step 4 — Present structured pass/fail report

Display the complete validation report. Highlight any failures with corrective actions.

### Step 5 — Recommend next action

- All pass → "Board is validated. Ready for application development."
- Some fail → identify root cause and suggest corrective skill or action

## Validation Checklist

### Static Checks (host-side, no board connection)

- [ ] `staging/latest/manifest.txt` checksums match staged artifacts
- [ ] `fdtdump <machine>.dtb` shows expected model string
- [ ] No `ERROR` lines in last bitbake build log (`build/tmp/log/`)
- [ ] overlay-tracker last commit matches expected customizations

### Dynamic Checks (requires board SSH or serial)

- [ ] U-Boot boots without errors
- [ ] Kernel boots to login prompt
- [ ] `uname -r` shows expected kernel version (6.6.x)
- [ ] `cat /proc/device-tree/model` shows expected board model string
- [ ] `dmesg | grep -c " error"` — zero critical errors
- [ ] `dmesg | grep iomuxc` — IOMUX initialized without errors
- [ ] Customized peripherals appear in dmesg (UART, USB, PCIe, camera, etc.)
- [ ] `lsusb` shows expected USB devices (if USB customized)
- [ ] NPU driver loaded: `lsmod | grep neutron` (if NPU used)
- [ ] VPU driver loaded: `lsmod | grep vpu` (if VPU used)
- [ ] Camera device present: `ls /dev/video*` (if camera added)
- [ ] Filesystem writable: `touch /tmp/test && rm /tmp/test`

## Files Touched

None — read-only validation.

## Safety Rules Applied

None — this skill is purely informational and read-only.

## References

- `context/bsp-customization-workflow.md` — workflow context
- `references/bsp-platforms-catalogue.md` — board serial console details
