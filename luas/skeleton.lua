--======================================================================
-- $$ banknote $$  -  custom lua skeleton / template
--
-- HOW TO USE
--   1. Copy this file into the banknote Luas folder on your executor:
--        workspace/banknote/ui/Luas/
--      (banknote shows the exact path as a notification + on the "lua" tab)
--   2. Rename it, e.g.  myfeature.lua, and edit the feature below.
--   3. In game, open the "lua" tab, press "Refresh list", tick your lua(s)
--      in the dropdown, then press "Load selected".
--
-- WHERE IT SHOWS UP
--   Your feature is placed in the tab named by `Category` (e.g. "Combat",
--   "Misc", "Visuals", "Movement"...). If that tab doesn't exist yet it is
--   created. It does NOT show in the "lua" tab itself.
--
-- CONTRACT
--   The file MUST return a table:
--     {
--        Name     = "...",      -- (optional) display name
--        Category = "Misc",     -- tab to place it in
--        Build    = function(Library, Page) ... end
--     }
--   Build receives the banknote Library and the target Page; create a
--   Section on the Page and add elements with the normal UI library API.
--
-- IMPORTANT
--   * Every `Flag` must be UNIQUE across the whole menu. Prefix yours
--     (e.g. "mylua_...") so it never clashes with another lua or feature.
--   * We are not at fault if a lua you add is detected. Use with caution.
--======================================================================
return {
    Name = "My Custom Lua",
    Category = "Misc", -- Combat / Misc / Visuals / Movement / ... (your choice)

    Build = function(Library, Page)
        -- one box in the chosen tab. Side = 1 (left column) or 2 (right).
        local Section = Page:Section({ Name = "My Custom Lua", Side = 1 })

        -- feature state
        local enabled = false
        local speed   = 50
        local mode    = "A"
        local color   = Color3.fromRGB(255, 255, 255)

        -- Toggle (+ optional keybind)
        local Enabled = Section:Toggle({
            Name = "Enabled",
            Flag = "mylua_enabled",
            Default = false,
            Callback = function(value) enabled = value end
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

        --==============================================================
        -- your feature logic
        --==============================================================
        local conn = game:GetService("RunService").Heartbeat:Connect(function()
            if not enabled then return end
            -- do your thing using `speed`, `mode`, `color`, ...
        end)

        -- OPTIONAL: return a cleanup function. "Unload selected" in the lua
        -- tab destroys your UI automatically, and ALSO calls this so your
        -- connections/loops stop. Without it, only the UI is removed.
        return function()
            conn:Disconnect()
        end
    end
}
