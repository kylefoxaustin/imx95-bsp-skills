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
`reserved-memory` regions in the device tree and kernel bootargs. Provides recommended
values for camera-heavy, NPU-heavy, and general-purpose use cases.

## When to Invoke

- User reports CMA allocation failures in dmesg: `cma: alloc failed`
- Running memory-intensive workloads (video encode/decode, ML inference, multi-camera)
- Reducing memory footprint for a constrained application
- User says "tune CMA", "resize DMA buffer", "memory pool"

## Pre-conditions

1. `targets/active_target.yaml` exists.
2. Carrier overlay file exists.
3. `overlay-tracker/` is initialized and clean.
4. User knows total RAM on the board (FRDM-IMX95: 8 GB LPDDR5).

## SAFETY RULE

**Never reduce CMA below 320 MB for `imx-image-full` with VPU enabled.**
Reducing CMA too aggressively will cause VPU/ISI/NPU failures at runtime.

## i.MX 95 Memory Layout (8 GB LPDDR5, default)

```
Physical RAM: 0x80000000 – 0x27FFFFFFF (8 GB)

Reserved regions (default BSP):
  ATF/OPTEE carveout : ~16 MB  (top of RAM)
  VPU firmware       : 64 MB   (vpu_fw)
  imx-dma-heap       : 256 MB  (DMA-BUF heap for multimedia)
  linux,cma          : 512 MB  (CMA pool — default imx-image-full)
  NPU firmware       : 32 MB   (npu_fw)
```

## Recommended CMA Values by Use Case

| Use Case | CMA Size | DMA-BUF Heap | Notes |
|---|---|---|---|
| General purpose | 512 MB | 256 MB | Default BSP values |
| Camera-heavy (4K, multi-cam) | 768 MB | 512 MB | Increase for ISI/ISP buffers |
| NPU-heavy (ML inference) | 512 MB | 256 MB | Increase NPU carveout instead |
| Minimal (core-image-base) | 128 MB | 64 MB | No VPU/NPU — safe to reduce |
| Video encode/decode (VPU) | 640 MB | 384 MB | VPU needs large contiguous bufs |

**Minimum safe values for imx-image-full:** CMA ≥ 320 MB, DMA-BUF heap ≥ 128 MB

## Questions to Ask User

1. **What is the use case?** (camera, NPU, VPU, general, minimal)
2. **What failure are you seeing?** (CMA alloc failed, VPU error, ISI error, OOM)
3. **Total RAM on board?** (FRDM-IMX95: 8 GB)
4. **Image recipe?** (`imx-image-full`, `imx-image-multimedia`, `core-image-base`)

## Procedure

### Step 1 — Read active target

Extract `paths.dt_overlay_dir` and `yocto.image_recipe` from `targets/active_target.yaml`.

### Step 2 — Determine recommended values

Based on use case, recommend CMA and DMA-BUF heap sizes from the table above.

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
- **R5** — Never reduce CMA below 320 MB for imx-image-full with VPU

## References

- `references/bsp-customization-kernel-dtb.md` — overlay structure
- `context/bsp-customization-workflow.md` — workflow context
