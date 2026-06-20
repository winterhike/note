--======================================================================
-- $$ banknote $$ COMPATIBILITY SHIM
-- Returns a Library object that implements Instance.lua's UI API
-- (AddToggle/AddSlider/AddDropdown/AddColorPicker/AddKeyPicker/AddInput/
--  AddButton/AddDependencyBox/Tabboxes/Groupboxes/Toggles/Options) on top
-- of the juanitahaxx banknote library, so the entire Instance.lua feature
-- logic can run unchanged and render through the banknote UI.
--
-- Usage (inside the Rivals logic file): replace
--     local Library = loadInstanceLibrary()
-- with
--     local Library = loadstring(game:HttpGet(BASE_URL.."games/logic/shim.lua"))()
-- (getgenv().BanknoteLibrary must be set by loader.lua first.)
--======================================================================
return (function()
    local UIS = game:GetService("UserInputService")
    local RunService = game:GetService("RunService")
    local TextService = game:GetService("TextService")
    local CoreGui = game:GetService("CoreGui")

    local BN = getgenv().BanknoteLibrary
    assert(BN, "[banknote] BanknoteLibrary not set by loader")

    local Toggles = {}
    local Options = {}
    getgenv().Toggles = Toggles
    getgenv().Options = Options

    local guiParent = (gethui and gethui()) or CoreGui
    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "\0banknote_shim"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.IgnoreGuiInset = true
    ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
    ScreenGui.DisplayOrder = 2147483646
    ScreenGui.Parent = guiParent

    local Lib = {
        Registry = {}, RegistryMap = {}, HudRegistry = {}, Signals = {},
        ScreenGui = ScreenGui,
        FontColor = Color3.fromRGB(255, 255, 255),
        MainColor = Color3.fromRGB(28, 28, 28),
        BackgroundColor = Color3.fromRGB(20, 20, 20),
        AccentColor = Color3.fromRGB(0, 200, 255),
        OutlineColor = Color3.fromRGB(50, 50, 50),
        RiskColor = Color3.fromRGB(255, 50, 50),
        Black = Color3.new(0, 0, 0),
        Font = Enum.Font.Code,
        OpenedFrames = {}, DependencyBoxes = {}, Flags = {},
        Unloaded = false, MinValueChange = 0.05, NotifyOnError = false,
    }
    local KeybindFrame = Instance.new("Frame")
    KeybindFrame.Visible = false
    KeybindFrame.BackgroundTransparency = 1
    KeybindFrame.Parent = ScreenGui
    Lib.KeybindFrame = KeybindFrame

    function Lib:Round(v, d) local m = 10 ^ (d or 0) return math.floor(tonumber(v) * m + 0.5) / m end
    function Lib:MapValue(V, mnA, mxA, mnB, mxB) return (1 - ((V - mnA) / (mxA - mnA))) * mnB + ((V - mnA) / (mxA - mnA)) * mxB end
    function Lib:GetDarkerColor(C) local H, S, V = Color3.toHSV(C) return Color3.fromHSV(H, S, V / 1.5) end
    Lib.AccentColorDark = Lib:GetDarkerColor(Lib.AccentColor)
    function Lib:GetTextBounds(Text, Font, Size, Res)
        local f = Font; if typeof(Font) == "Font" then f = Enum.Font.Code end
        local b = TextService:GetTextSize(Text, Size, f, Res or Vector2.new(1920, 1080))
        return b.X, b.Y
    end
    function Lib:Create(Class, Props)
        local inst = type(Class) == "string" and Instance.new(Class) or Class
        for p, v in next, Props do
            if p == "Font" then
                if typeof(v) == "Font" then inst.FontFace = v elseif typeof(v) == "EnumItem" then inst.Font = v end
            else inst[p] = v end
        end
        return inst
    end
    function Lib:ApplyTextStroke(inst)
        inst.TextStrokeTransparency = 1
        Lib:Create("UIStroke", { Color = Color3.new(0,0,0), Thickness = 1, LineJoinMode = Enum.LineJoinMode.Miter, Parent = inst })
    end
    function Lib:AddToRegistry(inst, props, isHud)
        local d = { Instance = inst, Properties = props }
        table.insert(Lib.Registry, d); Lib.RegistryMap[inst] = d
        if isHud then table.insert(Lib.HudRegistry, d) end
    end
    function Lib:RemoveFromRegistry(inst)
        local d = Lib.RegistryMap[inst]
        if d then
            for i = #Lib.Registry, 1, -1 do if Lib.Registry[i] == d then table.remove(Lib.Registry, i) end end
            for i = #Lib.HudRegistry, 1, -1 do if Lib.HudRegistry[i] == d then table.remove(Lib.HudRegistry, i) end end
            Lib.RegistryMap[inst] = nil
        end
    end
    function Lib:UpdateColorsUsingRegistry()
        for _, o in next, Lib.Registry do
            for p, idx in next, o.Properties do
                if type(idx) == "string" then o.Instance[p] = Lib[idx]
                elseif type(idx) == "function" then o.Instance[p] = idx() end
            end
        end
    end
    function Lib:CreateLabel(Props, IsHud)
        local inst = Lib:Create("TextLabel", { BackgroundTransparency = 1, Font = Lib.Font, TextColor3 = Lib.FontColor, TextSize = 16, TextStrokeTransparency = 0 })
        Lib:ApplyTextStroke(inst)
        Lib:AddToRegistry(inst, { TextColor3 = "FontColor" }, IsHud)
        return Lib:Create(inst, Props)
    end
    function Lib:MakeDraggable(inst) inst.Active = true; inst.Draggable = true end
    function Lib:Thread(fn) return task.spawn(fn) end
    function Lib:SafeCall(fn, ...) local r = { pcall(fn, ...) } local ok = table.remove(r, 1) return ok, table.unpack(r) end
    function Lib:SafeCallback(fn, ...) if not fn then return end return fn(...) end
    function Lib:GiveSignal(s) table.insert(Lib.Signals, s) end
    function Lib:OnUnload(cb) Lib.OnUnloadCb = cb end
    function Lib:Unload()
        for i = #Lib.Signals, 1, -1 do local c = table.remove(Lib.Signals, i) pcall(function() c:Disconnect() end) end
        if Lib.OnUnloadCb then pcall(Lib.OnUnloadCb) end
        Lib.Unloaded = true; pcall(function() ScreenGui:Destroy() end)
    end
    function Lib:UpdateDependencyBoxes()
        for _, dep in next, Lib.DependencyBoxes do if dep.Update then pcall(function() dep:Update() end) end end
    end
    function Lib:Notify(text, dur, color) pcall(function() BN:Notification(tostring(text), dur or 3, color or Lib.AccentColor) end) end
    function Lib:SetWatermark(text)
        Lib._watermarkText = tostring(text)
        if Lib._watermarkObj and Lib._watermarkObj.SetText then pcall(function() Lib._watermarkObj:SetText(tostring(text)) end) end
    end
    function Lib:SetWatermarkVisibility() end
    function Lib:MouseIsOverOpenedFrame() return false end

    local function makeObj(typeName, idx, default, callback)
        local obj = { Type = typeName, Value = default, Flag = idx, Callback = callback, _changed = {} }
        function obj:OnChanged(fn) table.insert(self._changed, fn) end
        function obj:_fire()
            if self.Callback then pcall(self.Callback, self.Value) end
            for _, fn in ipairs(self._changed) do pcall(fn, self.Value) end
        end
        function obj:SetText(t) if self._bn and self._bn.SetText then pcall(function() self._bn:SetText(t) end) end end
        function obj:SetVisibility() end
        return obj
    end

    local keyPickers = {}
    local function parseKey(key)
        if not key or key == "None" or key == "" then return nil end
        local s = tostring(key):gsub("Enum%.KeyCode%.", ""):gsub("Enum%.UserInputType%.", "")
        if Enum.KeyCode[s] then return Enum.KeyCode[s] end
        if Enum.UserInputType[s] then return Enum.UserInputType[s] end
        return nil
    end
    UIS.InputBegan:Connect(function(input)
        for _, kp in ipairs(keyPickers) do
            local k = parseKey(kp.Value)
            if k and (input.KeyCode == k or input.UserInputType == k) then
                if kp.Mode == "Toggle" then
                    kp._state = not kp._state
                    if kp.Callback then pcall(kp.Callback, kp._state) end
                    for _, fn in ipairs(kp._changed) do pcall(fn, kp._state) end
                elseif kp.Mode == "Hold" then
                    kp._state = true
                    if kp.Callback then pcall(kp.Callback, true) end
                end
            end
        end
    end)
    UIS.InputEnded:Connect(function(input)
        for _, kp in ipairs(keyPickers) do
            local k = parseKey(kp.Value)
            if k and (input.KeyCode == k or input.UserInputType == k) then
                if kp.Mode == "Hold" then
                    kp._state = false
                    if kp.Callback then pcall(kp.Callback, false) end
                end
            end
        end
    end)

    local function attachColorPicker(parentObj, section, idx, info)
        info = info or {}
        local obj = makeObj("ColorPicker", idx, info.Default or Color3.fromRGB(255,255,255), info.Callback)
        obj.Title = info.Title or "color"; Options[idx] = obj
        local bn = section.__cur
        if bn and bn.Colorpicker then
            obj._bn = bn:Colorpicker({ Name = obj.Title, Flag = "bn_" .. tostring(idx), Default = obj.Value,
                Callback = function(v) obj.Value = v; obj:_fire() end })
        end
        function obj:Set(c) self.Value = c; if self._bn and self._bn.Set then pcall(function() self._bn:Set(c) end) end; self:_fire() end
        return parentObj
    end
    local function attachKeyPicker(parentObj, section, idx, info)
        info = info or {}
        local obj = makeObj("KeyPicker", idx, info.Default or "None", info.Callback)
        obj.Mode = info.Mode or "Toggle"; obj.Modes = info.Modes; obj._state = false
        function obj:GetState() return self._state end
        function obj:Set(k) self.Value = tostring(k) end
        Options[idx] = obj; table.insert(keyPickers, obj)
        return parentObj
    end
    local function wrapElement(section, baseObj)
        local w = { __obj = baseObj }
        function w:AddColorPicker(idx, info) return attachColorPicker(self, section, idx, info) end
        function w:AddKeyPicker(idx, info) return attachKeyPicker(self, section, idx, info) end
        function w:OnChanged(fn) if baseObj then baseObj:OnChanged(fn) end return self end
        function w:SetValue(v) if baseObj and baseObj.Set then baseObj:Set(v) end return self end
        function w:SetText(t) if baseObj and baseObj.SetText then baseObj:SetText(t) end return self end
        return w
    end

    local function makeSection(bnSection)
        local sec = { __bn = bnSection, __cur = nil }
        function sec:AddToggle(idx, info)
            info = info or {}
            local obj = makeObj("Toggle", idx, info.Default or false, info.Callback)
            Toggles[idx] = obj
            obj._bn = bnSection:Toggle({ Name = info.Text or tostring(idx), Flag = "bn_" .. tostring(idx), Default = obj.Value,
                Callback = function(v) obj.Value = v; obj:_fire() end })
            function obj:Set(b) self.Value = b; if self._bn and self._bn.Set then pcall(function() self._bn:Set(b) end) end; self:_fire() end
            self.__cur = obj._bn
            return wrapElement(self, obj)
        end
        function sec:AddSlider(idx, info)
            info = info or {}
            local obj = makeObj("Slider", idx, info.Default or info.Min or 0, info.Callback)
            obj.Min, obj.Max = info.Min or 0, info.Max or 100; Options[idx] = obj
            obj._bn = bnSection:Slider({ Name = info.Text or tostring(idx), Flag = "bn_" .. tostring(idx),
                Min = obj.Min, Max = obj.Max, Default = obj.Value, Decimals = math.max(info.Rounding or 1, 1), Suffix = info.Suffix or "",
                Callback = function(v) obj.Value = v; obj:_fire() end })
            function obj:Set(v) self.Value = v; if self._bn and self._bn.Set then pcall(function() self._bn:Set(v) end) end; self:_fire() end
            self.__cur = obj._bn
            return wrapElement(self, obj)
        end
        function sec:AddDropdown(idx, info)
            info = info or {}
            local values = info.Values or {}
            local default = info.Default
            if type(default) == "number" then default = values[default] end
            if info.Multi and type(default) ~= "table" then default = default or {} end
            local obj = makeObj("Dropdown", idx, default, info.Callback)
            obj.Values = values; obj.Multi = info.Multi or false; Options[idx] = obj
            obj._bn = bnSection:Dropdown({ Name = info.Text or tostring(idx), Flag = "bn_" .. tostring(idx),
                Items = values, Default = obj.Value, Multi = obj.Multi or false,
                Callback = function(v) obj.Value = v; obj:_fire() end })
            function obj:SetValue(v) self.Value = v; if self._bn and self._bn.Set then pcall(function() self._bn:Set(v) end) end; self:_fire() end
            obj.Set = obj.SetValue
            function obj:SetValues(vals) self.Values = vals; if self._bn and self._bn.SetValues then pcall(function() self._bn:SetValues(vals) end) end end
            self.__cur = obj._bn
            return wrapElement(self, obj)
        end
        function sec:AddInput(idx, info)
            info = info or {}
            local obj = makeObj("Input", idx, info.Default or "", info.Callback)
            Options[idx] = obj
            obj._bn = bnSection:Textbox({ Name = info.Text or tostring(idx), Flag = "bn_" .. tostring(idx),
                Default = obj.Value, Placeholder = info.Placeholder or "", Numeric = info.Numeric or false, Finished = info.Finished or false,
                Callback = function(v) obj.Value = v; obj:_fire() end })
            function obj:SetValue(v) self.Value = v; if self._bn and self._bn.Set then pcall(function() self._bn:Set(v) end) end; self:_fire() end
            obj.Set = obj.SetValue
            self.__cur = obj._bn
            return wrapElement(self, obj)
        end
        sec.AddTextbox = sec.AddInput
        function sec:AddButton(a, b)
            local name, cb
            if type(a) == "table" then name, cb = a.Text or a.Name, a.Func or a.Callback else name, cb = a, b end
            bnSection:Button({ Name = name or "button", Callback = function() if cb then pcall(cb) end end })
            return sec
        end
        function sec:AddLabel(text)
            local bnLabel = bnSection:Label({ Name = type(text) == "table" and (text.Text or "") or tostring(text) })
            self.__cur = bnLabel
            return wrapElement(self, nil)
        end
        function sec:AddDivider() return sec end
        function sec:AddBlank() return sec end
        function sec:AddDualSlider(idxL, idxR, infoL, infoR) sec:AddSlider(idxL, infoL); sec:AddSlider(idxR, infoR); return sec end
        function sec:AddDependencyBox()
            local dep = makeSection(bnSection)
            dep.SetupDependencies = function() end; dep.Update = function() end
            table.insert(Lib.DependencyBoxes, dep)
            return dep
        end
        function sec:Resize() end
        function sec:SetupDependencies() end
        return sec
    end

    local function makeTabbox(bnSection)
        local tb = {}
        function tb:AddTab(name)
            local s = makeSection(bnSection)
            bnSection:Label({ Name = "— " .. tostring(name) .. " —" })
            return s
        end
        return tb
    end

    local function makeTab(bnPage)
        local tab = { Groupboxes = {}, Tabboxes = {} }
        function tab:AddGroupbox(info)
            local side = (info and info.Side) or 1
            local bnSec = bnPage:Section({ Name = (info and info.Name) or "section", Side = side })
            return makeSection(bnSec)
        end
        function tab:AddLeftGroupbox(name) return tab:AddGroupbox({ Side = 1, Name = name }) end
        function tab:AddRightGroupbox(name) return tab:AddGroupbox({ Side = 2, Name = name }) end
        function tab:AddTabbox(info)
            local side = (info and info.Side) or 1
            local bnSec = bnPage:Section({ Name = (info and info.Name) or "tabs", Side = side })
            return makeTabbox(bnSec)
        end
        function tab:AddLeftTabbox(name) return tab:AddTabbox({ Side = 1, Name = name }) end
        function tab:AddRightTabbox(name) return tab:AddTabbox({ Side = 2, Name = name }) end
        return tab
    end

    function Lib:CreateWindow(config)
        config = config or {}
        local bnWindow = BN:Window({ Name = "$$ banknote: Rivals $$" })
        Lib._bnWindow = bnWindow
        pcall(function() Lib._watermarkObj = bnWindow:Watermark({ Name = "$$ banknote $$" }) end)
        pcall(function() bnWindow:KeybindList() end)
        local Window = { Tabs = {}, Holder = nil, TabPadding = config.TabPadding or 6 }
        function Window:AddTab(name)
            local bnPage = bnWindow:Page({ Name = name })
            local tab = makeTab(bnPage)
            Window.Tabs[name] = tab
            return tab
        end
        task.defer(function() pcall(function() bnWindow:Init() end) end)
        return Window
    end

    task.spawn(function()
        local frames, elapsed = 0, 0
        RunService.RenderStepped:Connect(function(dt)
            frames += 1; elapsed += dt
            if elapsed >= 1 then
                Lib:SetWatermark(("$$ banknote $$ | %d fps"):format(math.floor(frames / elapsed)))
                frames, elapsed = 0, 0
            end
        end)
    end)

    return Lib
end)()
