#!/run/current-system/sw/bin/bash
# Liquid-glass palette, sourced by sketchybarrc and every plugin so colors live in
# one place. `source "$(dirname "$0")/theme.sh"` (rc) / "../theme.sh" (plugins).

# ── Raw template values ───────────────────────────────────────────────────────
BAR_COLOR=0x00000000       # transparent bar (relies on blur)
ACCENT=0xffffffff          # primary accent / on-glass text (white)
SECONDARY=0xffd6eaf8       # secondary accent (pale blue)
FOCUSED=0xff00f3ff         # focused-space highlight (glowing cyan)
DISABLED=0xff777777        # dimmed / inactive
GLASS_BG=0x20ffffff        # translucent pill background
GLASS_BORDER=0x40ffffff    # pill / bar border
POPUP_BG=0xee1a1d1e        # dark-glass popup background
POPUP_BORDER=0x80ffffff    # popup border

# ── Derived roles ─────────────────────────────────────────────────────────────
# On the translucent-white bar pills, text/icons are white (ACCENT); inside the
# dark popup they're light on dark.
BAR_TEXT="$ACCENT"
BAR_DIM="$DISABLED"
POPUP_TEXT=0xffe8eef2      # primary text in popup
POPUP_DIM=0xffa9b3bd       # secondary text in popup
POPUP_HEAD="$SECONDARY"    # section headers in popup
FOCUS_FG=0xff00171a        # dark text on the cyan focused-space pill
ZEBRA_A=0x00000000         # popup row shading (transparent / faint)
ZEBRA_B=0x14ffffff
