#!/usr/bin/env bash
# lib/bsp_common.sh — shared guards for imx95-bsp-skills
#
# ⚠️ WHY THIS FILE EXISTS, AND WHY IT IS DELIBERATELY SMALL
#
# This repo had NO shared library. `read_yaml()` is copy-pasted into ten-plus
# scripts, and the Yocto MACHINE default was pasted into five. That is the
# structural cause of a defect fixed in imx95-device-skills the same day: one
# wrong CMA threshold existed in TWO skills, I fixed one, and the other sat
# there until a fleet-wide grep found it. A fix at the source leaves copies
# behind — so a guard that belongs in five places goes in ONE.
#
# It is NOT a migration of read_yaml and the other duplicated helpers. That is a
# bigger change with real regression risk across sixteen skills, and it is
# recorded as a known structural issue instead of attempted in passing. This
# file is additive: nothing that worked before behaves differently.
#
# Source it with:
#     source "$(dirname "${BASH_SOURCE[0]}")/../../../lib/bsp_common.sh"
# (from skills/<name>/scripts/), guarded so a missing file is not fatal.

# ─── The Yocto MACHINE name is [UNKNOWN] for this board (Q3) ─────────────────
#
# Reference counts across the fleet's i.MX95 repos:
#     imx95-19x19-frdm-pro      68
#     imx95-15x15-evk           45
#     imx95-19x19-lpddr5-evk     1   <- what five scripts SILENTLY DEFAULTED to
#
# @95emulator established a CONFIRMED NEGATIVE: the local imx-yocto-bsp has no
# machine conf or DTS for frdm-imx95-pro, and imx95-15x15-lpddr4x-frdm is a
# DIFFERENT FRDM variant that must not be substituted. So nobody has
# established the right value — see references/imx95-ground-truth.md §7 / Q3.
#
# ⇒ A wrong MACHINE that FAILS bitbake is the GOOD outcome. The bad one is a
#   name that EXISTS and builds a DIFFERENT BOARD, because that produces a
#   plausible image for hardware you do not have. The cost of the silent default
#   is therefore asymmetric and in the dangerous direction.
_BSP_UNVERIFIED_MACHINES=("imx95-19x19-lpddr5-evk" "imx95frdm" "imx95-15x15-evk")

# bsp_warn_if_unverified_machine <machine> [context]
#   Warns — loudly, on stderr — when a MACHINE is one of this repo's v1 guesses.
#   Does NOT refuse: the caller may legitimately be building for a board whose
#   MACHINE genuinely is one of these, and this repo has no authority to say
#   otherwise. It only knows which names it previously invented.
bsp_warn_if_unverified_machine() {
    local machine="${1:-}" ctx="${2:-}" m
    [ -n "$machine" ] || return 0
    for m in "${_BSP_UNVERIFIED_MACHINES[@]}"; do
        if [ "$machine" = "$m" ]; then
            {
                echo ""
                echo "⚠️  MACHINE '$machine' is one of this repo's UNVERIFIED v1 guesses${ctx:+ ($ctx)}."
                echo "    imx95-19x19-lpddr5-evk has 1 supporting reference across the fleet;"
                echo "    imx95-19x19-frdm-pro has 68, and the local BSP has NO conf for"
                echo "    frdm-imx95-pro at all. The correct MACHINE is [UNKNOWN] (Q3)."
                echo ""
                echo "    A wrong MACHINE that FAILS bitbake is the good outcome."
                echo "    The bad one is a name that EXISTS and builds a DIFFERENT BOARD."
                echo "    Confirm against your own BSP checkout before trusting the output."
                echo ""
            } >&2
            return 0
        fi
    done
    return 0
}

# bsp_machine_or_refuse <machine> [context]
#   For operations where proceeding on a guess is EXPENSIVE or MISLEADING —
#   a long bitbake, or an artifact that will be flashed. Refuses (exit 6) when
#   the MACHINE is empty, warns when it is an unverified guess.
bsp_machine_or_refuse() {
    local machine="${1:-}" ctx="${2:-}"
    if [ -z "$machine" ]; then
        {
            echo "FATAL: MACHINE is not set${ctx:+ ($ctx)}, and this repo will NOT guess one."
            echo ""
            echo "  Set it in your target profile (targets/active_target.yaml: machine: <name>)"
            echo "  or pass it explicitly."
            echo ""
            echo "  The correct value for the fleet FRDM-IMX95-PRO is [UNKNOWN] — see"
            echo "  references/imx95-ground-truth.md §7. Establish it from YOUR BSP"
            echo "  checkout (conf/machine/*.conf), not from this repo."
        } >&2
        return 6
    fi
    bsp_warn_if_unverified_machine "$machine" "$ctx"
    return 0
}
