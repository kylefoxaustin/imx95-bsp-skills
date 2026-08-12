# BSP Customization Software Layers — i.MX 95 Yocto BSP

> **Shared context document.** Explains the Yocto layer stack for i.MX 95 and the rules
> for customization. All skills read this before modifying any BSP files.

---

## Overview

The NXP i.MX 95 Yocto BSP is built from a stack of Yocto layers. Understanding this stack
is essential for making correct, maintainable customizations. The golden rule is:

> **Never modify upstream layers directly. Always customize through `meta-imx95-custom`.**

---

## The i.MX 95 Yocto Layer Stack

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        LAYER STACK (highest priority at top)                │
├─────────────────────────────────────────────────────────────────────────────┤
│  meta-imx95-custom          ← YOUR LAYER — all customizations go here       │
│  (sources/meta-imx95-custom/)                                               │
│  Priority: 10 (highest)                                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│  meta-imx                   ← NXP i.MX Yocto layer                         │
│  (sources/meta-imx/)                                                        │
│  Priority: 8                                                                │
│  READ-ONLY — never modify directly                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│  meta-freescale             ← Freescale/NXP community layer                 │
│  (sources/meta-freescale/)                                                  │
│  Priority: 7                                                                │
│  READ-ONLY — never modify directly                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│  meta-freescale-3rdparty    ← Third-party BSP support                       │
│  (sources/meta-freescale-3rdparty/)                                         │
│  Priority: 6                                                                │
│  READ-ONLY — never modify directly                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│  meta-openembedded layers   ← OE community layers (meta-oe, meta-python...) │
│  (sources/meta-openembedded/)                                               │
│  Priority: 5                                                                │
│  READ-ONLY — never modify directly                                          │
├─────────────────────────────────────────────────────────────────────────────┤
│  poky (meta + meta-poky)    ← Yocto Project Poky base                      │
│  (sources/poky/)                                                            │
│  Priority: 1 (lowest)                                                       │
│  READ-ONLY — never modify directly                                          │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Layer Responsibilities

| Layer | Provides | Managed by |
|---|---|---|
| `meta-imx95-custom` | Your bbappend recipes, DT overlays, custom image recipes | You (via skills) |
| `meta-imx` | i.MX-specific recipes: linux-imx, u-boot-imx, imx-gpu-viv, imx-vpu-hantro | NXP (via repo) |
| `meta-freescale` | Freescale/NXP machine configs, BSP recipes | NXP community (via repo) |
| `meta-freescale-3rdparty` | Third-party board support | NXP community (via repo) |
| `meta-openembedded` | Extended package set (Python, networking, etc.) | OE community (via repo) |
| `poky` | Core Yocto build system, base recipes, classes | Yocto Project (via repo) |

---

## The `meta-imx95-custom` Layer

This is the only layer you ever modify. It is created by `imx95-init-source` if it does not
already exist.

### Directory Structure

```
sources/meta-imx95-custom/
├── conf/
│   └── layer.conf                    ← Layer configuration (BBPATH, BBFILES, priority)
├── recipes-kernel/
│   └── linux/
│       ├── linux-imx_%.bbappend      ← Kernel recipe extension (adds DT overlays, patches)
│       └── files/
│           └── overlays/
│               ├── imx95-custom.dts          ← Main carrier overlay
│               ├── imx95-custom-pinmux.dts   ← Pinmux sub-overlay
│               ├── imx95-custom-camera.dts   ← Camera overlay (if applicable)
│               └── imx95-custom-memory.dts   ← Memory overlay (if applicable)
├── recipes-bsp/
│   └── u-boot/
│       └── u-boot-imx_%.bbappend     ← U-Boot recipe extension (env, patches)
├── recipes-core/
│   └── images/
│       └── my-custom-image.bb        ← Custom image recipe (if needed)
└── README                            ← Layer description
```

### `conf/layer.conf` Template

