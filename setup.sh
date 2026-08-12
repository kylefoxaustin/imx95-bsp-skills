#!/bin/bash
# setup.sh — imx95-bsp-skills bootstrap installer
#
# Installs the imx95-bsp-skills bundle into a BSP workspace directory.
# Does NOT download the BSP itself — use imx95-download-bsp for that.
#
# Usage:
#   ./setup.sh --workspace ~/imx95-workspace
#   ./setup.sh --workspace /data/imx95-ws --skills-dir ~/.claude/skills
#
# Environment overrides:
#   CLAUDE_SKILLS_DIR   Override destination for skills installation
#
# Copyright 2024 imx95-bsp-skills contributors
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# ── Constants ─────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_VERSION="0.1.0"
BUNDLE_NAME="imx95-bsp-skills"
MIN_DISK_GB=5

# Required host tools for the full workflow
REQUIRED_TOOLS=(git python3 dtc)
# Tools needed for build/flash (warn if missing, don't fail)
OPTIONAL_TOOLS=(repo bitbake uuu fdtdump devtool)

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# ── Helpers ───────────────────────────────────────────────────────────────────
info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()     { error "$*"; exit 1; }

usage() {
    cat <<EOF
${BOLD}imx95-bsp-skills setup.sh${NC}

Installs the imx95-bsp-skills bundle into a BSP workspace directory.

${BOLD}USAGE${NC}
    $0 --workspace <path> [OPTIONS]

${BOLD}OPTIONS${NC}
    --workspace <path>    Path to BSP workspace (created if it does not exist)
    --skills-dir <path>   Override skills install dir (default: <workspace>/.imx95-skills)
                          Can also be set via CLAUDE_SKILLS_DIR env var
    --no-tool-check       Skip host tool checks
    --dry-run             Print what would be done without doing it
    -h, --help            Show this help

${BOLD}EXAMPLES${NC}
    $0 --workspace ~/imx95-workspace
    $0 --workspace /data/imx95-ws --skills-dir ~/.claude/skills/imx95-bsp
    CLAUDE_SKILLS_DIR=~/.claude/skills $0 --workspace ~/imx95-workspace

${BOLD}WHAT THIS SCRIPT DOES${NC}
    1. Creates <workspace>/ if it does not exist
    2. Copies CLAUDE.md into <workspace>/CLAUDE.md
    3. Copies skills/, context/, references/ into <skills-dir>/
    4. Creates <workspace>/targets/ directory
    5. Creates <workspace>/overlay-tracker/ as an empty git repository
    6. Writes <skills-dir>/VERSION with bundle version and git SHA
    7. Prints a "Next steps" summary

${BOLD}NEXT STEPS AFTER SETUP${NC}
    cd <workspace>
    claude
    # Then say: "help me set up the i.MX 95 BSP workspace"
EOF
}

# ── Argument parsing ──────────────────────────────────────────────────────────
WORKSPACE=""
SKILLS_DIR_OVERRIDE="${CLAUDE_SKILLS_DIR:-}"
NO_TOOL_CHECK=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --workspace)
            WORKSPACE="${2:?--workspace requires a path argument}"
            shift 2
            ;;
        --skills-dir)
            SKILLS_DIR_OVERRIDE="${2:?--skills-dir requires a path argument}"
            shift 2
            ;;
        --no-tool-check)
            NO_TOOL_CHECK=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "Unknown argument: $1  (run with --help for usage)"
            ;;
    esac
done

[[ -n "$WORKSPACE" ]] || die "--workspace is required. Run with --help for usage."

# Expand ~ in paths
WORKSPACE="${WORKSPACE/#\~/$HOME}"
[[ -n "$SKILLS_DIR_OVERRIDE" ]] && SKILLS_DIR_OVERRIDE="${SKILLS_DIR_OVERRIDE/#\~/$HOME}"

# Determine skills install directory
if [[ -n "$SKILLS_DIR_OVERRIDE" ]]; then
    SKILLS_DIR="$SKILLS_DIR_OVERRIDE"
else
    SKILLS_DIR="${WORKSPACE}/.imx95-skills"
fi

# ── Dry-run wrapper ───────────────────────────────────────────────────────────
run() {
    if $DRY_RUN; then
        echo -e "${YELLOW}[DRY-RUN]${NC} $*"
    else
        "$@"
    fi
}

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║         imx95-bsp-skills  v${BUNDLE_VERSION}  setup.sh              ║${NC}"
echo -e "${BOLD}║         NXP i.MX 95 Yocto BSP Skill Bundle              ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
info "Source bundle : ${SCRIPT_DIR}"
info "Workspace     : ${WORKSPACE}"
info "Skills dir    : ${SKILLS_DIR}"
$DRY_RUN && warn "DRY-RUN mode — no files will be written"
echo ""

