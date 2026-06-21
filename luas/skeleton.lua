--======================================================================
-- $$ banknote $$  -  custom lua skeleton / template
--
-- HOW TO USE
--   1. Copy this file into the banknote Luas folder on your executor:
--        workspace/banknote/ui/Luas/
--      (the folder is created automatically the first time banknote runs)
--   2. Rename it to whatever you want, e.g.  myfeature.lua
--   3. Edit the feature below. Re-inject banknote to load it.
--
-- It shows up automatically under the "lua" tab in the banknote UI, for
-- every game (next to the "settings" tab).
--
-- CONTRACT
--   The file MUST `return function(Library, Page) ... end`.
--   * Library = the banknote UI library (same one every feature uses).
--   * Page    = the "lua" page; create Section(s) on it and add elements.
--
-- IMPORTANT
--   * Every `Flag` must be UNIQUE across the whole menu. Prefix yours
--     (e.g. "mylua_...") so it never clashes with another lua or feature.
--   * We are not at fault if a lua you add is detected. Use with caution.
--======================================================================
return function(Library, Page)
    -- one box in the "lua" tab. Side = 1 (left column) or 2 (right column).
    local Section = Page:Section({ Name = "My Custom Lua", Side = 1 })

    -- feature state
    local enabled = false
    local speed   = 50
    local mode    = "A"
    local color   = Color3.fromRGB(255, 255, 255)

    -- Toggle (the main on/off). You can attach a keybind to it.
    local Enabled = Section:Toggle({
        Name = "Enabled",
        Flag = "mylua_enabled",
        Default = false,
        Callback = function(value)
            enabled = value
        end
    })
    Enabled:Keybind({
        Name = "Enabled",
        Flag = "mylua_enabled_key",
        Mode = "Toggle", -- Toggle / Hold / Always
        Callback = function(state)
            enabled = state
            if Enabled.Set then pcall(function() Enabled:Set(state) end) end
        end
    })

    -- Slider
    Section:Slider({
        Name = "Speed",
        Flag = "mylua_speed",
        Min = 1, Max = 100, Default = 50,
        Decimals = 1,            -- step size (1 = integers, 0.01 = hundredths)
        Suffix = " studs",
        Callback = function(value) speed = value end
    })

    -- Dropdown
    Section:Dropdown({
        Name = "Mode",
        Flag = "mylua_mode",
        Items = { "A", "B", "C" },
        Default = "A",
        Multi = false,
        Callback = function(value)
            if type(value) == "table" then value = value[1] end
            mode = value
        end
    })

    -- Colorpicker (attach to a Label)
    Section:Label({ Name = "Color" }):Colorpicker({
        Name = "Color",
        Flag = "mylua_color",
        Default = color,
        Callback = function(c) color = c end
    })

    -- Button
    Section:Button({
        Name = "Notify",
        Callback = function()
            Library:Notification("Hello from my custom lua!", 4, Library.Theme.Accent)
        end
    })

    --==================================================================
    -- your feature logic
    --==================================================================
    game:GetService("RunService").Heartbeat:Connect(function()
        if not enabled then return end
        -- do your thing here using `speed`, `mode`, `color`, ...
    end)
end