```bitbake
# We have a conf and classes directory, add to BBPATH
BBPATH .= ":${LAYERDIR}"

# We have recipes-* directories, add to BBFILES
BBFILES += "${LAYERDIR}/recipes-*/*/*.bb \
            ${LAYERDIR}/recipes-*/*/*.bbappend"

BBFILE_COLLECTIONS += "imx95-custom"
BBFILE_PATTERN_imx95-custom = "^${LAYERDIR}/"
BBFILE_PRIORITY_imx95-custom = "10"

LAYERDEPENDS_imx95-custom = "core freescale-layer fsl-bsp-release"
LAYERSERIES_COMPAT_imx95-custom = "scarthgap"
```

---

## The bbappend Mechanism

A `.bbappend` file extends an existing recipe without modifying the original. The `%` wildcard
in the filename matches any version of the recipe.

### How bbappend Works

```
sources/meta-imx/recipes-kernel/linux/linux-imx_6.6.bb   ← original recipe (READ-ONLY)
sources/meta-imx95-custom/recipes-kernel/linux/linux-imx_%.bbappend  ← your extension
```

Bitbake automatically merges the bbappend into the original recipe at parse time. The bbappend
can add `SRC_URI` entries, override variables, and add tasks.

### Example: Adding DT Overlays via bbappend

```bitbake
# sources/meta-imx95-custom/recipes-kernel/linux/linux-imx_%.bbappend

# Add overlay source files to the kernel recipe
FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += " \
    file://overlays/imx95-custom.dts \
    file://overlays/imx95-custom-pinmux.dts \
"

# Copy overlays into the kernel source tree before compilation
do_configure:append() {
    cp ${WORKDIR}/overlays/imx95-custom.dts \
       ${S}/arch/arm64/boot/dts/freescale/
    cp ${WORKDIR}/overlays/imx95-custom-pinmux.dts \
       ${S}/arch/arm64/boot/dts/freescale/
}

# Add the overlay DTB to the list of DTBs to build
KERNEL_DEVICETREE:append = " freescale/imx95-custom.dtb"
```

### Example: Adding a Kernel Config Fragment via bbappend

```bitbake
# sources/meta-imx95-custom/recipes-kernel/linux/linux-imx_%.bbappend

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://enable-can.cfg"

# enable-can.cfg contains:
# CONFIG_CAN=y
# CONFIG_CAN_FLEXCAN=y
```

### Example: Overriding a U-Boot Environment Variable via bbappend

```bitbake
# sources/meta-imx95-custom/recipes-bsp/u-boot/u-boot-imx_%.bbappend

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI += "file://0001-uboot-env-overlay.patch"
```

---

## Creating `meta-imx95-custom` from Scratch

`imx95-init-source` creates this layer automatically. If you need to create it manually:

```bash
# From workspace root, with Yocto environment sourced:
cd <workspace_root>

# Create the layer directory structure
bitbake-layers create-layer sources/meta-imx95-custom

# Add the layer to bblayers.conf
bitbake-layers add-layer sources/meta-imx95-custom

# Verify
bitbake-layers show-layers
```

The `bitbake-layers create-layer` command creates:
- `conf/layer.conf` with correct BBPATH and BBFILES settings
- `recipes-example/` with a placeholder recipe (can be deleted)
- `README` with layer description

After creation, update `conf/layer.conf`:
- Set `BBFILE_PRIORITY_imx95-custom = "10"` (higher than meta-imx priority of 8)
- Set `LAYERSERIES_COMPAT_imx95-custom = "scarthgap"`
- Add `LAYERDEPENDS_imx95-custom = "core freescale-layer fsl-bsp-release"`

---

## Rules for Customization

### Rule 1: Never Modify Upstream Layers

```
WRONG:  edit sources/meta-imx/recipes-kernel/linux/linux-imx_6.6.bb
WRONG:  edit sources/meta-freescale/conf/machine/imx95-19x19-lpddr5-evk.conf
WRONG:  edit sources/poky/meta/recipes-core/images/core-image-base.bb
WRONG:  edit sources/linux-imx/arch/arm64/boot/dts/freescale/imx95-19x19-lpddr5-evk.dts

CORRECT: create sources/meta-imx95-custom/recipes-kernel/linux/linux-imx_%.bbappend
CORRECT: create sources/meta-imx95-custom/conf/machine/imx95-custom.conf (new machine)
CORRECT: create sources/meta-imx95-custom/recipes-core/images/my-image.bb (new image)
CORRECT: create sources/meta-imx95-custom/recipes-kernel/linux/files/overlays/imx95-custom.dts
```

