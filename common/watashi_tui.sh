#!/bin/bash
# ============================================================
#  Watashi Manager - terminal skin
#  Every colour, box, banner and menu that the terminal side
#  of the panel shows is born in this one file.
#    WATASHI_TUI=0   ->  the plain old look comes back
# ============================================================

if [ -n "$WS_TUI_LOADED" ]; then
    return 0 2>/dev/null || exit 0
fi
WS_TUI_LOADED=1

export WS_BRAND_A="WATASHI"
export WS_BRAND_B="MANAGER"
export WS_BRAND="WATASHI MANAGER"
export WS_TAG="a panel with a pulse"

# ---------- is the skin welcome here ----------
function ws_skin_on() {
    case "$WATASHI_TUI" in
    0 | off | no | false) return 1 ;;
    esac
    case "$TERM" in
    "" | dumb) return 1 ;;
    esac
    return 0
}

function ws_tty() {
    [ -t 0 ] && [ -t 1 ]
}

function ws_cols() {
    local c=""
    c=$(tput cols 2>/dev/null)
    case "$c" in
    '' | *[!0-9]*) c=80 ;;
    esac
    [ "$c" -lt 40 ] && c=40
    echo "$c"
}

function ws_deep() {
    ws_skin_on || return 1
    case "$COLORTERM" in
    truecolor | 24bit) return 0 ;;
    esac
    local n=""
    n=$(tput colors 2>/dev/null)
    case "$n" in
    '' | *[!0-9]*) return 1 ;;
    esac
    [ "$n" -ge 256 ] && return 0
    return 1
}

# ---------- ink ----------
WS_VIOLET="124 58 237"
WS_LILAC="167 139 250"
WS_BLUE="59 130 246"
WS_CYAN="34 211 238"
WS_MINT="16 185 129"
WS_AMBER="245 158 11"
WS_ROSE="239 68 68"
WS_MUTED="139 146 165"
WS_GRAD=("124 58 237" "137 71 240" "112 94 243" "86 118 245" "62 142 243" "46 168 241" "36 190 239" "34 205 238" "58 216 240")

function ws_fg() {
    ws_deep || return 0
    printf '\033[38;2;%s;%s;%sm' "$1" "$2" "$3"
}

function ws_off() {
    ws_skin_on || return 0
    printf '\033[0m'
}

function ws_bold() {
    ws_skin_on || return 0
    printf '\033[1m'
}

function ws_faint() {
    ws_skin_on || return 0
    printf '\033[2m'
}

function ws_reset_term() {
    printf '\033[0m'
    printf '\033[?25h'
    tput sgr0 2>/dev/null || true
}

function ws_clear() {
    ws_tty || return 0
    printf '\033[H\033[2J'
}

function ws_pad() {
    local w="$1"
    local c=""
    c=$(ws_cols)
    local p=$(((c - w) / 2))
    [ "$p" -lt 0 ] && p=0
    printf '%*s' "$p" ''
}

function ws_rule() {
    local w="$1"
    case "$w" in
    '' | *[!0-9]*) w=46 ;;
    esac
    local c=""
    c=$(ws_cols)
    [ "$w" -gt $((c - 4)) ] && w=$((c - 4))
    ws_pad "$w"
    local i=0
    local g=0
    while [ "$i" -lt "$w" ]; do
        g=$((i * 9 / w))
        printf '%s\xe2\x94\x80' "$(ws_fg ${WS_GRAD[$g]})"
        i=$((i + 1))
    done
    printf '%s\n' "$(ws_off)"
}

# ---------- the mark is the name ----------
# No drawing here on purpose. A picture made of blocks depends on the
# console font and breaks; letters never do. Each letter gets its own
# colour, so the name walks through the panel gradient.
WS_WORD="WATASHI MANAGER"

