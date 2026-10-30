on run arguments
    set action to item 1 of arguments
    if action is "rows" then
        tell application "System Events" to tell process "Juggler"
            tell group 1 of window "Juggler"
                if not (exists scroll area 1) then return value of every static text
                set texts to {}
                repeat with element in (entire contents of scroll area 1 as list)
                    try
                        if class of element is static text then set end of texts to value of element
                    end try
                end repeat
                return texts
            end tell
        end tell
    else if action is "next" or action is "previous" then
        tell application "System Events" to tell process "iTerm2" to set frontmost to true
        if action is "next" then
            tell application "System Events" to keystroke "j" using {command down, shift down}
        else
            tell application "System Events" to keystroke "k" using {command down, shift down}
        end if
    else if action is "resize" then
        tell application "System Events" to tell process "Juggler"
            set frontmost to true
            set size of window "Juggler" to {(item 2 of arguments) as integer, (item 3 of arguments) as integer}
            return size of window "Juggler"
        end tell
    else if action is "down" or action is "up" then
        tell application "System Events" to tell process "Juggler"
            set frontmost to true
            if action is "down" then
                key code 125
            else
                key code 126
            end if
        end tell
    else
        error "Expected rows, next, previous, resize WIDTH HEIGHT, down, or up"
    end if
end run
