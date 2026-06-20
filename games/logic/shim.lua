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
    -- nil-safe access: any unregistered flag returns a harmless stub so
    -- calls like Options.X:OnChanged(...) / Toggles.X.Value never error.
    local Stub = setmetatable({ Value = false, Mode = "Toggle", Type = "Stub" }, {
        __index = function() return function() end end,
    })
    setmetatable(Toggles, { __index = function() return Stub end })
    setmetatable(Options, { __index = function() return Stub end })
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
        text = tostring(text):gsub("instance", "$$ banknote $$")
        Lib._watermarkText = text
        if Lib._watermarkObj and Lib._watermarkObj.SetText then pcall(function() Lib._watermarkObj:SetText(text) end) end
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

    -- Keybinds use the banknote library's NATIVE Keybind (Toggle/Hold/Always,
    -- shows in the keybind list). We keep a registry to sync Mode/state back
    -- into the Options[idx] objects the Instance logic reads.
    local keyPickers = {}
    local function toKeyCode(v)
        if v == nil then return nil end
        if typeof(v) == "EnumItem" then return v end
        local s = tostring(v):gsub("Enum%.KeyCode%.", ""):gsub("Enum%.UserInputType%.", "")
        if s == "None" or s == "" or s == "none" then return nil end
        if Enum.KeyCode[s] then return Enum.KeyCode[s] end
        if Enum.UserInputType[s] then return Enum.UserInputType[s] end
        return nil
    end
    RunService.Heartbeat:Connect(function()
        local flags = BN.Flags
        if not flags then return end
        for _, kp in ipairs(keyPickers) do
            local f = flags[kp._flag]
            if type(f) == "table" then
                kp.Mode = f.Mode or kp.Mode
                kp._state = f.Toggled and true or false
                if f.Key then kp.Value = tostring(f.Key) end
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
        obj._flag = "bnkey_" .. tostring(idx)
        function obj:GetState()
            local f = BN.Flags and BN.Flags[self._flag]
            if type(f) == "table" then
                self.Mode = f.Mode or self.Mode
                self._state = f.Toggled and true or false
            end
            return self._state
        end
        Options[idx] = obj
        table.insert(keyPickers, obj)
        local bn = section.__cur
        if bn and bn.Keybind then
            local data = {
                Name = info.Text or info.Title or tostring(idx),
                Flag = obj._flag,
                Mode = obj.Mode,
                Callback = function(toggled)
                    obj._state = toggled and true or false
                    local f = BN.Flags and BN.Flags[obj._flag]
                    if type(f) == "table" then
                        if f.Mode then obj.Mode = f.Mode end
                        if f.Key then obj.Value = tostring(f.Key) end
                    end
                    if obj.Callback then pcall(obj.Callback, obj._state) end
                    for _, fn in ipairs(obj._changed) do pcall(fn, obj._state) end
                end,
            }
            local default = toKeyCode(info.Default)
            if default then data.Default = default end
            obj._bn = bn:Keybind(data)
        end
        function obj:Set(k)
            if obj._bn and obj._bn.Set then pcall(function() obj._bn:Set(k) end) end
        end
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
            -- banknote's Round() uses an INCREMENT (step), not decimal places.
            -- Instance's "Rounding" is decimal places, so step = 10^-Rounding.
            local step = 10 ^ (-(info.Rounding or 0))
            obj._bn = bnSection:Slider({ Name = info.Text or tostring(idx), Flag = "bn_" .. tostring(idx),
                Min = obj.Min, Max = obj.Max, Default = obj.Value, Decimals = step, Suffix = info.Suffix or "",
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

    -- Tabbox: juanitahaxx has no nested tabs, so each "tab" becomes its own
    -- clean section named after the tab (on the same side).
    local function makeTabbox(bnPage, side)
        local tb = {}
        function tb:AddTab(name)
            local bnSec = bnPage:Section({ Name = tostring(name), Side = side })
            return makeSection(bnSec)
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
            return makeTabbox(bnPage, side)
        end
        function tab:AddLeftTabbox(name) return tab:AddTabbox({ Side = 1, Name = name }) end
        function tab:AddRightTabbox(name) return tab:AddTabbox({ Side = 2, Name = name }) end
        return tab
    end

    -- Dummy (no-op) chain for the Instance "settings" tab — the banknote
    -- library auto-builds its own settings page on Init, so we discard
    -- Instance's duplicate settings UI while keeping its code error-free.
    local function makeDummyChain()
        local d = {}
        setmetatable(d, { __index = function() return function() return d end end })
        return d
    end
    local function makeDummySection()
        local s = {}
        setmetatable(s, { __index = function() return function() return makeDummyChain() end end })
        return s
    end
    local function makeDummyTab()
        local t = {}
        setmetatable(t, { __index = function() return function() return makeDummySection() end end })
        return t
    end

    function Lib:CreateWindow(config)
        config = config or {}
        local bnWindow = BN:Window({ Name = "$$ banknote: Rivals $$" })
        Lib._bnWindow = bnWindow
        pcall(function() Lib._watermarkObj = bnWindow:Watermark({ Name = "$$ banknote $$" }) end)
        pcall(function() bnWindow:KeybindList() end)
        local Window = { Tabs = {}, Holder = nil, TabPadding = config.TabPadding or 6 }
        function Window:AddTab(name)
            -- skip Instance's settings tab (banknote provides its own)
            if tostring(name):lower() == "settings" then
                local dummy = makeDummyTab()
                Window.Tabs[name] = dummy
                return dummy
            end
            local bnPage = bnWindow:Page({ Name = name })
            local tab = makeTab(bnPage)
            Window.Tabs[name] = tab
            return tab
        end
        task.defer(function() pcall(function() bnWindow:Init() end) end)
        return Window
    end

    return Lib
end)()
