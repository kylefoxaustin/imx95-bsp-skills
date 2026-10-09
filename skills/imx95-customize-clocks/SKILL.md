---
name: imx95-customize-clocks
version: "2.0"
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

> # ⚖️ READ FIRST — the contract on this SoC is **SET AND READ BACK**, not "set"
>
> **Resolved 2026-09-12 on the real board** (`references/imx95-ground-truth.md` §6.1, measured by
> `@95emulator` and independently reproduced). An earlier version of this banner told the skill to
> **refuse**, because it was unknown whether DT clock properties had any authority on the i.MX95.
> They do — but not the authority a conventional CCM skill assumes:
>
> - The shipped DT uses them heavily: `assigned-clocks` on **26** nodes, `assigned-clock-rates` on
>   **23**, `assigned-clock-parents` on **26**.
> - **24 of those 26** reference **`scmi_clk`** (`/firmware/scmi/protocol@14`, phandle `0x11`) —
>   **not a CCM**. 2 reference some other provider; check which before assuming SCMI.
> - So: **the overlay EXPRESSES the request → SCMI CARRIES it → the Cortex-M33 System Manager
>   DECIDES**, and it may deny per its per-logical-machine permissions.
>
> ### This skill therefore:
> 1. **Generates the overlay.** DT is the legitimate lever; refusing would be wrong.
> 2. **Identifies the provider** of the clock being changed — `scmi_clk` or not — from the base DT,
>    and says which.
> 3. **Never says "this sets the clock to X."** For an SCMI clock it says: *"this requests X; the
>    System Manager decides whether to grant it."*
> 4. **Adds a mandatory read-back step to validation:** after boot, report **requested vs
>    effective** rate (`/sys/kernel/debug/clk/clk_summary`, or the consumer driver). A mismatch is a
>    **denial, not a bug in the overlay** — say so, rather than debugging the hardware.
>
> 🔧 **Counting DT properties on the board:** use `/sys/firmware/devicetree/base`. `find` returns
> **0** under `/proc/device-tree` on this rootfs while `cat` on the same paths works — a zero from
> that instrument is indistinguishable from an absent property. Validate any counter against a
> property you already know is present.
>
> **Related — regulators are the OPPOSITE case (§6.2):** SCMI voltage protocol `0x17` is **not
> exposed**; the board rails (`+V1.8_SW`, `USB_VBUS`, `VDD_SD2_3V3`, `M.2-power-ekey`, …) are plain
> Linux `regulator-fixed`/`regulator-gpio` nodes with **ordinary DT authority, no SM in the path.**
> `imx95-customize-power` does not exist on disk. v1's description of it was wrong about the **part
> and the target** (PCA9450 PMIC regulators — the PMIC here is PF09 and invisible to Linux), **not**
> about DT regulator editing as a mechanism. If it is built, it edits **board fixed/GPIO supplies**.

## Purpose

Modify clock assignments in the device tree overlay. Handles `assigned-clocks`,
`assigned-clock-parents`, `assigned-clock-rates` patterns, enabling CLKO1/CLKO2 clock
output pads, and overriding peripheral clock frequencies.

⚠️ **Subject to the contract above** — the DT mechanics below are accurate Linux bindings. For an
`scmi_clk` consumer they are a *request*, and the validation step must read the effective rate back.

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

## i.MX 95 Clock Model — what the board actually shows

> ⚠️ **An earlier version of this section described a Linux-owned CCM** —
> `clk: clock-controller@44450000 { compatible = "nxp,imx95-ccm"; }` referenced as
> `<&clk IMX95_CLK_*>`, with a table of clock IDs and three ready-to-paste examples. **None of that
> was taken from this board, and it contradicts what the board shows.** It is deleted, not
> corrected: once this skill *generates* overlays (see the banner), invented phandles and IDs stop
> being harmless prose and become DTBs that build, flash, and silently request the wrong clock.

**Measured on the running FRDM-IMX95-PRO** (`references/imx95-ground-truth.md` §6.1):

