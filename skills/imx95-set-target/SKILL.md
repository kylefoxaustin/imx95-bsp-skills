---
name: imx95-set-target
version: "0.1.0"
platform: imx95-bsp
phase: setup
invoke_when:
  - "switch to target"
  - "change active board"
  - "set active target"
  - "use a different board profile"
  - "switch board"
requires_host_tools:
  - git
  - python3
safe: true
destructive: false
commit_gate: false
---

# imx95-set-target

## Purpose

Switch the active target to an existing profile in `targets/`. Lists all available target
profiles in the workspace, lets the user select one, and updates `targets/active_target.yaml`.

## When to Invoke

- User says "switch to target X", "change active board", "use a different board profile"
- User has multiple target profiles and wants to switch between them

## Pre-conditions

- Workspace exists with `targets/` directory
- At least one `targets/*.yaml` profile file exists (other than `active_target.yaml`)

## Procedure

### Step 1 — Read Active Target

Read `targets/active_target.yaml` to know the current active target:

```bash
WORKSPACE=$(python3 -c "
import yaml, os
with open('targets/active_target.yaml') as f:
    t = yaml.safe_load(f)
print(os.path.expanduser(t['paths']['workspace_root']))
")
```

Display current state:
```
Current active target: frdm-imx95-base
  Board   : FRDM-IMX95
  MACHINE : imx95-19x19-lpddr5-evk
  Image   : imx-image-full
```

### Step 2 — List Available Profiles

List all `*.yaml` files in `targets/` except `active_target.yaml`:

```bash
ls <workspace>/targets/*.yaml | grep -v active_target.yaml
```

Display as a numbered list:
```
Available target profiles:
  1. frdm-imx95-base        (FRDM-IMX95, eMMC, imx-image-full)     [ACTIVE]
  2. frdm-imx95-sd          (FRDM-IMX95, SD, core-image-base)
  3. acme-carrier-v1        (ACME Carrier, eMMC, imx-image-multimedia)

Enter the number of the profile to activate, or 'cancel':
```

Parse each YAML to show the summary line (profile_name, board.name, boot_device, image_recipe).

### Step 3 — Wait for User Selection

Wait for the user to enter a number or profile name.

If user enters "cancel" or "0", abort with:
```
Cancelled. Active target unchanged: frdm-imx95-base
```

### Step 4 — STOP: Confirm Switch

Show what will change:
```
Switch active target:
  FROM: frdm-imx95-base  (FRDM-IMX95, eMMC, imx-image-full)
  TO:   acme-carrier-v1  (ACME Carrier, eMMC, imx-image-multimedia)

This will update targets/active_target.yaml.
Reply "confirm" to proceed, or "cancel" to abort.
```

**WAIT** for explicit confirmation before updating the file.

### Step 5 — Update active_target.yaml

```bash
# Copy the selected profile to active_target.yaml
cp <workspace>/targets/<selected_profile>.yaml <workspace>/targets/active_target.yaml

# Or use a symlink:
cd <workspace>/targets
ln -sf <selected_profile>.yaml active_target.yaml
```

### Step 6 — Confirm and Warn

Report success:
```
✓ Active target switched to: acme-carrier-v1
  Board   : ACME Carrier
  MACHINE : imx95-19x19-lpddr5-evk
  Image   : imx-image-multimedia
  Boot    : eMMC

⚠️  Remember: build/conf/local.conf may still have the old MACHINE value.
   Run imx95-init-source to re-source the environment with the new MACHINE.
```

### Step 7 — Check for MACHINE Mismatch

Read `build/conf/local.conf` (if it exists) and check if `MACHINE` matches the new target:

```bash
grep '^MACHINE' <workspace>/build/conf/local.conf 2>/dev/null || echo "not set"
```

If there is a mismatch:
```
⚠️  MACHINE mismatch detected:
   local.conf MACHINE : imx95-19x19-lpddr5-evk
   New target MACHINE : imx95-15x15-evk

   Run imx95-init-source to update local.conf before building.
```

## Files Touched

- `targets/active_target.yaml` — updated (copy or symlink to selected profile)

## Safety Rules Applied

- STOP checkpoint: confirm switch before updating active_target.yaml
- Warn about MACHINE mismatch in local.conf
- Never delete or overwrite named profile YAMLs

## References

- `context/target-platform-contract.md` — target profile schema
- `references/bsp-platforms-catalogue.md` — valid MACHINE names
- `scripts/set_target.sh` — shell script implementation
