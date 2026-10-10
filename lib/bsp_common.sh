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

# ─── The Yocto MACHINE: the names EXIST. None builds THIS board's device tree ──
#
# ⚠️ CORRECTED 2026-10-10 after actually reading the local BSP. An earlier
# version of this file called these names "unverified guesses" with "1
# supporting reference". That was wrong about the CAUSE, and the real cause is
# more dangerous.
#
# MEASURED in ~/Documents/nxp/linux/imx-yocto-bsp (sources/meta-imx):
#   imx95-19x19-lpddr5-evk.conf    EXISTS. bitbake accepts it. Already used for
#                                  a local build (build-imx95-drone-sizer).
#   imx95-15x15-lpddr4x-frdm.conf  EXISTS.
#   ...nine imx95 machine confs in total.
#
# So the name is NOT doubtful. It is VALID AND WRONG:
#   imx95-19x19-lpddr5-evk   builds  imx95-19x19-evk.dtb
#   imx95-15x15-lpddr4x-frdm builds  imx95-15x15-frdm.dtb
#   THIS BOARD RUNS          ------  imx95-19x19-frdm-pro-neutron.dtb  [MEASURED]
#
# Every available machine gives you either the right SoC package with the WRONG
# BOARD (19x19 EVK) or the right board family with the WRONG PACKAGE (FRDM at
# 15x15). There is no 19x19 FRDM-PRO machine in this BSP.
#
# ⇒ THAT IS THE DANGEROUS SHAPE, not a missing file: a MACHINE that FAILS
#   bitbake is the good outcome. One that EXISTS and builds a DIFFERENT BOARD
#   produces a bootable-looking image with the wrong device tree.
#
# WHY IT IS ABSENT — likely upstream, not local:
#   [SOURCED — Kyle, i.MX product org, 2026-10-10]: NXP may not have released a
#   formal FRDM-IMX95-PRO BSP yet. NOT independently verified against an NXP
#   release index. If true, WAITING FOR A NEWER SNAPSHOT DOES NOT HELP and the
#   path is a custom machine conf (see imx95-derive-carrier).
#   ⚠️ An earlier version of this repo said Q3 "needs a newer BSP snapshot".
#   That was a HYPOTHESIS about the fix stated as a blocker. Retracted.
# ⚠️ THESE ARE TWO DIFFERENT CASES AND AN EARLIER VERSION OF THIS FILE FLATTENED
# THEM INTO ONE ARRAY. Verified against the local BSP 2026-10-10:
#
#   EXISTS, builds the WRONG BOARD  -> DANGEROUS: valid name, wrong device tree,
#                                      image looks fine
#   DOES NOT EXIST                  -> SAFE: bitbake fails loudly, which is the
#                                      good outcome. These are v1 inventions.
_BSP_EXISTS_WRONG_BOARD=("imx95-19x19-lpddr5-evk" "imx95-15x15-lpddr4x-frdm" "imx95evk")
_BSP_NONEXISTENT=("imx95frdm" "imx95-15x15-evk")

# bsp_warn_if_unverified_machine <machine> [context]
#   Warns on stderr, with a DIFFERENT message per case:
#     - a name that EXISTS but builds another board  -> loud warning (dangerous)
#     - a name this repo INVENTED and that does not
#       exist in meta-imx                            -> note that bitbake will
#                                                       fail, which is SAFE
#   Never refuses: the caller may legitimately be building a board whose MACHINE
#   genuinely is one of these, and this repo has no authority to overrule them.
bsp_warn_if_unverified_machine() {
    local machine="${1:-}" ctx="${2:-}" m
    [ -n "$machine" ] || return 0
    for m in "${_BSP_EXISTS_WRONG_BOARD[@]}"; do
        if [ "$machine" = "$m" ]; then
            {
                echo ""
                echo "⚠️  MACHINE '$machine' EXISTS in meta-imx and bitbake will accept it${ctx:+ ($ctx)},"
                echo "    but it does NOT build this board's device tree."
                echo ""
                echo "      imx95-19x19-lpddr5-evk    builds  imx95-19x19-evk.dtb"
                echo "      imx95-15x15-lpddr4x-frdm  builds  imx95-15x15-frdm.dtb"
                echo "      THIS BOARD RUNS                   imx95-19x19-frdm-pro-neutron.dtb"
                echo ""
                echo "    No 19x19 FRDM-PRO machine exists in this BSP — every option is"
                echo "    either the right SoC package with the wrong board, or the right"
                echo "    board family with the wrong package."
                echo ""
                echo "    ⇒ This is NOT 'an unverified name'. It is a VALID name that builds"
                echo "      a DIFFERENT BOARD: the image will look fine and carry the wrong"
                echo "      device tree. A MACHINE that FAILS bitbake is the good outcome."
                echo ""
                echo "    Likely cause [SOURCED — Kyle, 2026-10-10, not independently verified]:"
                echo "    NXP may not have released a formal FRDM-IMX95-PRO BSP yet. If so, a"
                echo "    newer snapshot will not help — write a custom machine conf."
                echo ""
            } >&2
            return 0
        fi
    done
    for m in "${_BSP_NONEXISTENT[@]}"; do
        if [ "$machine" = "$m" ]; then
            {
                echo ""
                echo "ℹ️  MACHINE '$machine' does NOT exist in meta-imx${ctx:+ ($ctx)}."
                echo "    It is one of this repo's v1 inventions. The nearest real names are"
                echo "    imx95-15x15-lpddr4x-evk and imx95-15x15-lpddr4x-frdm."
                echo ""
                echo "    ⇒ This is the SAFE failure: bitbake will stop with 'no such machine'"
                echo "      rather than silently building a different board. Fix the name."
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
#   the MACHINE is empty; warns per-case otherwise (see above).
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