# ── Step 1: Check required host tools ────────────────────────────────────────
if ! $NO_TOOL_CHECK; then
    echo -e "${BOLD}── Checking host tools ──────────────────────────────────────${NC}"
    MISSING_REQUIRED=()
    MISSING_OPTIONAL=()

    for tool in "${REQUIRED_TOOLS[@]}"; do
        if command -v "$tool" &>/dev/null; then
            success "$tool  $(command -v "$tool")"
        else
            error "$tool  NOT FOUND"
            MISSING_REQUIRED+=("$tool")
        fi
    done

    for tool in "${OPTIONAL_TOOLS[@]}"; do
        if command -v "$tool" &>/dev/null; then
            success "$tool  $(command -v "$tool")"
        else
            warn "$tool  not found (needed for build/flash phases)"
            MISSING_OPTIONAL+=("$tool")
        fi
    done

    # Special check: uuu version
    if command -v uuu &>/dev/null; then
        UUU_VER=$(uuu --version 2>&1 | grep -oP '\d+\.\d+\.\d+' | head -1 || echo "unknown")
        UUU_MAJOR=$(echo "$UUU_VER" | cut -d. -f1)
        UUU_MINOR=$(echo "$UUU_VER" | cut -d. -f2)
        UUU_PATCH=$(echo "$UUU_VER" | cut -d. -f3)
        if [[ "$UUU_MAJOR" -gt 1 ]] || \
           [[ "$UUU_MAJOR" -eq 1 && "$UUU_MINOR" -gt 5 ]] || \
           [[ "$UUU_MAJOR" -eq 1 && "$UUU_MINOR" -eq 5 && "$UUU_PATCH" -ge 21 ]]; then
            success "uuu version ${UUU_VER} >= 1.5.21 ✓"
        else
            warn "uuu version ${UUU_VER} is below minimum 1.5.21 — upgrade before flashing"
        fi
    fi

    # Special check: repo tool
    if command -v repo &>/dev/null; then
        REPO_VER=$(repo --version 2>&1 | grep -oP 'repo version \S+' | head -1 || echo "repo found")
        success "repo  ${REPO_VER}"
    fi

    if [[ ${#MISSING_REQUIRED[@]} -gt 0 ]]; then
        echo ""
        error "Missing required tools: ${MISSING_REQUIRED[*]}"
        error "Install them before running the BSP workflow."
        echo ""
        echo "  Ubuntu/Debian:"
        echo "    sudo apt-get install -y git python3 device-tree-compiler"
        echo ""
        die "Aborting due to missing required tools."
    fi

    if [[ ${#MISSING_OPTIONAL[@]} -gt 0 ]]; then
        echo ""
        warn "Missing optional tools: ${MISSING_OPTIONAL[*]}"
        warn "These are needed for later phases. Install them before building or flashing."
        warn "See README.md Prerequisites section for install instructions."
    fi
    echo ""
fi

# ── Step 2: Check disk space ──────────────────────────────────────────────────
echo -e "${BOLD}── Checking disk space ──────────────────────────────────────${NC}"
PARENT_DIR="$(dirname "$WORKSPACE")"
[[ -d "$PARENT_DIR" ]] || PARENT_DIR="/"
AVAIL_GB=$(df -BG "$PARENT_DIR" 2>/dev/null | awk 'NR==2 {gsub("G",""); print $4}' || echo 0)
if [[ "$AVAIL_GB" -lt "$MIN_DISK_GB" ]]; then
    die "Only ${AVAIL_GB}GB free at ${PARENT_DIR}. Need at least ${MIN_DISK_GB}GB for workspace setup."
elif [[ "$AVAIL_GB" -lt 80 ]]; then
    warn "${AVAIL_GB}GB free at ${PARENT_DIR}. A full Yocto build needs 80–120GB. Proceed with caution."
else
    success "${AVAIL_GB}GB free at ${PARENT_DIR} ✓"
fi
echo ""

# ── Step 3: Create workspace directory ───────────────────────────────────────
echo -e "${BOLD}── Creating workspace ───────────────────────────────────────${NC}"
if [[ -d "$WORKSPACE" ]]; then
    info "Workspace already exists: ${WORKSPACE}"
else
    run mkdir -p "$WORKSPACE"
    success "Created workspace: ${WORKSPACE}"
fi

# Create standard workspace subdirectories
for dir in targets staging; do
    if [[ -d "${WORKSPACE}/${dir}" ]]; then
        info "  ${dir}/  already exists"
    else
        run mkdir -p "${WORKSPACE}/${dir}"
        success "  Created ${dir}/"
    fi
done
echo ""

# ── Step 4: Copy CLAUDE.md into workspace root ────────────────────────────────
echo -e "${BOLD}── Installing CLAUDE.md ─────────────────────────────────────${NC}"
run cp "${SCRIPT_DIR}/CLAUDE.md" "${WORKSPACE}/CLAUDE.md"
success "Copied CLAUDE.md → ${WORKSPACE}/CLAUDE.md"
echo ""

# ── Step 5: Install skills bundle into skills dir ────────────────────────────
echo -e "${BOLD}── Installing skills bundle ─────────────────────────────────${NC}"
run mkdir -p "$SKILLS_DIR"

for component in skills context references; do
    if [[ -d "${SCRIPT_DIR}/${component}" ]]; then
        run cp -r "${SCRIPT_DIR}/${component}" "${SKILLS_DIR}/"
        success "Installed ${component}/ → ${SKILLS_DIR}/${component}/"
    else
        warn "${component}/ not found in bundle — skipping"
    fi
done

# Write VERSION file
GIT_SHA="unknown"
if git -C "$SCRIPT_DIR" rev-parse --short HEAD &>/dev/null; then
    GIT_SHA=$(git -C "$SCRIPT_DIR" rev-parse --short HEAD)
fi
VERSION_CONTENT="bundle=${BUNDLE_NAME}
version=${BUNDLE_VERSION}
git_sha=${GIT_SHA}
installed=$(date -u +%Y-%m-%dT%H:%M:%SZ)
workspace=${WORKSPACE}
"
if $DRY_RUN; then
    echo -e "${YELLOW}[DRY-RUN]${NC} Would write ${SKILLS_DIR}/VERSION"
else
    echo "$VERSION_CONTENT" > "${SKILLS_DIR}/VERSION"
fi
success "Wrote ${SKILLS_DIR}/VERSION  (v${BUNDLE_VERSION}, sha=${GIT_SHA})"
echo ""

# ── Step 6: Initialize overlay-tracker git repo ───────────────────────────────
echo -e "${BOLD}── Initializing overlay-tracker ─────────────────────────────${NC}"
OVERLAY_TRACKER="${WORKSPACE}/overlay-tracker"
if [[ -d "${OVERLAY_TRACKER}/.git" ]]; then
    info "overlay-tracker already initialized: ${OVERLAY_TRACKER}"
else
    run mkdir -p "$OVERLAY_TRACKER"
    if $DRY_RUN; then
        echo -e "${YELLOW}[DRY-RUN]${NC} Would git init ${OVERLAY_TRACKER}"
    else
        git -C "$OVERLAY_TRACKER" init -q
        git -C "$OVERLAY_TRACKER" commit --allow-empty \
            -m "init: overlay-tracker for imx95-bsp-skills workspace"
    fi
    success "Initialized overlay-tracker git repo: ${OVERLAY_TRACKER}"
fi
echo ""

# ── Step 7: Create .gitignore in workspace ────────────────────────────────────
echo -e "${BOLD}── Creating workspace .gitignore ────────────────────────────${NC}"
WORKSPACE_GITIGNORE="${WORKSPACE}/.gitignore"
if [[ ! -f "$WORKSPACE_GITIGNORE" ]]; then
    if ! $DRY_RUN; then
        cat > "$WORKSPACE_GITIGNORE" <<'GITIGNORE'
# Yocto build artifacts
build/tmp/
build/cache/
build/sstate-cache/

# Downloaded sources
downloads/

# repo tool internals
.repo/

# Staging artifacts
staging/

# Python cache
__pycache__/
*.pyc
*.pyo

# Editor files
.vscode/
.idea/
*.swp
*~
GITIGNORE
    fi
    success "Created ${WORKSPACE_GITIGNORE}"
else
    info ".gitignore already exists in workspace"
fi
echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo -e "${BOLD}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║                   SETUP COMPLETE                        ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${BOLD}Workspace:${NC}      ${WORKSPACE}"
echo -e "  ${BOLD}Skills dir:${NC}     ${SKILLS_DIR}"
echo -e "  ${BOLD}Bundle version:${NC} ${BUNDLE_VERSION} (${GIT_SHA})"
echo ""
echo -e "${BOLD}Next steps:${NC}"
echo ""
echo -e "  1. Start Claude Code from the workspace:"
echo -e "     ${BLUE}cd ${WORKSPACE}${NC}"
echo -e "     ${BLUE}claude${NC}"
echo ""
echo -e "  2. Say to Claude Code:"
echo -e "     ${GREEN}\"help me set up the i.MX 95 BSP workspace for the FRDM-IMX95 EVK\"${NC}"
echo ""
echo -e "  Claude Code will invoke ${BOLD}imx95-quick-start${NC} and guide you through:"
echo -e "    • Creating a target profile"
echo -e "    • Downloading the NXP Yocto BSP (~10–20 GB, 30–60 min)"
echo -e "    • Configuring the image recipe"
echo -e "    • Building the image (2–4 hours first build)"
echo -e "    • Flashing via uuu"
echo ""
echo -e "  ${YELLOW}Tip:${NC} Make sure you have ≥ 80 GB free disk space before building."
echo ""