### Rule 2: Use DT Overlays, Not In-Tree DTS Edits

```
WRONG:  edit sources/linux-imx/arch/arm64/boot/dts/freescale/imx95-19x19-lpddr5-evk.dts
        (this change will be lost on repo sync)

CORRECT: create sources/meta-imx95-custom/recipes-kernel/linux/files/overlays/imx95-custom.dts
         and register it in linux-imx_%.bbappend
```

### Rule 3: Use `devtool` for Temporary In-Tree Development

If you need to temporarily edit kernel source (e.g., for driver development), use `devtool`:

```bash
# Create a devtool workspace for linux-imx
devtool modify linux-imx

# This creates a separate workspace at <build>/workspace/sources/linux-imx/
# with a git repo you can commit to. Changes are tracked as patches.

# When done, extract the patches back to meta-imx95-custom:
devtool finish linux-imx sources/meta-imx95-custom
```

### Rule 4: Layer Priority Determines Override Order

When two layers define the same recipe or bbappend, the higher-priority layer wins.
`meta-imx95-custom` has priority 10, which is higher than `meta-imx` (8) and
`meta-freescale` (7). This means your bbappend always takes effect.

### Rule 5: `repo sync` Resets Upstream Layers

Running `repo sync` will reset any uncommitted changes in `sources/meta-imx/`,
`sources/meta-freescale/`, `sources/poky/`, etc. This is another reason to never
modify upstream layers directly — your changes will be silently lost.

---

## Useful bitbake-layers Commands

```bash
# Show all layers in the current build
bitbake-layers show-layers

# Show which layer provides a specific recipe
bitbake-layers show-recipes linux-imx

# Show all bbappend files for a recipe
bitbake-layers show-appends linux-imx

# Show all recipes in a layer
bitbake-layers show-recipes -l meta-imx95-custom

# Add a layer to bblayers.conf
bitbake-layers add-layer sources/meta-imx95-custom

# Remove a layer from bblayers.conf
bitbake-layers remove-layer sources/meta-imx95-custom

# Create a new layer
bitbake-layers create-layer sources/meta-imx95-custom
```

---

## Useful bitbake Commands for Customization

```bash
# Show all variables for a recipe (useful for debugging bbappend)
bitbake -e linux-imx | grep ^SRC_URI

# Show the full recipe environment
bitbake -e linux-imx > /tmp/linux-imx-env.txt

# Force a recipe to re-fetch and recompile
bitbake linux-imx -c cleansstate && bitbake linux-imx

# Run only the configure task (to check bbappend effects)
bitbake linux-imx -c configure

# Run only the compile task
bitbake linux-imx -c compile

# Force recompile without cleaning
bitbake linux-imx -c compile -f

# Deploy the kernel artifacts to tmp/deploy/images/
bitbake linux-imx -c deploy -f

# Open kernel menuconfig
bitbake linux-imx -c menuconfig

# Show task dependency graph for a recipe
bitbake -g linux-imx && dot -Tpng task-depends.dot -o task-depends.png
```

---

## Common Mistakes and How to Avoid Them

| Mistake | Symptom | Fix |
|---|---|---|
| Editing upstream layer directly | Change lost after `repo sync` | Use bbappend in meta-imx95-custom |
| Wrong `BBFILE_PRIORITY` | bbappend not applied | Set priority > 8 in layer.conf |
| Missing `FILESEXTRAPATHS:prepend` | SRC_URI file not found | Add `FILESEXTRAPATHS:prepend := "${THISDIR}/files:"` |
| Wrong bbappend filename | bbappend not matched | Use `linux-imx_%.bbappend` (% = any version) |
| `LAYERSERIES_COMPAT` mismatch | Layer not loaded | Set to `"scarthgap"` for Scarthgap BSP |
| Overlay DTS not in `KERNEL_DEVICETREE` | DTB not built | Add `KERNEL_DEVICETREE:append = " freescale/imx95-custom.dtb"` |
| `do_configure:append` syntax error | Build fails at configure | Use `:append` not `_append` (Scarthgap uses new override syntax) |
