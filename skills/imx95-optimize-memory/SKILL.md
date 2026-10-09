---
name: imx95-optimize-memory
version: "1.0"
platform: imx95
phase: customize
invoke_when:
  - "tune CMA"
  - "resize DMA buffer"
  - "memory pool"
  - "CMA allocation failure"
  - "DMA-BUF heap"
  - "reserved memory"
  - "VPU memory"
  - "NPU memory"
  - "memory reservation"
requires_host_tools:
  - dtc
  - git
safe: true
destructive: false
commit_gate: true
---

# imx95-optimize-memory

## Purpose

Tune CMA (Contiguous Memory Allocator) size, DMA-BUF heap pool sizes, and
`reserved-memory` regions in the device tree and kernel bootargs.

⚠️ **It does NOT provide recommended sizes.** The previous version did, and every number in that
table was invented. Sizing is driven by the failure the user actually observed and by reading the
board's real `reserved-memory` node — not by a lookup table nobody measured.

## When to Invoke

- User reports CMA allocation failures in dmesg: `cma: alloc failed`
- Running memory-intensive workloads (video encode/decode, ML inference, multi-camera)
- Reducing memory footprint for a constrained application
- User says "tune CMA", "resize DMA buffer", "memory pool"

## Pre-conditions

1. `targets/active_target.yaml` exists.
2. Carrier overlay file exists.
3. `overlay-tracker/` is initialized and clean.
4. User knows total RAM on the board (FRDM-IMX95-PRO: 16 GB LPDDR [SOURCED] — the earlier "8 GB LPDDR5" here was unverified).

> # 🔴 THE NEUTRON DTB — the single most consequential reserved-memory fact on this board
>
> This board boots **`imx95-19x19-frdm-pro-neutron.dtb`**, which adds a dedicated **4 GiB
> `neutron_memory` `shared-dma-pool`**. Measured effect: `CmaTotal` **960 MiB → 4.94 GiB**
> [MEASURED, `references/imx95-ground-truth.md` §2.3].
>
> - **Without it the ONNX Runtime Neutron EP cannot initialise at all.** It requests a flat 2 GiB
>   contiguous buffer, gets ENOMEM against the stock 960 MiB pool, logs at a severity nobody
>   reads, and **silently runs the entire graph on the six A55 cores at a plausible latency.**
>   *That single failure is why the Neutron was believed "CNN-only" for months.*
> - It is a **strict improvement**: `linux,cma` stays 960 MiB and memory bandwidth re-measured
>   **16.0 GB/s identical** before and after.
> - 🔴 **Never propose reverting to the stock DTB.** It silently breaks the board into the
>   CNN-only-looking state — no error, just a slower plausible number.

## SAFETY RULE

**Do not shrink `linux,cma` or remove `neutron_memory` without understanding which accelerator
path draws from which pool.** The TFLite Neutron delegate path draws from `linux,cma`; the ORT
Neutron EP uses the dedicated pool.

## i.MX 95 memory layout — MEASURED on this board

| Region | Size | Tag |
|---|--:|:--|
| `linux,cma` | **960 MiB** | [MEASURED] |
| `neutron_memory` (`shared-dma-pool`) | **4 GiB** | [MEASURED] |
| **`CmaTotal`** | **4.94 GiB** | [MEASURED] |
| Total RAM | 16 GB LPDDR | [SOURCED] |

> ⚠️ **Everything the first version of this skill said about memory was invented**, and it is worth
> listing precisely because each number was plausible:
> - `linux,cma: 512 MB` — measured value is **960 MiB**
> - *"Never reduce CMA below 320 MB"* — a floor nobody established
> - a "Recommended CMA Values by Use Case" table (512/768/128/640 MB…) — **entirely fabricated**
> - RAM stated as **8 GB** — the dossier says **16 GB** [SOURCED]
> - `vpu_fw 64 MB` / `imx-dma-heap 256 MB` / `npu_fw 32 MB` — **[UNVERIFIED]**, retained nowhere
> - and **`neutron_memory` was not mentioned at all** — the one region that decides whether the
>   board's LLM path works
>
> **There is no replacement recommendation table**, deliberately. Sizing guidance that nobody
> measured is what produced the last one. Ask the user what failed, read the actual
> `reserved-memory` node, and change one thing at a time.

## Questions to Ask User

1. **What is the use case?** (camera, NPU, VPU, general, minimal)
2. **What failure are you seeing?** (CMA alloc failed, VPU error, ISI error, OOM)
3. **Total RAM on board?** (FRDM-IMX95-PRO: 16 GB LPDDR [SOURCED])
4. **Image recipe?** (`imx-image-full`, `imx-image-multimedia`, `core-image-base`)

## Procedure

### Step 1 — Read active target

Extract `paths.dt_overlay_dir` and `yocto.image_recipe` from `targets/active_target.yaml`.

