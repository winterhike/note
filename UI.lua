--[[
    UI Builder - $$ banknote $$
    Dynamically builds the UI from a game config table.
    This file is loaded by loader.lua and receives game-specific features.
]]

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/sametexe001/juanitahaxx/refs/heads/main/Library.lua"))()

local UI = {}

function UI:Build(Config)
    local Window = Library:Window({Name = "$$ banknote $$"})
    local Watermark = Window:Watermark({Name = "$$ banknote $$"})
    local KeybindList = Window:KeybindList()

    -- Iterate through each page defined in the config
    for _, pageData in ipairs(Config.Pages) do
        local Page = Window:Page({Name = pageData.Name})

        -- Iterate through each section in the page
        for _, sectionData in ipairs(pageData.Sections) do
            local Section = Page:Section({Name = sectionData.Name, Side = sectionData.Side})

            -- Iterate through each element in the section
            for _, element in ipairs(sectionData.Elements) do
                local elemType = element.Type

                if elemType == "Toggle" then
                    Section:Toggle({
                        Name = element.Name,
                        Flag = element.Flag,
                        Default = element.Default or false,
                        Callback = element.Callback or function(v) end
                    })

                elseif elemType == "Button" then
                    Section:Button({
                        Name = element.Name,
                        Callback = element.Callback or function() end
                    })

                elseif elemType == "Slider" then
                    Section:Slider({
                        Name = element.Name,
                        Flag = element.Flag,
                        Min = element.Min or 0,
                        Max = element.Max or 100,
                        Default = element.Default or 0,
                        Decimals = element.Decimals or 1,
                        Suffix = element.Suffix or "",
                        Callback = element.Callback or function(value) end
                    })

                elseif elemType == "Dropdown" then
                    Section:Dropdown({
                        Name = element.Name,
                        Flag = element.Flag,
                        Items = element.Items or {},
                        Default = element.Default or "",
                        Multi = element.Multi or false,
                        Callback = element.Callback or function(value) end
                    })

                elseif elemType == "Textbox" then
                    Section:Textbox({
                        Name = element.Name,
                        Flag = element.Flag,
                        Default = element.Default or "",
                        Placeholder = element.Placeholder or "",
                        Numeric = element.Numeric or false,
                        Finished = element.Finished or false,
                        Callback = element.Callback or function(value) end
                    })

                elseif elemType == "Label" then
                    local label = Section:Label({Name = element.Name})

                    -- Labels can have attached colorpickers or keybinds
                    if element.Colorpicker then
                        label:Colorpicker({
                            Name = element.Colorpicker.Name,
                            Flag = element.Colorpicker.Flag,
                            Default = element.Colorpicker.Default or Color3.fromRGB(255, 255, 255),
                            Callback = element.Colorpicker.Callback or function(value, alpha) end
                        })
                    end

                    if element.Keybind then
                        label:Keybind({
                            Name = element.Keybind.Name,
                            Flag = element.Keybind.Flag,
                            Default = element.Keybind.Default or Enum.KeyCode.E,
                            Mode = element.Keybind.Mode or "Toggle",
                            Callback = element.Keybind.Callback or function(value) end
                        })
                    end
                end
            end
        end
    end

    -- Watermark FPS/Time
    do
        local FpsText = Watermark:Add("FPS: ")
        local DateTimeText = Watermark:Add("")

        local FPS = 0
        local FrameCount = 0
        local Elapsed = 0

        Library:Connect(game:GetService("RunService").RenderStepped, function(DeltaT)
            FrameCount += 1
            Elapsed += DeltaT

            if Elapsed >= 1 then
                FPS = math.floor(FrameCount / Elapsed)
                FpsText:SetText("FPS: " .. FPS)
                FrameCount = 0
                Elapsed = 0
            end

            DateTimeText:SetText(os.date("%H:%M:%S %d/%m/%Y"))
        end)
    end

    Window:Init()
end

return UI