| fact | value | tag |
|---|---|---|
| Clock provider for most consumers | **`scmi_clk`** — `/firmware/scmi/protocol@14`, phandle `0x11` | [MEASURED ×2] |
| Consumers referencing it first | **24 of 26** `assigned-clocks` nodes | [MEASURED ×2] |
| Example (a `pcie-ep` consumer) | `<&scmi_clk 0x23>, <&scmi_clk 0x24>` | [MEASURED] |
| The 2 non-SCMI consumers | provider **[UNKNOWN]** — not yet identified | — |
| SCMI clock **ID → name** mapping | **[UNKNOWN]** — nobody has established it | — |
| CLKO1/CLKO2 pad support, `IMX95_CLK_*` macro names | **[UNKNOWN]** on this board | — |

### The pattern — with the IDs READ, never guessed

```dts
&<peripheral> {
    /* ID taken from THIS board's base DT or the BSP's own clock binding header —
       never from memory, never from another i.MX part's header */
    assigned-clocks      = <&scmi_clk <ID>>;
    assigned-clock-rates = <FREQ_HZ>;   /* a REQUEST — the System Manager decides */
};
```

### Step 0 — establish the provider and ID before writing anything

```bash
# On the board. Use /sys/firmware/devicetree/base — `find` returns 0 under /proc/device-tree here.
# python3 is confirmed present on the board; busybox/coreutils `od` flags are not, so don't rely on them.
# Resolves each provider's #clock-cells rather than assuming 1, and classifies the provider three ways.
python3 - <<'EOF'
import os, struct
B    = "/sys/firmware/devicetree/base"
NODE = "soc/<peripheral-node>"          # <- fill in
rd    = lambda p: open(p, "rb").read() if os.path.exists(p) else None
cells = lambda b: [struct.unpack(">I", b[i:i+4])[0] for i in range(0, len(b) - len(b) % 4, 4)]
ph2node = {}
for r, _, f in os.walk(B):
    if "phandle" in f:
        ph2node[cells(rd(r + "/phandle"))[0]] = r
scmi = cells(rd(B + "/firmware/scmi/protocol@14/phandle"))[0]
DIRECT = {b"nxp,imx95-vpu-csr"}          # local providers with direct authority [MEASURED]
def klass(ph):
    if ph == scmi: return "SCMI    -> request; SM decides; mismatch = SM DENIAL"
    comp = set((rd(ph2node[ph] + "/compatible") or b"").split(b"\0"))
    if comp & DIRECT: return "LOCAL   -> direct authority; mismatch = REAL BUG"
    return "UNKNOWN -> refuse until identified"
v = rd(f"{B}/{NODE}/assigned-clocks")
if not os.path.isdir(f"{B}/{NODE}"):
    # A missing NODE must not read like "a real node with no clocks" — that is a false absence.
    raise SystemExit(f"NODE NOT FOUND: {NODE} — check the path; nothing was classified")
elif v is None:
    print("node exists; no assigned-clocks on it today")
else:
    c, i = cells(v), 0
    while i < len(c):
        ph = c[i]; n = ph2node.get(ph)
        k = cells(rd(n + "/#clock-cells"))[0] if n and rd(n + "/#clock-cells") else None
        if k is None:
            print(f"provider {hex(ph)}: #clock-cells unresolved -> UNKNOWN, refuse"); break
        print(f"provider {hex(ph)} {os.path.relpath(n, B)}  ids {[hex(x) for x in c[i+1:i+1+k]]}  {klass(ph)}")
        i += 1 + k
EOF
# ✅ Executed verbatim on the FRDM-IMX95-PRO 2026-09-12 [MEASURED]:
#   soc/pcie-ep@4c300000 -> 0x11 scmi_clk ids 0x23, 0x24, 0x58   -> SCMI  (mismatch = SM denial)
#   soc/jpegdec@4c500000 -> 0x89 clock-controller@4c410000 id 0x2 -> LOCAL (mismatch = real bug)
#   a mistyped path      -> NODE NOT FOUND (an earlier revision printed "no assigned-clocks",
#                           a false absence — caught by running this, fixed, re-run below)
# the effective rate NOW, so the read-back after the change has a baseline
grep -i "<clock-name>" /sys/kernel/debug/clk/clk_summary 2>/dev/null
```

**The provider decides what a read-back mismatch MEANS — classify three ways, never two:**

