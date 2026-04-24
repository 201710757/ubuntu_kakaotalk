#!/usr/bin/env bash
# KakaoTalk top-bar toggle for GNOME via Argos.
# Left-click the bar item to open the menu; menu items control KakaoTalk.

export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin"
LAUNCHER="$HOME/.local/bin/kakaotalk"
BAR_ICON="$HOME/.local/share/icons/hicolor/22x22/apps/kakaotalk.png"
MENU_ICON="$HOME/.local/share/icons/hicolor/256x256/apps/kakaotalk.png"

BAR_B64=$(base64 -w0 "$BAR_ICON" 2>/dev/null)
MENU_B64=$(base64 -w0 "$MENU_ICON" 2>/dev/null)

bar_line() {
    if [ -n "$BAR_B64" ]; then
        echo " | image='$BAR_B64' imageWidth=22 imageHeight=22"
    else
        echo "카톡"
    fi
}

menu_title() {
    local title="$1"
    if [ -n "$MENU_B64" ]; then
        echo "$title | image='$MENU_B64' imageWidth=16 imageHeight=16"
    else
        echo "$title"
    fi
}

if pgrep -x KakaoTalk.exe >/dev/null 2>&1; then
    # Running → menu offers focus / restart / quit.
    bar_line
    echo "---"
    menu_title "카카오톡 · 실행 중"
    echo "---"
    echo "창 포커스 | bash='\"$LAUNCHER\"' terminal=false"
    echo "재시작 (검정화면 복구) | bash='\"$LAUNCHER\" --restart' terminal=false"
    echo "종료 | bash='\"$LAUNCHER\" --quit' terminal=false refresh=true"
else
    # Stopped → menu offers start only.
    bar_line
    echo "---"
    menu_title "카카오톡 · 중지"
    echo "---"
    echo "실행 | bash='\"$LAUNCHER\"' terminal=false refresh=true"
fi
