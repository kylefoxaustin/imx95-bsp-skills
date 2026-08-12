---
name: imx95-download-bsp
version: "1.0"
platform: imx95
phase: setup
invoke_when:
  - "download the BSP"
  - "repo sync"
  - "get NXP sources"
  - "initialize the BSP workspace"
  - "fetch the Yocto layers"
requires_host_tools:
  - repo
  - git
  - curl
  - python3
safe: true
destructive: false
commit_gate: false
---

# imx95-download-bsp

## Purpose

Initialize and sync the NXP Yocto BSP using the Google `repo` tool and the `imx-manifest`
manifest. Downloads all BSP source layers into `<workspace>/sources/`. This is a one-time
operation per workspace; subsequent updates use `repo sync` again.

## When to Invoke

- User says "download the BSP", "repo sync", "get NXP sources", "fetch the layers"
- First-time setup after `imx95-init-target`
- When updating to a new BSP release (change manifest file, re-sync)

## Pre-conditions

1. Active target profile exists at `targets/active_target.yaml` — read it for manifest URL,
   branch, and file.
2. `repo` tool is on PATH (or can be installed to `~/bin/repo`).
3. `git` is on PATH.
4. Network access to `github.com` (or corporate mirror configured via proxy).
5. ≥ 50 GB free disk space (full BSP sync is ~10–20 GB; build will need more).

## Decision Tree

```
Is repo tool installed?
  NO  → Install repo to ~/bin/repo (Step 1)
  YES → Skip to Step 2

Is <workspace>/.repo/ already present?
  YES → Ask user: re-init (new release) or just re-sync?
    re-sync → run repo sync only (Step 3)
    re-init → run repo init then repo sync (Steps 2–3)
  NO  → Run repo init then repo sync (Steps 2–3)
```

## Procedure

### Step 1 — Ensure repo tool is installed

```bash
if ! command -v repo &>/dev/null; then
    mkdir -p ~/bin
    curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
    chmod a+x ~/bin/repo
    export PATH=$HOME/bin:$PATH
    echo "repo installed to ~/bin/repo"
fi
repo --version
```

### Step 2 — Read active target profile

Read `targets/active_target.yaml` and extract:
- `yocto.bsp_manifest_url`   → `https://github.com/nxp-imx/imx-manifest`
- `yocto.bsp_manifest_branch` → `imx-linux-scarthgap`
- `yocto.bsp_manifest_file`  → `imx-6.6.52-2.2.0.xml`
- `paths.workspace_root`     → workspace directory

### Step 3 — Initialize the repo manifest

```bash
cd <workspace_root>
repo init \
  -u https://github.com/nxp-imx/imx-manifest \
  -b imx-linux-scarthgap \
  -m imx-6.6.52-2.2.0.xml
```

Expected output: `repo initialized in <workspace_root>`

If `repo init` fails with a git error, check:
- Network connectivity: `curl -I https://github.com`
- Proxy settings: `echo $https_proxy`
- Git config: `git config --global user.email` must be set

### Step 4 — Sync all layers

```bash
cd <workspace_root>
repo sync -j8 --no-clone-bundle
```

This downloads ~10–20 GB. Estimated time: 30–60 minutes on a fast connection.

**If sync fails mid-way** (network timeout, rate limit):
```bash
repo sync -j4 --no-clone-bundle   # retry with fewer parallel jobs
```

**If a specific project fails:**
```bash
repo sync -j4 --no-clone-bundle <project-name>
```

### Step 5 — Verify sync

```bash
cd <workspace_root>
ls sources/
# Expected directories:
# meta-imx  meta-freescale  poky  meta-openembedded
# linux-imx  u-boot-imx  imx-atf  imx-mkimage
```

Run the helper script to verify:
```bash
bash skills/imx95-download-bsp/scripts/download_bsp.sh --verify-only
```

### Step 6 — Report to user

Print:
- Manifest URL, branch, file used
- List of synced layers with their HEAD commit SHAs
- Total disk usage of `sources/`
- Recommended next step: `imx95-init-source`

## Files Touched

- `<workspace>/.repo/` — created by `repo init`
- `<workspace>/sources/meta-imx/` — NXP i.MX Yocto layer
- `<workspace>/sources/meta-freescale/` — Freescale community layer
- `<workspace>/sources/poky/` — Yocto Project Poky
- `<workspace>/sources/meta-openembedded/` — OpenEmbedded layers
- `<workspace>/sources/linux-imx/` — NXP kernel source
- `<workspace>/sources/u-boot-imx/` — NXP U-Boot source
- `<workspace>/sources/imx-atf/` — ARM Trusted Firmware
- `<workspace>/sources/imx-mkimage/` — Boot image assembly tool

## Safety Rules Applied

- **R9** — Never commit inside `.repo/` or `sources/` subdirectories
- **R7** — Verify disk space before syncing

## Gotchas

- Corporate proxies: set `http_proxy` and `https_proxy` before running
- `repo sync` may fail on first run due to GitHub rate limits — retry with `-j4`
- If `.repo/` exists from a different manifest, `repo init` will warn; answer `y` to reinitialize
- `--no-clone-bundle` avoids bundle download failures on some corporate networks
- After sync, `sources/` directories are managed by `repo` — do NOT `git commit` inside them

## References

- `context/bsp-customization-workflow.md` — full workflow context
- `context/target-platform-contract.md` — target profile YAML schema
- `references/bsp-platforms-catalogue.md` — supported board MACHINE names