| provider | consumers on this board | authority | read-back mismatch means |
|---|---|---|---|
| **`scmi_clk`** (`protocol@14`, ph `0x11`) | 24 | **request** — the System Manager decides | **SM denial** — report as such, not as a bug |
| **`nxp,imx95-vpu-csr`** (`clock-controller@4c410000`, ph `0x89`) | 2 — `jpegdec@4c500000`, `jpegenc@4c550000` | **direct**, like a regulator — no SM in the path | **a REAL BUG** — do not call it a denial |
| anything else | — | unknown | **refuse** until the provider is identified |

> ⚠️ **Why three and not two:** an earlier revision said "check whether it's SCMI". A two-way test
> puts the JPEG codec clocks in the "not SCMI" bucket with no stated semantics — and the natural
> default ("mismatch = the SM said no") would **explain away a real bug on a clock the SM never
> touches.** (Provider identified by `@95emulator`, reproduced by this repo.)

- If the peripheral **already** references a provider, reuse **that provider and ID** — change the
  rate only.
- **Never reuse `IMX95_CLK_*` names or IDs from another provider or another i.MX part.**
- If the node has **no** clock assignment today and the user cannot supply the ID from the BSP's
  binding header, **stop and say exactly what is missing** — an ID is not a thing to infer.

## Questions to Ask User

1. **Which peripheral?** (the DT node, not just "UART")
2. **Target frequency?** (Hz)
3. **Where does the clock ID come from?** (this board's base DT, or the BSP binding header — ask for
   the file)
4. **Why is the default insufficient?** — and state up front that on an `scmi_clk` consumer the
   System Manager may refuse the rate.

## Procedure

### Step 1 — Read the active target and existing overlay

### Step 2 — Run Step 0 above; record provider, ID and current effective rate

### Step 3 — Generate the snippet using the READ provider and ID

### STOP — Show the snippet, and say plainly:
*"This requests `<FREQ>` Hz from `<provider>`. For an SCMI clock the System Manager decides whether
to grant it; the effective rate will be read back after boot."* Wait for explicit approval.

### Step 4 — Apply to the overlay file

### Step 5 — Validate with dtc

```bash
dtc -@ -I dts -O dtb -o /dev/null <overlay-file>
```
A clean `dtc` proves the overlay **parses**. It proves nothing about whether the rate is granted.

### Step 6 — Commit to overlay-tracker (commit-gate)

Show `git diff --staged`, wait for approval, then commit:
```
customize(clocks): request <FREQ> Hz for <peripheral> via <provider>

Board: <profile_name>
Skill: imx95-customize-clocks
Files: <overlay-file>

Provider: <scmi_clk | other>, ID <id> (source: <base DT | header path>)
Baseline effective rate: <Hz>

Tested: pending — effective rate NOT yet read back
```

### Step 7 — ⭐ READ BACK after flash (mandatory — hand to `imx95-validate-image`)

Report **requested vs effective**, and interpret a mismatch **by provider class** (Step 0):
- **`scmi_clk`** → the **System Manager denied** the request under its per-logical-machine
  permissions. Report it as a denial — **not** an overlay bug, **not** a hardware fault.
- **`nxp,imx95-vpu-csr`** (local, direct) → **a real bug.** Nothing sits between the overlay and the
  clock; do **not** reach for "denial" — it would hide the defect.
- **unknown provider** → you should not have generated this overlay; stop.

Update the commit's `Tested:` line only after this step.

## Files Touched

- `sources/meta-imx95-custom/recipes-kernel/linux/files/overlays/imx95-<name>.dts`
- `overlay-tracker/` (committed)

## Safety Rules Applied

- **R2** — Only meta-imx95-custom overlays modified
- **R3** — DT changes committed before building
- **R4** — Commit-gate on every commit
- **R5** — Never assume hardware details: provider and clock ID are READ from this board, never
  carried over from another i.MX part's header
- **R11** — Never present an SCMI clock request as effective until the rate has been read back

## References

- `references/bsp-customization-iomux-dt.md` — CLKO pad configuration
- `references/bsp-customization-kernel-dtb.md` — overlay structure
- `context/bsp-customization-workflow.md` — workflow context
