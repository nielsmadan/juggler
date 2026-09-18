on run arguments
    set action to item 1 of arguments
    if action is "rows" then
        tell application "System Events" to tell process "Juggler"
            tell group 1 of window "Juggler"
                if exists scroll area 1 then
                    return value of every static text of UI element 1 of scroll area 1
                else
                    return value of every static text
                end if
            end tell
        end tell
    else if action is "next" or action is "previous" then
        tell application "System Events" to tell process "iTerm2" to set frontmost to true
        if action is "next" then
            tell application "System Events" to keystroke "j" using {command down, shift down}
        else
            tell application "System Events" to keystroke "k" using {command down, shift down}
        end if
    else
        error "Expected rows, next, or previous"
    end if
end run
