#!/run/current-system/sw/bin/bash
# Single-pass workspace updater (AeroSpace): refreshes all space.* items in one
# sketchybar call. $1 = accent color.
export PATH="/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
source "$(dirname "$0")/../theme.sh"

COLOR="${1:-$ACCENT}"          # space number (icon) — white accent
GLYPH="${2:-$GLYPH}"           # window app-glyphs (label)
PERSISTENT=" 1 2 3 "
# front_app_switched/display_change/manual runs don't pass it — resolve it.
FOCUSED_WORKSPACE="${FOCUSED_WORKSPACE:-$(aerospace list-workspaces --focused 2>/dev/null)}"

# App name → Nerd Font glyph as explicit UTF-8 bytes (FontAwesome range).
__icon() {
    case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
        *ghostty* | *terminal* | *iterm* | *alacritty* | *kitty* | *wezterm*) printf '\xef\x84\xa0' ;; # terminal
        *safari*) printf '\xef\x89\xa7' ;;                                                             # safari
        *chrome* | *chromium* | *brave* | *edge*) printf '\xef\x89\xa8' ;;                             # chrome
        *firefox*) printf '\xef\x89\xa9' ;;                                                            # firefox
        *arc*) printf '\xef\x82\xac' ;;                                                                # globe
        *xcode*) printf '\xef\x85\xb9' ;;                                                              # apple
        *code* | *cursor* | *sublime* | *zed* | *nova*) printf '\xef\x84\xa1' ;;                       # code
        *finder*) printf '\xef\x81\xbb' ;;                                                             # folder
        *mail* | *outlook* | *spark*) printf '\xef\x83\xa0' ;;                                         # envelope
        *slack*) printf '\xef\x86\x98' ;;                                                              # slack
        *message* | *whatsapp* | *telegram* | *signal*) printf '\xef\x82\x86' ;;                       # comments
        *calendar* | *fantastical*) printf '\xef\x81\xb3' ;;                                           # calendar
        *spotify*) printf '\xef\x86\xbc' ;;                                                            # spotify
        *music*) printf '\xef\x80\x81' ;;                                                              # music
        *note* | *obsidian* | *bear*) printf '\xef\x89\x89' ;;                                         # sticky-note
        *zoom* | *webex* | *facetime* | *teams*) printf '\xef\x80\xbd' ;;                              # video-camera
        *intellij* | *pycharm* | *goland* | *webstorm* | *idea* | *"android studio"*) printf '\xef\x83\xb4' ;; # coffee
        *preview* | *pdf* | *acrobat*) printf '\xef\x87\x81' ;;                                        # file-pdf
        *setting* | *preference*) printf '\xef\x80\x93' ;;                                             # cog
        *docker*) printf '\xef\x86\xb2' ;;                                                             # cube
        *) printf '\xef\x8b\x90' ;;                                                                    # window (default)
    esac
}

# One call: all windows grouped by workspace (dedupe apps per workspace).
declare -A APPS SEEN DISP MON
while IFS='|' read -r ws app; do
    [ -n "$ws" ] || continue
    case " ${SEEN[$ws]-} " in *" $app "*) continue ;; esac
    SEEN[$ws]+=" $app "
    APPS[$ws]+="$(__icon "$app") "
done < <(aerospace list-windows --all --format '%{workspace}|%{app-name}' 2>/dev/null)

# Workspace → monitor-id + sketchybar display (NSScreen order).
while IFS='|' read -r ws mon ns; do
    [ -n "$ws" ] || continue
    MON[$ws]="$mon"; DISP[$ws]="$ns"
done < <(aerospace list-workspaces --all --format '%{workspace}|%{monitor-id}|%{monitor-appkit-nsscreen-screens-id}' 2>/dev/null)

# Visible (focused) workspace per monitor.
declare -A VIS
for m in $(printf '%s\n' "${MON[@]}" | sort -u); do
    [ -n "$m" ] || continue
    VIS[$m]="$(aerospace list-workspaces --monitor "$m" --visible --format '%{workspace}' 2>/dev/null)"
done

ARGS=()
for sid in 1 2 3 4 5 6 7 8 9; do
    disp="${DISP[$sid]:-1}"; mon="${MON[$sid]}"; glyphs="${APPS[$sid]}"; glyphs="${glyphs% }"
    if [ -n "$mon" ]; then focus="${VIS[$mon]:-$FOCUSED_WORKSPACE}"; else focus="$FOCUSED_WORKSPACE"; fi
    if [ -z "$glyphs" ] && [[ "$PERSISTENT" != *" $sid "* ]] && [ "$sid" != "$focus" ]; then
        ARGS+=(--set "space.$sid" drawing=off)
        continue
    fi
    if [ "$sid" = "$focus" ]; then
        ARGS+=(--animate tanh 12 --set "space.$sid" drawing=on display="$disp"
            background.drawing=on background.color="$FOCUSED"
            icon.color="$FOCUS_FG" label.color="$FOCUS_FG" label="$glyphs")
    else
        ARGS+=(--animate tanh 12 --set "space.$sid" drawing=on display="$disp"
            background.drawing=off icon.color="$COLOR" label.color="$GLYPH" label="$glyphs")
    fi
done
sketchybar "${ARGS[@]}"
