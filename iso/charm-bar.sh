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
    # $1 = overall percent 0..100
    local pct_over=$1
    if (( total > 0 )); then
        # combine package progress with per-package pct when known:
        # fraction = (cur-1 + pct/100)/total, clamped
        local frac
        frac=$(( cur - 1 ))
        (( frac < 0 )) && frac=0
        # add intra-package progress if we track it (passed via $2)
        local intra=${2:-0}
        overall=$(( (frac * 100 + intra) / total ))
        (( overall > 100 )) && overall=100
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
        printf '\r[%s] %s %s %s %3d%% %-*s\r\n' \
            "$out" "$FLAME_ACTIVE" "$LABEL" "complete!" "$overall" 0 "" >&2
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
        # try to grab package atom from same line: ::gentoo / ::nethix suffix
        if [[ $line =~ (Emerging\ \([0-9]+\ of\ [0-9]+\)\ [^[:space:]]+) ]]; then
            pkg=" ${BASH_REMATCH[1]#Emerging (*of *)}"
        fi
        render 0
    elif [[ $line =~ \[\ *([0-9]+)%\ *\] ]]; then
        pct=${BASH_REMATCH[1]}
        render "$pct" "$pct"
    elif [[ $line =~ >>>\ (Installing|Completed|Merging)\ \(([0-9]+)\ of\ ([0-9]+)\) ]]; then
        cur=${BASH_REMATCH[2]}
        total=${BASH_REMATCH[3]}
        render 100
    fi
done

render 100 100
