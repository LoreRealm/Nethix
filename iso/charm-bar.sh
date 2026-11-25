#!/usr/bin/env bash
# charm-bar.sh — themed progress filter for portage output.
#
# Pipes emerge's output through a rune-bar renderer. Real messages and errors
# pass through untouched; the bar lives on the last line and redraws via \r.
# When stdin is not a TTY-aware stream (e.g. tee to a file) the bar degrades
# gracefully: no escape codes, just periodic percent lines.
#
# Usage:
#   emerge ... 2>&1 | charm-bar.sh "phase label"
#
# NOTE: not currently used by iso/build.sh (PROGRESS/CHARM off by default);
# reserved for the user-facing install flow (summon) where pretty output
# earns its keep. Keep this file syntax-clean and tested for that day.
#
# Threading: reads line-by-line, so it can be inserted anywhere in a pipe.
# Percentages come from portage's own ">>> Emerging (N of M)" counters and
# the per-package "[ NN%]" build-progress tokens portage emits when not
# fully quiet.

set -euo pipefail

LABEL=${1:-working}

BAR_WIDTH=${CHARM_BAR_WIDTH:-24}
TOTAL_GLYPHS=${CHARM_BAR_GLYPHS:-"ᚠ ᚢ ᚦ ᚨ ᚱ ᚲ ᚷ ᚹ ᚺ ᚾ ᛁ ᛊ ᛏ ᛒ ᛖ ᛗ"}
CONSUMED=${CHARM_BAR_CONSUMED:-"·"}
FLAME_ACTIVE=${CHARM_BAR_FLAME_ON:-"✦"}
FLAME_IDLE=${CHARM_BAR_FLAME_OFF:-"✧"}

# split glyph list on spaces into an array
IFS=' ' read -r -a GLYPHS <<< "$TOTAL_GLYPHS"

IS_TTY=0
[[ -t 2 ]] && IS_TTY=1

cur=0
total=0
pkg=""
pct=0
overall=0

render() {
    # $1 = overall percent 0..100, $2 = intra-package percent (optional)
    local pct_over=$1
    if (( total > 0 )); then
        # fraction = (cur-1 + intra/100)/total, clamped to 0..100
        local frac intra
        frac=$(( cur - 1 ))
        (( frac < 0 )) && frac=0
        intra=${2:-0}
        overall=$(( (frac * 100 + intra) / total ))
        (( overall > 100 )) && overall=100
    else
        overall=$pct_over
    fi

    local filled=$(( overall * BAR_WIDTH / 100 ))
    local i out=""
    for ((i=0; i<BAR_WIDTH; i++)); do
        if (( i < filled )); then
            out+="${GLYPHS[$(( i % ${#GLYPHS[@]} ))]}"
        else
            out+="$CONSUMED"
        fi
        out+=" "
    done

    if (( overall >= 100 )); then
        printf '\r[%s] %s %s %s %3d%%\n' \
            "$out" "$FLAME_ACTIVE" "$LABEL" "complete!" "$overall" >&2
    elif (( IS_TTY )); then
        printf '\r[%s] %s %s%s %3d%%' \
            "$out" "$FLAME_ACTIVE" "$LABEL" "$pkg" "$overall" >&2
    else
        printf '[%s] %s %s%s %3d%%\n' \
            "$out" "$FLAME_ACTIVE" "$LABEL" "$pkg" "$overall" >&2
    fi
}

while IFS= read -r line; do
    printf '%s\n' "$line"
    # count total jobs from "Emerging (N of M)" — M is our total
    if [[ $line =~ Emerging\ \(([0-9]+)\ of\ ([0-9]+)\) ]]; then
        cur=${BASH_REMATCH[1]}
        total=${BASH_REMATCH[2]}
        pkg=""
        # package atom: token after the closing paren, minus repo suffix
        if [[ $line =~ Emerging\ \([0-9]+\ of\ [0-9]+\)\ ([^[:space:]]+) ]]; then
            pkg=" ${BASH_REMATCH[1]%::*}"
        fi
        render 0
    elif [[ $line =~ \[\ *([0-9]+)%\ *\] ]]; then
        pct=${BASH_REMATCH[1]}
        render "$pct" "$pct"
    elif [[ $line == ">>>"*"Installing"*"("*" of "*" )"* || $line == ">>>"*"Completed"*"("*" of "*" )"* || $line == ">>>"*"Merging"*"("*" of "*" )"* ]]; then
        # e.g. ">>> Installing (2 of 14) app-misc/foo-1.2::gentoo"
        if [[ $line == *"("*" of "*)* ]]; then
            cur=${line##*(}
            cur=${cur%% of*}
            total=${line##* of }
            total=${total%%)*}
        fi
        render 100
    fi
done

render 100 100
