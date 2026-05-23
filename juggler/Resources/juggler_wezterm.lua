-- Juggler integration for WezTerm.
-- Posts focus events to Juggler and styles tab titles based on a user var.
--
-- To install manually: require this file from your wezterm.lua
--     require 'juggler_wezterm'
--
-- Juggler's installer adds the require line automatically (idempotent).

local wezterm = require 'wezterm'

local JUGGLER_PORT = 7483
local JUGGLER_URL = 'http://localhost:' .. JUGGLER_PORT .. '/wezterm-event'

local function post_event(event, pane_id)
    local payload = string.format('{"event":"%s","pane_id":"%s"}', event, pane_id)
    wezterm.background_child_process({
        'curl', '-s', '-X', 'POST', JUGGLER_URL,
        '-H', 'Content-Type: application/json',
        '-d', payload,
        '--connect-timeout', '1',
    })
end

wezterm.on('window-focus-changed', function(window, pane)
    if window:is_focused() and pane then
        post_event('focus_changed', tostring(pane:pane_id()))
    end
end)

wezterm.on('format-tab-title', function(tab, _tabs, _panes, _config, _hover, _max_width)
    local pane = tab.active_pane
    local color = pane and pane.user_vars and pane.user_vars.juggler_color
    if color and color ~= '' then
        return {
            { Background = { Color = '#' .. color } },
            { Text = ' ' .. (tab.active_pane.title or '') .. ' ' },
        }
    end
    return nil
end)

return {}
