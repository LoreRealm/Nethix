# runebar.sh — the Nethix/cleric standard terminal progress bar (v3).
#
# One shared library for every terminal progress display. Three styles via
# one API so every tool (cleric, cantrip-*, scri, summon) looks the same:
#
#   rb_begin <total> [title]   start a multi-step task; sets RB_TOTAL
#   rb_step  [label]           advance one step (partial-block smooth bar)
#   rb_set   <done> [label]    jump to an absolute step count
#   rb_task  <msg>             one-shot titled spinner line (indeterminate)
#   rb_done  [msg]             finish: erase bar, print completion line
#   rb_cast  <done> <total> <label>   legacy per-spell cast line (kept for
#                                     cleric's dispatcher; same rendering)
#
# Rendering notes:
# - Smooth fill via Unicode partial blocks (█▇▆▅▄▃▂▁, U+2588-258F) so the bar
#   advances in eighths of a cell, not whole chars (mike42's technique).
# - Futhark rune trail + braille spinner frames (cli-spinners style).
# - FANCY auto-off for pipes and non-UTF locales (cron-safe ASCII bar).
# - rb_task/rb_step redraw one line with \r when on a TTY — no scrolling spam.
#
# Standalone demo: ./runebar.sh [steps]

RB_BAR_WIDTH=24
RB_RUNES='ᛝ ᛟ ᚨ ᛉ ᚦ ᚱ ᚷ ᛉ ᛒ ᛘ ᛚ ᛜ'
RB_FRAMES='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
RB_BLOCKS='█▇▆▅▄▃▂▁'
RB_TOTAL=1; RB_DONE=0; RB_LABEL=""

if [[ -t 1 ]] && locale 2>/dev/null | grep -qi 'utf-8\|utf8'; then
    RB_FANCY=1
else
    RB_FANCY=0
fi

# rb_bar <done> <total> — render the smooth bar itself
rb_bar() {
    local done=$1 total=${2:-1} bar="" i
    (( total < 1 )) && total=1
    (( done > total )) && done=total
    if (( RB_FANCY )); then
        local exact done_blocks partial idx
        exact=$(( done * RB_BAR_WIDTH * 8 / total ))
        done_blocks=$(( exact / 8 ))
        partial=$(( exact % 8 ))
        for ((i=0; i<RB_BAR_WIDTH; i++)); do
            if (( i < done_blocks )); then bar+='█'
            elif (( i == done_blocks && partial > 0 )); then
                idx=$(( 8 - partial ))
                bar+="${RB_BLOCKS:$idx:1}"
            else bar+='▒'
            fi
        done
    else
        local fill=$(( done * RB_BAR_WIDTH / total ))
        for ((i=0; i<RB_BAR_WIDTH; i++)); do
            if (( i < fill )); then bar+='='; else bar+='-'; fi
        done
    fi
    printf '%s' "$bar"
}

# rb_line <done> <total> <label> — full progress line (used by rb_step)
rb_line() {
    local done=$1 total=$2 label=$3
    (( total < 1 )) && total=1
    (( done > total )) && done=total
    local pct=$(( done * 100 / total ))
    if (( RB_FANCY )); then
        local trail="" r i
        local runes=($RB_RUNES); local nt=${#runes[@]}
        for ((i=0; i<5; i++)); do
            r=$(( (done + i * 3) % nt ))
            trail+="${runes[$r]} "
        done
        local frame_i=$(( (done + SECONDS + $$) % ${#RB_FRAMES} ))
        printf '%s%-16s %s %3d%% %s' "$trail" "$label" "$(rb_bar "$done" "$total")" "$pct" "${RB_FRAMES:$frame_i:1}"
    else
        printf '[%s] %3d%% %s' "$(rb_bar "$done" "$total")" "$pct" "$label"
    fi
}

# --- public API ---
rb_begin() {
    RB_TOTAL=${1:-1}; RB_DONE=0; RB_LABEL=${2:-"working"}
    (( RB_TOTAL < 1 )) && RB_TOTAL=1
    return 0
}

rb_step() {
    RB_LABEL=${1:-$RB_LABEL}
    (( RB_DONE < RB_TOTAL )) && RB_DONE=$(( RB_DONE + 1 ))
    rb_print
}

rb_set() {
    RB_DONE=${1:-0}
    RB_LABEL=${2:-$RB_LABEL}
    rb_print
}

rb_print() {
    if [[ -t 1 ]]; then
        printf '\r%s' "$(rb_line "$RB_DONE" "$RB_TOTAL" "$RB_LABEL")"
    else
        printf '%s\n' "$(rb_line "$RB_DONE" "$RB_TOTAL" "$RB_LABEL")"
    fi
}

rb_task() {
    # indeterminate titled spinner (single line while on TTY)
    local msg=$1 i=0
    if [[ -t 1 ]] && (( RB_FANCY )); then
        while :; do
            printf '\r%s %s' "${RB_FRAMES:$((i % ${#RB_FRAMES})):1}" "$msg"
            (( i++ )); sleep 0.12
        done
    else
        printf ':: %s...\n' "$msg"
    fi
}

rb_kill_spinner() { kill %1 2>/dev/null; printf '\r\033[K'; }

rb_done() {
    if [[ -t 1 ]]; then printf '\r\033[K'; fi
    local msg=${1:-"done"}
    if (( RB_FANCY )); then
        printf 'ᛝ ᛟ ᚦ ᚱ ᛉ ᛒ  %s\n' "$msg"
    else
        printf ':: %s\n' "$msg"
    fi
}

# legacy cleric dispatcher entry point
rb_cast() {
    local done=${1:-0} total=${2:-1} label=${3:-spell}
    rb_line "$done" "$total" "$label"
    printf '\n'
}

# legacy finale
rb_finale() {
    local total=${1:-1}
    if (( RB_FANCY )); then
        printf '\n%s\n' "ᛝ ᛟ ᚦ ᚱ ᛉ ᛒ    all $total runes cast    ᛒ ᛉ ᚱ ᚦ ᛟ ᛝ"
        printf 'the runes glow briefly, then dim. the incantation is spent.\n\n'
    else
        printf 'scan complete: %d spells cast\n' "$total"
    fi
}

# standalone demo
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    total=${1:-5}
    rb_begin "$total" "demo"
    for ((d=1; d<=total; d++)); do
        RB_DONE=$d; RB_LABEL="step-$d"; rb_print; sleep 0.4
    done
    rb_done "demo complete"
    rb_finale "$total"
fi