function ws_word_spaced() {
    local out=""
    local ch=""
    local i=0
    local n=${#WS_WORD}
    while [ "$i" -lt "$n" ]; do
        ch=${WS_WORD:$i:1}
        if [ "$ch" = " " ]; then
            out="$out  "
        else
            out="$out$ch "
        fi
        i=$((i + 1))
    done
    printf '%s' "${out% }"
}

function ws_art() {
    printf '%s\n' "$WS_BRAND"
}

function ws_banner() {
    ws_skin_on || {
        echo "$WS_BRAND"
        return 0
    }
    local text=""
    text=$(ws_word_spaced)
    local len=${#text}
    local pos=0
    local ch=""
    local g=0
    printf '%s' "$(ws_pad $len)"
    while [ "$pos" -lt "$len" ]; do
        ch=${text:$pos:1}
        g=$((pos * 9 / len))
        [ "$g" -gt 8 ] && g=8
        printf '%s%s%s' "$(ws_bold)" "$(ws_fg ${WS_GRAD[$g]})" "$ch"
        pos=$((pos + 1))
    done
    printf '%s\n' "$(ws_off)"
}

function ws_version_line() {
    local t="$1"
    [ -z "$t" ] && t="$WS_VERSION_LINE"
    [ -z "$t" ] && return 0
    ws_skin_on || {
        echo "$t"
        return 0
    }
    printf '%s%s%s%s\n' "$(ws_pad ${#t})" "$(ws_fg $WS_MINT)" "$t" "$(ws_off)"
}

function ws_brand_line() {
    ws_skin_on || {
        echo "$WS_BRAND"
        return 0
    }
    printf '%s' "$(ws_pad 17)"
    printf '%s%s%s' "$(ws_bold)" "$(ws_fg $WS_LILAC)" "$WS_BRAND_A"
    printf '%s%s %s%s\n' "$(ws_off)" "$(ws_bold)" "$(ws_fg $WS_CYAN)$WS_BRAND_B" "$(ws_off)"
}

function ws_tag_line() {
    local t="$1"
    [ -z "$t" ] && t="$WS_TAG"
    printf '%s%s%s%s\n' "$(ws_pad ${#t})" "$(ws_fg $WS_MUTED)" "$t" "$(ws_off)"
}

function ws_chip() {
    printf '%s\xe2\x97\x86%s %s%s%s %s%s%s' "$(ws_fg $WS_VIOLET)" "$(ws_off)" "$(ws_fg $WS_LILAC)" "$WS_BRAND_A" "$(ws_off)" "$(ws_fg $WS_CYAN)" "$WS_BRAND_B" "$(ws_off)"
}

function ws_head() {
    ws_clear
    echo
    ws_banner
    if [ -n "$1" ]; then
        ws_tag_line "$1"
    else
        ws_tag_line "$WS_TAG"
    fi
    ws_version_line
    echo
}

# ---------- the palette every whiptail box inherits ----------
WS_NEWT='root=,black
roottext=gray,black
border=brightmagenta,black
window=lightgray,black
shadow=,black
title=brightcyan,black
button=black,brightmagenta
actbutton=black,brightcyan
compactbutton=brightcyan,black
checkbox=lightgray,black
actcheckbox=black,brightcyan
entry=brightcyan,black
disentry=gray,black
label=brightmagenta,black
listbox=lightgray,black
actlistbox=black,brightcyan
sellistbox=brightcyan,black
actsellistbox=black,brightmagenta
textbox=lightgray,black
acttextbox=black,brightcyan
emptyscale=,gray
fullscale=,brightmagenta
helpline=brightcyan,black'

if ws_skin_on; then
    export NEWT_COLORS="$WS_NEWT"
fi

# ---------- small words ----------
function ws_ok() {
    printf '%s\xe2\x9c\x93 %s%s\n' "$(ws_fg $WS_MINT)" "$1" "$(ws_off)"
}

function ws_bad() {
    printf '%s\xe2\x9c\x97 %s%s\n' "$(ws_fg $WS_ROSE)" "$1" "$(ws_off)"
}

function ws_note() {
    printf '%s\xe2\x80\xa2 %s%s\n' "$(ws_fg $WS_MUTED)" "$1" "$(ws_off)"
}

function ws_kv() {
    printf '%s  %-22s%s%s%s\n' "$(ws_fg $WS_MUTED)" "$1" "$(ws_fg $WS_CYAN)" "$2" "$(ws_off)"
}

# ---------- a themed whiptail box ----------
function ws_box() {
    local title="$1"
    local text="$2"
    if ws_skin_on && ws_tty && command -v whiptail >/dev/null 2>&1; then
        NEWT_COLORS="$WS_NEWT" whiptail --title " $title " --msgbox "$text" 0 66
    else
        printf '%s\n' "$text"
    fi
    ws_reset_term
}

# ---------- the full screen we sign our work with ----------
function ws_sign() {
    local text="$1"
    local kind="$2"
    if ! ws_tty || ! ws_skin_on; then
        printf '%s\n' "$text"
        return 0
    fi
    ws_head "$WS_TAG"
    ws_rule 46
    echo
    local tint="$WS_CYAN"
    local sign="\xe2\x9c\x93"
    if [ "$kind" = "bad" ]; then
        tint="$WS_ROSE"
        sign="\xe2\x9c\x97"
    fi
    printf '%s%s%s ' "$(ws_pad $((${#text} + 2)))" "$(ws_fg $tint)" "$(printf "$sign")"
    printf '%s%s%s\n' "$(ws_bold)" "$text" "$(ws_off)"
    echo
    ws_rule 46
    echo
    ws_reset_term
}

# ---------- our own home screen, keys and all ----------
function ws_menu() {
    ws_skin_on || return 2
    ws_tty || return 2
    local sub="$1"
    shift
    local keys=()
    local labels=()
    while [ "$#" -ge 2 ]; do
        keys+=("$1")
        labels+=("$2")
        shift 2
    done
    local n=${#keys[@]}
    [ "$n" -eq 0 ] && return 2
    local sel=0
    local k=""
    local rest=""
    local i=0
    WS_MENU_CHOICE=""
    printf '\033[?25l'
    while true; do
        ws_head "$sub"
        ws_rule 46
        echo
        i=0
        while [ "$i" -lt "$n" ]; do
            if [ "$i" -eq "$sel" ]; then
                printf '%s%s%s\xe2\x96\xb8 %-2s %-36s%s\n' "$(ws_pad 46)" "$(ws_bold)" "$(ws_fg $WS_CYAN)" "$((i + 1))" "${labels[$i]}" "$(ws_off)"
            else
                printf '%s%s  %-2s %-36s%s\n' "$(ws_pad 46)" "$(ws_fg $WS_MUTED)" "$((i + 1))" "${labels[$i]}" "$(ws_off)"
            fi
            i=$((i + 1))
        done
        echo
        ws_rule 46
        printf '%s%s%s%s\n' "$(ws_pad 46)" "$(ws_faint)" "  up down move    enter open    1-9 jump    q quit" "$(ws_off)"
        IFS= read -rsn1 k 2>/dev/null
        if [ "$?" -ne 0 ]; then
            printf '\033[?25h'
            return 2
        fi
        case "$k" in
        $'\033')
            IFS= read -rsn2 -t 0.06 rest 2>/dev/null
            case "$rest" in
            '[A') sel=$((sel - 1)) ;;
            '[B') sel=$((sel + 1)) ;;
            esac
            ;;
        k | K) sel=$((sel - 1)) ;;
        j | J) sel=$((sel + 1)) ;;
        '')
            WS_MENU_CHOICE="${keys[$sel]}"
            printf '\033[?25h'
            ws_reset_term
            return 0
            ;;
        q | Q)
            WS_MENU_CHOICE=""
            printf '\033[?25h'
            ws_reset_term
            return 1
            ;;
        [1-9])
            if [ "$k" -le "$n" ]; then
                WS_MENU_CHOICE="${keys[$((k - 1))]}"
                printf '\033[?25h'
                ws_reset_term
                return 0
            fi
            ;;
        esac
        [ "$sel" -lt 0 ] && sel=$((n - 1))
        [ "$sel" -ge "$n" ] && sel=0
    done
}

