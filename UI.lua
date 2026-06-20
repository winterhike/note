--[[
    UI Builder - $$ banknote $$
    Dynamically builds the UI from a game config table.
    This file is loaded by loader.lua and receives game-specific features.
]]

local UI = {}

function UI:Build(Config, Library, placeName)
    local windowTitle = "$$ banknote: " .. (placeName or "Unknown") .. " $$"
    local Window = Library:Window({Name = windowTitle})
    local Watermark = Window:Watermark({Name = "$$ banknote $$"})
    local KeybindList = Window:KeybindList()

    -- Global flags table for logic scripts to read
    getgenv().BanknoteFlags = getgenv().BanknoteFlags or {}
    getgenv().BanknoteButtonHandlers = getgenv().BanknoteButtonHandlers or {}

    -- Helper to set default flag values
    local function setDefaultFlag(flag, value)
        if flag and value ~= nil then
            getgenv().BanknoteFlags[flag] = value
        end
    end

    --==================================================================
    -- Detection markers + hover tooltips
    --==================================================================
    local UISvc = game:GetService("UserInputService")
    local RunSvc = game:GetService("RunService")

    local tooltipGui = Instance.new("ScreenGui")
    tooltipGui.Name = "BanknoteTooltips"
    tooltipGui.ResetOnSpawn = false
    tooltipGui.IgnoreGuiInset = true
    tooltipGui.DisplayOrder = 2147483647
    tooltipGui.Parent = (gethui and gethui()) or game:GetService("CoreGui")

    local ttFrame = Instance.new("Frame")
    ttFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
    ttFrame.BorderSizePixel = 0
    ttFrame.Visible = false
    ttFrame.Size = UDim2.fromOffset(250, 46)
    ttFrame.ZIndex = 1000
    ttFrame.Parent = tooltipGui
    local ttStroke = Instance.new("UIStroke")
    ttStroke.Color = Color3.fromRGB(0, 0, 0)
    ttStroke.Thickness = 1
    ttStroke.Parent = ttFrame
    local ttPad = Instance.new("UIPadding")
    ttPad.PaddingLeft = UDim.new(0, 6); ttPad.PaddingRight = UDim.new(0, 6)
    ttPad.PaddingTop = UDim.new(0, 4); ttPad.PaddingBottom = UDim.new(0, 4)
    ttPad.Parent = ttFrame
    local ttLabel = Instance.new("TextLabel")
    ttLabel.BackgroundTransparency = 1
    ttLabel.Size = UDim2.new(1, 0, 1, 0)
    ttLabel.TextWrapped = true
    ttLabel.Font = Enum.Font.Code
    ttLabel.TextSize = 13
    ttLabel.TextColor3 = Color3.fromRGB(235, 235, 235)
    ttLabel.TextXAlignment = Enum.TextXAlignment.Left
    ttLabel.TextYAlignment = Enum.TextYAlignment.Center
    ttLabel.ZIndex = 1001
    ttLabel.Parent = ttFrame

    local ttConn
    local function showTooltip(msg)
        ttLabel.Text = msg
        ttFrame.Size = UDim2.fromOffset(250, 46)
        ttFrame.Visible = true
        if ttConn then ttConn:Disconnect() end
        ttConn = RunSvc.RenderStepped:Connect(function()
            local m = UISvc:GetMouseLocation()
            ttFrame.Position = UDim2.fromOffset(m.X + 16, m.Y + 10)
        end)
    end
    local function hideTooltip()
        ttFrame.Visible = false
        if ttConn then ttConn:Disconnect(); ttConn = nil end
    end

    -- Appends a red "DETECTED (?)/(!)" marker to an element and shows a
    -- warning tooltip on hover. detection = "warn" (?) or "detected" (!)
    local function applyDetection(obj, detection)
        local mark, msg
        if detection == "detected" then
            mark = "(!)"
            msg = "this feature is detected, seen from our tests, use it with caution."
        else
            mark = "(?)"
            msg = "this feature potentially may be detected, use it with caution."
        end
        local label = obj and obj.Items and obj.Items["Text"] and obj.Items["Text"].Instance
        if not label then return end
        label.RichText = true
        label.Text = label.Text .. '  <font color="rgb(255,55,55)">DETECTED ' .. mark .. '</font>'
        label.MouseEnter:Connect(function() showTooltip(msg) end)
        label.MouseLeave:Connect(function() hideTooltip() end)
    end

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
                    setDefaultFlag(element.Flag, element.Default or false)
                    local tgl = Section:Toggle({
                        Name = element.Name,
                        Flag = element.Flag,
                        Default = element.Default or false,
                        Callback = element.Callback or function(v)
                            getgenv().BanknoteFlags[element.Flag] = v
                        end
                    })
                    if element.Detection then applyDetection(tgl, element.Detection) end

                elseif elemType == "Button" then
                    local btn = Section:Button({
                        Name = element.Name,
                        Callback = element.Callback or function()
                            local h = getgenv().BanknoteButtonHandlers
                            if h and element.Flag and h[element.Flag] then
                                pcall(h[element.Flag])
                            end
                        end
                    })
                    if element.Detection then applyDetection(btn, element.Detection) end

                elseif elemType == "Slider" then
                    setDefaultFlag(element.Flag, element.Default or 0)
                    local sld = Section:Slider({
                        Name = element.Name,
                        Flag = element.Flag,
                        Min = element.Min or 0,
                        Max = element.Max or 100,
                        Default = element.Default or 0,
                        Decimals = element.Decimals or 1,
                        Suffix = element.Suffix or "",
                        Callback = element.Callback or function(value)
                            getgenv().BanknoteFlags[element.Flag] = value
                        end
                    })
                    if element.Detection then applyDetection(sld, element.Detection) end

                elseif elemType == "Dropdown" then
                    setDefaultFlag(element.Flag, element.Default or "")
                    local dd = Section:Dropdown({
                        Name = element.Name,
                        Flag = element.Flag,
                        Items = element.Items or {},
                        Default = element.Default or "",
                        Multi = element.Multi or false,
                        Callback = element.Callback or function(value)
                            getgenv().BanknoteFlags[element.Flag] = value
                        end
                    })
                    if element.Detection then applyDetection(dd, element.Detection) end

                elseif elemType == "Textbox" then
                    Section:Textbox({
                        Name = element.Name,
                        Flag = element.Flag,
                        Default = element.Default or "",
                        Placeholder = element.Placeholder or "",
                        Numeric = element.Numeric or false,
                        Finished = element.Finished or false,
                        Callback = element.Callback or function(value)
                            getgenv().BanknoteFlags[element.Flag] = value
                        end
                    })

                elseif elemType == "Label" then
                    local label = Section:Label({Name = element.Name})

                    -- Labels can have attached colorpickers or keybinds
                    if element.Colorpicker then
                        label:Colorpicker({
                            Name = element.Colorpicker.Name,
                            Flag = element.Colorpicker.Flag,
                            Default = element.Colorpicker.Default or Color3.fromRGB(255, 255, 255),
                            Callback = element.Colorpicker.Callback or function(value, alpha)
                                getgenv().BanknoteFlags[element.Colorpicker.Flag] = value
                            end
                        })
                    end

                    if element.Keybind then
                        label:Keybind({
                            Name = element.Keybind.Name,
                            Flag = element.Keybind.Flag,
                            Default = element.Keybind.Default or Enum.KeyCode.E,
                            Mode = element.Keybind.Mode or "Toggle",
                            Callback = element.Keybind.Callback or function(value)
                                getgenv().BanknoteFlags[element.Keybind.Flag] = value
                            end
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
