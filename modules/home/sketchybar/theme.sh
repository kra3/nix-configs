#!/run/current-system/sw/bin/bash
# Sketchybar theme palette. Switch the whole bar by changing THEME below (or set
# SKETCHYBAR_THEME in the environment). Every color the config uses is a role
# variable defined per theme, so scripts reference roles, never raw hexes.
#   Roles: BAR_COLOR PILL_BG PILL_BORDER BAR_TEXT ACCENT GLYPH FOCUSED FOCUS_FG
#          DISABLED POPUP_BG POPUP_BORDER POPUP_TEXT POPUP_DIM POPUP_HEAD
#          SECONDARY ZEBRA_A ZEBRA_B

THEME="${SKETCHYBAR_THEME:-liquid_glass}" # liquid_glass | catppuccin

case "$THEME" in
    catppuccin) # Catppuccin Mocha — dark, opaque-ish
        BAR_COLOR=0x991e1e2e   # base, translucent
        PILL_BG=0xcc11111b     # crust glass group-pill
        PILL_BORDER=0x22cdd6f4 # bar + pill border
        BAR_TEXT=0xffcdd6f4    # text on the bar
        ACCENT=0xff89b4fa      # blue — space number
        GLYPH=0xffa6adc8       # subtext — window app-glyphs
        SECONDARY=0xff89b4fa   # blue — links / "+N more" / webex glyph
        FOCUSED=0xff89b4fa     # focused-space pill (blue)
        FOCUS_FG=0xff1e1e2e    # text on the focused pill
        DISABLED=0xff6c7086    # overlay — muted
        POPUP_BG=0xdd11111b
        POPUP_BORDER=0x33cdd6f4
        POPUP_TEXT=0xffcdd6f4
        POPUP_DIM=0xffa6adc8
        POPUP_HEAD=0xfff9e2af  # yellow section headers
        HEADER_BG=0x22313244   # popup section-header row background
        OK=0xffa6e3a1          # status: good (green)
        WARN=0xfff9e2af        # status: warning (yellow)
        CRIT=0xfff38ba8        # status: critical (red)
        ZEBRA_A=0x00000000
        ZEBRA_B=0x11ffffff
        ;;
    liquid_glass | *) # translucent glass — white/cyan on blur
        BAR_COLOR=0x00000000   # transparent (relies on blur)
        PILL_BG=0x20ffffff     # translucent-white group-pill
        PILL_BORDER=0x40ffffff
        BAR_TEXT=0xffffffff    # white text on the bar
        ACCENT=0xffffffff      # white — space number
        GLYPH=0xffd6eaf8       # pale blue — window app-glyphs
        SECONDARY=0xffd6eaf8   # pale blue — links / "+N more" / webex glyph
        FOCUSED=0xff00f3ff     # glowing cyan focused-space pill
        FOCUS_FG=0xff00171a    # dark text on the cyan pill
        DISABLED=0xff777777
        POPUP_BG=0xee1a1d1e    # dark-glass popup
        POPUP_BORDER=0x80ffffff
        POPUP_TEXT=0xffe8eef2
        POPUP_DIM=0xffa9b3bd
        POPUP_HEAD=0xffd6eaf8
        HEADER_BG=0x22ffffff   # translucent-white section-header row
        OK=0xffa6e3a1          # status: good (green)
        WARN=0xfff9e2af        # status: warning (yellow)
        CRIT=0xfff38ba8        # status: critical (red)
        ZEBRA_A=0x00000000
        ZEBRA_B=0x14ffffff
        ;;
esac