# ---------- the progress window during install and update ----------
function ws_progress_plain() {
    local log=""
    local args=()
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --title | --subtitle)
            shift
            [ "$#" -gt 0 ] && shift
            ;;
        --log)
            shift
            log="$1"
            [ "$#" -gt 0 ] && shift
            ;;
        *)
            args+=("$1")
            shift
            ;;
        esac
    done
    [ "${#args[@]}" -eq 0 ] && return 0
    if [ -n "$log" ]; then
        "${args[@]}" 2>&1 | tee -a "$log"
        return ${PIPESTATUS[0]}
    fi
    "${args[@]}"
}

function ws_progress_window() {
    local py=""
    local cand=""
    for cand in python3 python3.13 python3.12 python3.10 python; do
        if command -v "$cand" >/dev/null 2>&1; then
            py="$cand"
            break
        fi
    done
    local prog="/opt/hiddify-manager/common/watashi_progress.py"
    if [ ! -f "$prog" ]; then
        prog="$(dirname "${BASH_SOURCE[0]}")/watashi_progress.py"
    fi
    if [ -n "$py" ] && [ -f "$prog" ] && ws_skin_on; then
        "$py" "$prog" --title "$WS_BRAND" "$@"
        local code=$?
        ws_reset_term
        return $code
    fi
    ws_progress_plain "$@"
}