### Step 2 — Read the board's ACTUAL reserved-memory layout

Do not size from a table. Read what is really there, then change one region at a time:

```bash
# on the board
grep -iE 'CmaTotal|CmaFree' /proc/meminfo
ls /sys/kernel/debug/cma/ 2>/dev/null          # per-region, needs CONFIG_CMA_DEBUGFS
fdtget -l /sys/firmware/fdt /reserved-memory 2>/dev/null || \
  dtc -I fs -O dts /sys/firmware/devicetree/base 2>/dev/null | sed -n '/reserved-memory/,/};/p'
```

⚠️ **If `CmaTotal` is ~4.94 GiB, the neutron DTB is booted — do not "normalise" it back.**

### Step 3 — Generate memory overlay

Construct the `reserved-memory` DT overlay snippet.

### STOP — Show generated snippet to user

Display the complete DT snippet with the proposed memory layout.
State: "Here is the proposed memory configuration. Please review and reply 'approve'
to proceed, or tell me what to change."

Wait for explicit approval.

### Step 4 — Apply to overlay file

Write the memory overlay to `imx95-<carrier-name>-memory.dts`.

### Step 5 — Validate with dtc

```bash
dtc -@ -I dts -O dtb -o /dev/null <memory-overlay-file>
```

### Step 6 — Commit to overlay-tracker (commit-gate)

Show `git diff --staged`, wait for approval, then commit.

Commit message:
```
customize(memory): tune CMA to <size>MB, DMA-BUF heap to <size>MB

Board: <profile_name>
Skill: imx95-optimize-memory
Files: imx95-<name>-memory.dts

Use case: <description>
CMA: <old> → <new> MB
DMA-BUF heap: <old> → <new> MB

Tested: pending
```

## DT Snippet Examples

### Increase CMA to 768 MB (camera-heavy)

```dts
// SPDX-License-Identifier: GPL-2.0+
/*
 * Memory reservation overlay for i.MX 95
 * Use case: camera-heavy (4K multi-camera)
 * CMA: 768 MB, DMA-BUF heap: 512 MB
 */

/dts-v1/;
/plugin/;

/ {
    reserved-memory {
        #address-cells = <2>;
        #size-cells = <2>;
        ranges;

        /* CMA pool — 768 MB for camera-heavy workloads */
        linux,cma {
            compatible = "shared-dma-pool";
            reusable;
            size = <0 0x30000000>;   /* 768 MB */
            alloc-ranges = <0 0x80000000 0 0xFFFFFFFF>;
            linux,cma-default;
        };

        /* DMA-BUF heap — 512 MB */
        imx_dma_heap: imx-dma-heap {
            compatible = "imx-dma-heap";
            no-map;
            size = <0 0x20000000>;   /* 512 MB */
        };
    };
};
```

### Reduce CMA to 128 MB (minimal image, no VPU/NPU)

```dts
/dts-v1/;
/plugin/;

/ {
    reserved-memory {
        #address-cells = <2>;
        #size-cells = <2>;
        ranges;

        /* CMA pool — 128 MB for minimal image */
        linux,cma {
            compatible = "shared-dma-pool";
            reusable;
            size = <0 0x08000000>;   /* 128 MB */
            alloc-ranges = <0 0x80000000 0 0xFFFFFFFF>;
            linux,cma-default;
        };
    };
};
```

### Add NPU firmware carveout (32 MB)

```dts
/dts-v1/;
/plugin/;

/ {
    reserved-memory {
        #address-cells = <2>;
        #size-cells = <2>;
        ranges;

        /* NPU firmware carveout — 32 MB */
        npu_fw: npu-fw@A0000000 {
            compatible = "shared-dma-pool";
            no-map;
            reg = <0 0xA0000000 0 0x02000000>;   /* 32 MB at 2.5 GB */
        };
    };
};
```

## Bootargs Alternative

CMA can also be set via kernel bootargs (U-Boot environment):
```
setenv bootargs "${bootargs} cma=768M"
saveenv
```

This overrides the DT `linux,cma` size. The DT approach is preferred for reproducibility.

## Files Touched

- `sources/meta-imx95-custom/recipes-kernel/linux/files/overlays/imx95-<name>-memory.dts`
- `overlay-tracker/` (committed)
- Optionally: `build/conf/local.conf` (if modifying `APPEND_BOOTARGS`)

## Safety Rules Applied

- **R2** — Only meta-imx95-custom overlays modified
- **R3** — DT changes committed before building
- **R4** — Commit-gate on every commit
- **R5** — Do not shrink `linux,cma` or remove `neutron_memory` without establishing which
  accelerator path draws from which pool. (The previous "never below 320 MB" floor was invented.)

## References

- `references/bsp-customization-kernel-dtb.md` — overlay structure
- `context/bsp-customization-workflow.md` — workflow context
