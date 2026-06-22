--======================================================================
-- $$ banknote $$  -  Da Hood  (PlaceId 2788229376)
--
-- This is the "sample.hit" Da Hood feature set, ported to run on the banknote
-- UI. Their feature LOGIC is kept intact; only their UI library is swapped for
-- a shim (H) that builds banknote elements instead. The ESP section and their
-- own settings/configs tab are excluded (banknote has its own settings, and
-- ESP was explicitly left out). Telemetry/webhook was stripped.
--
-- Marker for the loader: BanknoteLibrary
--======================================================================
-- Neutralize stale desync / fake-position / crosshair / camlock state from a
-- previous run FIRST (before the load guard). The desync "void spam" loops and
-- the crosshair render loop are connected unconditionally and check these
-- getgenv flags every frame; the original used `getgenv().x = getgenv().x or {}`
-- so a re-inject kept old enabled=true state, causing the constant void
-- teleporting and the crosshair error spam. Clearing the flags here stops both
-- immediately, even on a re-inject (no rejoin needed).
do
    for _, key in ipairs({ "fpos", "csync", "network" }) do
        local tbl = getgenv()[key]
        if type(tbl) == "table" then
            pcall(function()
                tbl.enabled = false
                tbl.velocity_enabled = false
                tbl.VisualizeEnabled = false
            end)
        end
    end
    -- csync's Heartbeat loop re-derives `enabled` from `selectedMode` every
    -- frame (enabled = selectedMode ~= 'CLICK ME TO DISABLE DESYNC'), so just
    -- clearing enabled is instantly overwritten. Reset the mode sentinel too,
    -- otherwise it keeps void-spamming your character underground.
    if type(getgenv().csync) == "table" then
        pcall(function() getgenv().csync.selectedMode = 'CLICK ME TO DISABLE DESYNC' end)
    end
    if type(getgenv().crosshair) == "table" then
        pcall(function() getgenv().crosshair.enabled = false end)
    end
    getgenv().lock = false
    getgenv().locktrgt = nil
end

if getgenv()._DaHoodLoaded then return end
getgenv()._DaHoodLoaded = true

-- Luraph macros (the original was Luraph-obfuscated). No-ops here.
LPH_OBFUSCATED   = true
LPH_NO_VIRTUALIZE = LPH_NO_VIRTUALIZE or function(f) return f end
LPH_JIT_MAX       = LPH_JIT_MAX or function(f) return f end
LPH_JIT           = LPH_JIT or function(f) return f end
LPH_NO_UPVALUES   = LPH_NO_UPVALUES or function(f) return f end
LPH_CRASH         = LPH_CRASH or function() end
LPH_ENCSTR        = LPH_ENCSTR or function(s) return s end
LPH_ENCNUM        = LPH_ENCNUM or function(x) return x end

pcall(function() if setfpscap then setfpscap(999) end end)
if cleardrawcache then pcall(cleardrawcache) end

-- math / drawing locals the body relies on (originally above the body)
local e = Drawing and Drawing.new
local f = Vector2.new
local g = Vector3.new
local h = CFrame.new
local i = Color3.fromRGB
local j = math.huge
local k = math.clamp
local l = math.sin
local m = math.pi
local n = tick
local o = table.insert
local p = table.clear
local q = ipairs
local r = pairs
local s = type
local t = typeof

-- service locals the body relies on
local v = game:GetService('Players')
local w = game:GetService('Workspace')
local x = w.CurrentCamera
local y = v.LocalPlayer
local z = game:GetService('RunService')
local A = game:GetService('ReplicatedStorage')
local B = game:GetService('TweenService')
local C = game:GetService('UserInputService')
local D = game:GetService('CoreGui')
local E = y:GetMouse()
local F = game:GetService('Lighting')
local G = game:GetService('StarterGui')

_G.Multi_IsBuying = false
_G.IsBuying = false
_G.busdhfnjsy7gjsy7d = false

--======================================================================
-- H: shim emulating the sample's UI library on top of the banknote library.
-- Supports: window -> tab -> section -> toggle/slider/keybind/dropdown/
-- colorpicker/textbox/button/label, plus H:notification{} and H.flags.
-- The "esp" section and any "settings" tab resolve to harmless no-op dummies.
--======================================================================
local H = (function()
    local BN = getgenv().BanknoteLibrary
    assert(BN, "[banknote] BanknoteLibrary not set by loader")

    local flags = {}
    local Shim = { flags = flags, directory = "banknote/ui" }

    local uid = 0
    local function nextFlag(o)
        uid = uid + 1
        return "dh_" .. uid .. "_" .. tostring((type(o) == "table" and (o.flag or o.name)) or "el")
    end
    local function setflag(flag, val) if flag ~= nil then flags[flag] = val end end

    -- a returned element: proxies a few common calls, no-ops everything else
    local function elem(bnObj)
        local w = { __bn = bnObj }
        function w:Set(v) if bnObj and bnObj.Set then pcall(function() bnObj:Set(v) end) end return w end
        function w:set(v) return w:Set(v) end
        function w:SetText(tx) if bnObj and bnObj.SetText then pcall(function() bnObj:SetText(tx) end) end return w end
        function w:SetValue(v) return w:Set(v) end
        setmetatable(w, { __index = function() return function() return w end end })
        return w
    end

    local function dummy()
        local d = {}
        setmetatable(d, { __index = function() return function() return d end end })
        return d
    end

    local function makeSection(bnSec)
        local sec = {}

        function sec:toggle(o)
            o = o or {}
            setflag(o.flag, o.default and true or false)
            local bn = bnSec:Toggle({
                Name = tostring(o.name or o.flag or "toggle"), Flag = nextFlag(o),
                Default = o.default and true or false,
                Callback = function(val) setflag(o.flag, val) if o.callback then pcall(o.callback, val) end end
            })
            return elem(bn)
        end

        function sec:slider(o)
            o = o or {}
            setflag(o.flag, o.default or o.min or 0)
            local bn = bnSec:Slider({
                Name = tostring(o.name or "slider"), Flag = nextFlag(o),
                Min = o.min or 0, Max = o.max or 100, Default = o.default or o.min or 0,
                Decimals = o.interval or 1, Suffix = (type(o.suffix) == "string" and o.suffix) or "",
                Callback = function(val) setflag(o.flag, val) if o.callback then pcall(o.callback, val) end end
            })
            return elem(bn)
        end

        function sec:dropdown(o)
            o = o or {}
            local items = o.items or {}
            local default = o.default
            if o.multi then
                if type(default) ~= "table" then default = default or {} end
            elseif default == nil and items[1] ~= nil then
                default = items[1]  -- avoid empty "none" dropdowns
            end
            setflag(o.flag, default)
            local bn = bnSec:Dropdown({
                Name = tostring(o.name or "dropdown"), Flag = nextFlag(o),
                Items = items, Default = default, Multi = o.multi or false,
                Callback = function(val) setflag(o.flag, val) if o.callback then pcall(o.callback, val) end end
            })
            return elem(bn)
        end

        function sec:keybind(o)
            o = o or {}
            local lbl = bnSec:Label({ Name = tostring(o.name or o.display or "keybind") })
            -- banknote fires a keybind's Callback once synchronously on creation
            -- (with Toggled=false). Several sample keybinds are toggle-FLIP style
            -- (they flip state on every call, ignoring the passed value), so that
            -- creation-fire would flip them ON - e.g. it was enabling the desync
            -- "Void Spam" mode and flinging the character to ~2M studs. Swallow
            -- any callback that fires during creation.
            local ready = false
            local data = {
                Name = tostring(o.display or o.name or "keybind"), Flag = nextFlag(o), Mode = "Toggle",
                Callback = function(toggled)
                    if not ready then return end
                    setflag(o.flag, toggled)
                    if o.callback then pcall(o.callback, toggled) end
                end
            }
            if typeof(o.default) == "EnumItem" then data.Default = o.default end
            local kb = (lbl and lbl.Keybind) and lbl:Keybind(data) or nil
            ready = true
            return elem(kb)
        end

        function sec:colorpicker(o)
            o = o or {}
            setflag(o.flag, o.color or Color3.fromRGB(255, 255, 255))
            local lbl = bnSec:Label({ Name = tostring(o.name or "color") })
            local bn = (lbl and lbl.Colorpicker) and lbl:Colorpicker({
                Name = tostring(o.name or "color"), Flag = nextFlag(o),
                Default = o.color or Color3.fromRGB(255, 255, 255),
                Callback = function(c) setflag(o.flag, c) if o.callback then pcall(o.callback, c) end end
            }) or nil
            return elem(bn)
        end

        function sec:textbox(o)
            o = o or {}
            setflag(o.flag, o.default or "")
            local bn = bnSec:Textbox({
                Name = tostring(o.name or o.flag or "textbox"), Flag = nextFlag(o),
                Default = o.default or "", Placeholder = o.placeholder or "", Finished = o.finished or false,
                Callback = function(val) setflag(o.flag, val) if o.callback then pcall(o.callback, val) end end
            })
            return elem(bn)
        end

        function sec:button(o)
            o = o or {}
            bnSec:Button({ Name = tostring(o.name or "button"), Callback = function() if o.callback then pcall(o.callback) end end })
            return elem(nil)
        end

        function sec:label(o)
            local nm = (type(o) == "table" and (o.name or o.text or "")) or tostring(o)
            return elem(bnSec:Label({ Name = tostring(nm) }))
        end

        setmetatable(sec, { __index = function() return function() return sec end end })
        return sec
    end

    local function makeTab(bnPage)
        local tab = {}
        function tab:section(o)
            o = o or {}
            local nm = tostring(o.name or "section")
            local nmc = nm:lower():gsub("%s+", "")
            if nmc == "esp" or nmc == "crosshair" then return dummy() end  -- excluded (ESP + buggy crosshair render loop)
            local side = (o.side == "right") and 2 or 1
            return makeSection(bnPage:Section({ Name = nm, Side = side }))
        end
        setmetatable(tab, { __index = function() return function() return tab end end })
        return tab
    end

    local function makeWindow(bnWindow)
        local win = {}
        function win:tab(o)
            o = o or {}
            local nm = tostring(o.name or "tab"):gsub("^%s+", ""):gsub("%s+$", "")
            if nm:lower() == "settings" then return dummy() end  -- banknote has its own
            return makeTab(bnWindow:Page({ Name = nm }))
        end
        setmetatable(win, { __index = function() return function() return win end end })
        return win
    end

    function Shim:window(o)
        local bnWindow = BN:Window({ Name = "$$ banknote: Da Hood $$" })
        Shim._bnWindow = bnWindow
        pcall(function() bnWindow:Watermark({ Name = "$$ banknote $$" }) end)
        pcall(function() bnWindow:KeybindList() end)
        task.defer(function() pcall(function() bnWindow:Init() end) end)
        return makeWindow(bnWindow)
    end

    function Shim:notification(o)
        o = o or {}
        pcall(function()
            BN:Notification(tostring(o.text or o.title or ""), o.duration or 3, BN.Theme and BN.Theme.Accent)
        end)
    end

    -- any other H:method (update_theme, panel, config_*, toggle_list, ...) -> no-op
    setmetatable(Shim, { __index = function() return function() return Shim end end })
    return Shim
end)()


local I = H.flags
local J = H:window{
    name = 'sample',
    subname = '.hit',
    menulogo = 'rbxassetid://107276976681956',
    size = UDim2.fromOffset(590, 565),
}
local K = J:tab{
    name = ' main',
}
local L = J:tab{
    name = ' ragebot',
}
local M = J:tab{
    name = ' world',
}
local N = J:tab{
    name = ' visuals',
}
local O = J:tab{
    name = ' misc',
}

_G.SA = {
    silent = false,
    part = 'Head',
    method = 'closest point',
    knock = false,
    chance = 100,
    wall = false,
    custom = false,
    legacy = false,
    FOV = {
        vis = false,
        trans = 1,
        thick = 1,
        rad = 150,
        col = Color3.fromRGB(255, 255, 255),
    },
    Enabled = false,
}

local P = game:GetService'Players'
local Q = game:GetService'Workspace'
local R = game:GetService'ReplicatedStorage'
local S = game:GetService'UserInputService'
local T = game:GetService'RunService'
local U = P.LocalPlayer
local V = Q.CurrentCamera
local W
local X

task.spawn(function()
    local Y = R:WaitForChild('Modules', 5):WaitForChild('GunHandler', 5)

    if Y then
        W = require(Y)
        X = W.getAim
    end
end)

_G.rc = nil
_G.FOVC = nil
_G.FOVC_O = nil
_G.FOVC_I = nil
_G.WC = LPH_NO_VIRTUALIZE(function(Y)
    if not V or not U.Character then
        return false
    end

    local Z = V.CFrame.Position
    local _ = Y.Position
    local aa = (_ - Z).Unit
    local ab = (_ - Z).Magnitude
    local ac = RaycastParams.new()

    ac.FilterDescendantsInstances = {
        U.Character,
        V,
    }
    ac.FilterType = Enum.RaycastFilterType.Blacklist
    ac.IgnoreWater = true

    local ad = Q:Raycast(Z, aa * ab, ac)

    if ad then
        local ae = ad.Instance:FindFirstAncestorOfClass'Model'

        return not (ae and P:GetPlayerFromCharacter(ae))
    end

    return false
end)
_G.GCP = LPH_JIT_MAX(function()
    local aa, ab, ac
    local ad = S:GetMouseLocation()
    local ae = {
        'LeftHand',
        'LeftLowerArm',
        'LeftUpperArm',
        'RightHand',
        'RightLowerArm',
        'RightUpperArm',
        'UpperTorso',
        'LeftFoot',
        'LeftLowerLeg',
        'LeftUpperLeg',
        'RightFoot',
        'RightLowerLeg',
        'RightUpperLeg',
        'LowerTorso',
        'Head',
    }

    for Y, Z in next, P:GetPlayers()do
        if Z ~= U and Z.Character then
            local _ = Z.Character
            local af = _:FindFirstChild'Humanoid'
            local ag = _:FindFirstChild'BodyEffects'
            local ah = ag and (ag:FindFirstChild'K.O' or ag:FindFirstChild'KO') and (ag:FindFirstChild'K.O' or ag:FindFirstChild'KO').Value

            if af and af.Health > 0 and (not _G.SA.knock or not ah) then
                if _G.SA.custom then
                    if _G.SA.method == 'closest part' then
                        for ai, aj in q(ae)do
                            local ak = _:FindFirstChild(aj)

                            if ak and (not _G.SA.wall or not _G.WC(ak)) then
                                local al, am = V:WorldToViewportPoint(ak.Position)

                                if am then
                                    local an = (ad - Vector2.new(al.X, al.Y)).Magnitude

                                    if an <= _G.SA.FOV.rad and (not aa or an < aa) then
                                        aa, ab, ac = an, ak, Z
                                    end
                                end
                            end
                        end
                    else
                        for ai, aj in q(_:GetChildren())do
                            if aj:IsA'BasePart' and (not _G.SA.wall or not _G.WC(aj)) then
                                local ak, al = V:WorldToViewportPoint(aj.Position)

                                if al then
                                    local am = (ad - Vector2.new(ak.X, ak.Y)).Magnitude

                                    if am <= _G.SA.FOV.rad and (not aa or am < aa) then
                                        aa, ab, ac = am, aj, Z
                                    end
                                end
                            end
                        end
                    end
                elseif _G.SA.legacy then
                    local ai = _:FindFirstChild(_G.SA.part)

                    if ai and (not _G.SA.wall or not _G.WC(ai)) then
                        local aj, ak = V:WorldToViewportPoint(ai.Position)

                        if ak then
                            local al = (ad - Vector2.new(aj.X, aj.Y)).Magnitude

                            if al <= _G.SA.FOV.rad and (not aa or al < aa) then
                                aa, ab, ac = al, ai, Z
                            end
                        end
                    end
                end
            end
        end
    end

    return ab, ac
end)
_G.cfovc = LPH_NO_VIRTUALIZE(function()
    if t(Drawing) == 'table' and Drawing.new then
        if not _G.FOVC_O then
            _G.FOVC_O = Drawing.new'Circle'
            _G.FOVC_O.ZIndex = 1
            _G.FOVC_O.Filled = false
            _G.FOVC_O.Visible = false
            _G.FOVC_O.Color = Color3.new(0, 0, 0)
        end
        if not _G.FOVC_I then
            _G.FOVC_I = Drawing.new'Circle'
            _G.FOVC_I.ZIndex = 1
            _G.FOVC_I.Filled = false
            _G.FOVC_I.Visible = false
            _G.FOVC_I.Color = Color3.new(0, 0, 0)
        end
        if not _G.FOVC then
            _G.FOVC = Drawing.new'Circle'
            _G.FOVC.ZIndex = 2
            _G.FOVC.Filled = false
            _G.FOVC.Visible = false
        end
    end
end)
_G.ufovc = LPH_NO_VIRTUALIZE(function()
    if not _G.FOVC then
        return
    end

    local aa = S:GetMouseLocation()
    local ab = (_G.SA.FOV.vis and _G.SA.Enabled and (_G.SA.legacy or _G.SA.custom))

    _G.FOVC.Position = Vector2.new(aa.X, aa.Y)
    _G.FOVC.Visible = ab
    _G.FOVC.Color = _G.SA.FOV.col
    _G.FOVC.Thickness = _G.SA.FOV.thick
    _G.FOVC.Radius = _G.SA.FOV.rad
    _G.FOVC.Transparency = _G.SA.FOV.trans

    if _G.FOVC_O then
        _G.FOVC_O.Position = _G.FOVC.Position
        _G.FOVC_O.Visible = ab
        _G.FOVC_O.Thickness = _G.SA.FOV.thick + 2
        _G.FOVC_O.Radius = _G.SA.FOV.rad
        _G.FOVC_O.Transparency = _G.SA.FOV.trans
    end
    if _G.FOVC_I then
        _G.FOVC_I.Position = _G.FOVC.Position
        _G.FOVC_I.Visible = ab
        _G.FOVC_I.Thickness = math.max(_G.SA.FOV.thick - 2, 0.1)
        _G.FOVC_I.Radius = _G.SA.FOV.rad
        _G.FOVC_I.Transparency = _G.SA.FOV.trans
    end
end)
_G.HM = LPH_JIT_MAX(function()
    if W then
        W.getAim = function(aa, ab)
            local ac = ab or 9999

            if _G.SA.Enabled and (_G.SA.legacy or _G.SA.custom) then
                if math.random(0, 100) <= _G.SA.chance then
                    local ad, ae = _G.GCP()

                    if ad then
                        local af = (ad.Position - aa)

                        return af.Unit, math.min(af.Magnitude, ac)
                    end
                end
            end

            return X(aa, ac)
        end
    end
end)
_G.UHM = LPH_NO_VIRTUALIZE(function()
    if W and X then
        W.getAim = X
    end
end)
_G.SSA = LPH_NO_VIRTUALIZE(function()
    if _G.rc then
        return
    end

    _G.cfovc()
    _G.HM()

    _G.rc = T.RenderStepped:Connect(function()
        _G.ufovc()
    end)
end)
_G.STA = LPH_NO_VIRTUALIZE(function()
    if _G.rc then
        pcall(function()
            _G.rc:Disconnect()
        end)

        _G.rc = nil
    end
    if _G.FOVC then
        _G.FOVC.Visible = false
    end
    if _G.FOVC_O then
        _G.FOVC_O.Visible = false
    end
    if _G.FOVC_I then
        _G.FOVC_I.Visible = false
    end

    _G.UHM()
end)

local aa = K:section{
    name = 'silent aimbot',
}

aa:keybind{
    name = 'master keybind',
    flag = 'tyitgiit',
    default = nil,
    display = 'silent aimbot',
    callback = function(ab)
        _G.SA.Enabled = ab
        _G.SA.silent = ab and (_G.SA.legacy or _G.SA.custom)

        if _G.SA.silent then
            _G.SSA()
        else
            _G.STA()
        end
    end,
}
aa:toggle{
    name = 'enabled',
    flag = 'uytruttuyk',
    default = false,
    callback = function(ab)
        _G.SA.Enabled = ab
        _G.SA.silent = ab and (_G.SA.legacy or _G.SA.custom)

        if _G.SA.silent then
            _G.SSA()
        else
            _G.STA()
        end
    end,
}
aa:toggle{
    name = 'knock check',
    flag = 'ytuiitiity',
    default = false,
    callback = function(ab)
        _G.SA.knock = ab
    end,
}
aa:toggle{
    name = 'wall check',
    flag = 'tyiittiktkitikt',
    default = false,
    callback = function(ab)
        _G.SA.wall = ab
    end,
}
aa:toggle{
    name = 'show fov',
    flag = 'drtgfduityfgfr',
    default = false,
    callback = function(ab)
        _G.SA.FOV.vis = ab
    end,
}
aa:colorpicker{
    name = 'fov color',
    flag = 'FOVColor',
    color = _G.SA.FOV.col,
    callback = function(ab)
        _G.SA.FOV.col = ab
    end,
}
aa:slider{
    name = 'fov size',
    flag = 'lkuykrrh',
    suffix = 'px',
    default = 150,
    min = 50,
    max = 1000,
    interval = 1,
    callback = function(ab)
        _G.SA.FOV.rad = ab
    end,
}
aa:toggle{
    name = 'use normal hitpart',
    flag = 'fgytjftfgtjtyfj',
    default = false,
    callback = function(ab)
        _G.SA.legacy = ab
        _G.SA.silent = _G.SA.Enabled and (_G.SA.legacy or _G.SA.custom)

        if _G.SA.silent then
            _G.SSA()
        else
            _G.STA()
        end
    end,
}
aa:dropdown{
    name = 'normal hitpart',
    flag = 'fgujfujftgyujfrgj',
    items = {
        'Head',
        'HumanoidRootPart',
        'UpperTorso',
        'LowerTorso',
        'RightHand',
        'LeftHand',
        'RightLeg',
    },
    multi = false,
    callback = function(ab)
        _G.SA.part = ab
    end,
}
aa:toggle{
    name = 'use custom hitpart',
    flag = 'fjtfgjfrjfgv',
    default = false,
    callback = function(ab)
        _G.SA.custom = ab
        _G.SA.silent = _G.SA.Enabled and (_G.SA.legacy or _G.SA.custom)

        if _G.SA.silent then
            _G.SSA()
        else
            _G.STA()
        end
    end,
}
aa:dropdown{
    name = 'custom hitpart',
    flag = 'fjfjttfjyjgfgtuj',
    items = {
        'closest part',
        'closest point',
    },
    multi = false,
    callback = function(ab)
        _G.SA.method = ab
    end,
}
aa:slider{
    name = 'hit chance',
    flag = 'ftjgffjfghy',
    suffix = '%',
    default = 100,
    min = 0,
    max = 100,
    interval = 1,
    callback = function(ab)
        _G.SA.chance = ab
    end,
}

local ab = K:section{
    name = 'triggerbot',
}

_G.sylithtb = false
_G.lastCheck = 0
_G.currentTarget = nil
_G.TriggerBot = {
    Delay = 0.5,
    Blacklisted = {},
}
_G.isDead = LPH_NO_VIRTUALIZE(function(ac)
    local ad = ac.Character

    if not ad then
        return true
    end

    local ae = ad:FindFirstChild'BodyEffects'

    if not ae then
        return true
    end

    local af = ae:FindFirstChild'K.O' or ae:FindFirstChild'KO'

    return af and af.Value
end)
_G.getTargetFromPart = LPH_NO_VIRTUALIZE(function(ac)
    if not ac then
        return nil
    end

    local ad = game:GetService'Players':GetPlayers()

    for ae = 1, #ad do
        local af = ad[ae]

        if af.Character and ac:IsDescendantOf(af.Character) and not _G.isDead(af) then
            return af
        end
    end

    return nil
end)
_G.StartTriggerBot = LPH_JIT_MAX(function()
    if _G.TriggerBotConnection then
        _G.TriggerBotConnection:Disconnect()
    end

    local ac = P.LocalPlayer
    local ad = ac:GetMouse()

    _G.TriggerBotConnection = T.Heartbeat:Connect(function()
        if not _G.sylithtb then
            _G.currentTarget = nil

            return
        end

        local ae = os.clock()

        if ae - (_G.lastCheck or 0) < 0.05 then
            return
        end

        _G.lastCheck = ae

        local af = _G.getTargetFromPart(ad.Target)

        _G.currentTarget = af

        local ag = ac.Character

        if af and ag then
            local ah = ag:FindFirstChildWhichIsA'Tool'

            if ah then
                local ai = false

                for aj, ak in next, _G.TriggerBot.Blacklisted do
                    if ak and ah.Name:find(aj) then
                        ai = true

                        break
                    end
                end

                if not ai then
                    task.spawn(function()
                        local aj = _G.TriggerBot.Delay or 0

                        if aj > 0 then
                            task.wait(aj)
                        end
                        if _G.currentTarget == _G.getTargetFromPart(ad.Target) then
                            ah:Activate()
                        end
                    end)
                end
            end
        end
    end)
end)

_G.StartTriggerBot()
ab:toggle{
    name = 'enabled',
    flag = 'ftjgjufytjgvj',
    default = false,
    callback = function(ac)
        _G.sylithtb = ac

        if not ac then
            _G.currentTarget = nil
        end
    end,
}
ab:slider{
    name = 'cooldown',
    flag = 'dfrghdhygpppp',
    suffix = 's',
    default = 0.5,
    min = 0,
    max = 3,
    interval = 0.01,
    callback = function(ac)
        _G.TriggerBot.Delay = ac
    end,
}
ab:dropdown{
    name = 'blacklisted tools',
    flag = 'dfgghdoooootthh',
    items = {
        '[Knife]',
        'Combat',
        '[Phone]',
        '[Wallet]',
        'TipJar',
        '[Bat]',
        '[Shovel]',
        '[LockPicker]',
    },
    multi = true,
    callback = function(ac)
        _G.TriggerBot.Blacklisted = ac
    end,
}

local ac = K:section{
    name = 'camera aimbot',
    side = 'right',
}

getgenv().lock = false
getgenv().locktrgt = nil
getgenv().lockUsmooth = false
getgenv().locksmooth = 0.5
getgenv().lockpart = 'Head'
getgenv().lockUpred = false
getgenv().lockpredX = 0
getgenv().lockpredY = 0
getgenv().lockpredZ = 0
getgenv().shalke = false
getgenv().shk = 0
getgenv().orbitSpeed = 5
getgenv().orbitAngle = 0
getgenv().orbitMid = false

ac:toggle{
    name = 'enabled',
    flag = 'camlock_enabled',
    default = false,
    callback = function(ad)
        getgenv().lock = ad

        if not ad then
            getgenv().locktrgt = nil
        end
    end,
}
ac:keybind{
    name = 'camera aimbot keybind',
    flag = 'camlock_bind',
    default = nil,
    display = 'camera aimbot',
    callback = function(ad)
        if not getgenv().lock then
            return
        end
        if getgenv().locktrgt then
            getgenv().locktrgt = nil
        else
            local ae, af = (math.huge)
            local ag = game:GetService'UserInputService':GetMouseLocation()
            local ah = game:GetService'Players':GetPlayers()
            local ai = game:GetService'Players'.LocalPlayer
            local aj = workspace.CurrentCamera

            for ak = 1, #ah do
                local al = ah[ak]

                if al ~= ai then
                    local am = al.Character

                    if am then
                        local an = am:FindFirstChild(getgenv().lockpart)

                        if an then
                            local Y, Z = aj:WorldToViewportPoint(an.Position)

                            if Z then
                                local _ = (Vector2.new(ag.X, ag.Y) - Vector2.new(Y.X, Y.Y)).Magnitude

                                if _ < ae then
                                    ae = _
                                    af = al
                                end
                            end
                        end
                    end
                end
            end

            getgenv().locktrgt = af
        end
    end,
}
ac:dropdown{
    name = 'hitpart',
    flag = 'camlock_hitpart',
    items = {
        'Head',
        'UpperTorso',
        'LowerTorso',
        'HumanoidRootPart',
        'LeftFoot',
        'RightFoot',
        'LeftLowerArm',
        'RightLowerArm',
    },
    multi = false,
    callback = function(ad)
        getgenv().lockpart = ad
    end,
}
ac:toggle{
    name = 'smoothness',
    flag = 'camlock_smooth_enabled',
    default = false,
    callback = function(ad)
        getgenv().lockUsmooth = ad
    end,
}
ac:slider{
    name = 'smoothing',
    flag = 'camlock_smooth_value',
    suffix = '',
    default = 5,
    min = 0,
    max = 10,
    interval = 0.1,
    callback = function(ad)
        getgenv().locksmooth = 1 - (ad / 10)

        if getgenv().locksmooth <= 0 then
            getgenv().locksmooth = 0.01
        end
    end,
}
ac:toggle{
    name = 'prediction',
    flag = 'camlock_pred_enabled',
    default = false,
    callback = function(ad)
        getgenv().lockUpred = ad
    end,
}
ac:slider{
    name = 'x prediction',
    flag = 'camlock_predX_value',
    suffix = '',
    default = 0,
    min = 0,
    max = 10,
    interval = 0.1,
    callback = function(ad)
        getgenv().lockpredX = ad / 10
    end,
}
ac:slider{
    name = 'y prediction',
    flag = 'camlock_predY_value',
    suffix = '',
    default = 0,
    min = 0,
    max = 10,
    interval = 0.1,
    callback = function(ad)
        getgenv().lockpredY = ad / 10
    end,
}
ac:slider{
    name = 'z prediction',
    flag = 'camlock_predZ_value',
    suffix = '',
    default = 0,
    min = 0,
    max = 10,
    interval = 0.1,
    callback = function(ad)
        getgenv().lockpredZ = ad / 10
    end,
}
ac:toggle{
    name = 'shake',
    flag = 'camlock_shake_enabled',
    default = false,
    callback = function(ad)
        getgenv().shalke = ad
    end,
}
ac:slider{
    name = 'shaking',
    flag = 'camlock_shake_value',
    suffix = '',
    default = 0,
    min = 0,
    max = 10,
    interval = 0.1,
    callback = function(ad)
        getgenv().shk = ad / 10
    end,
}
ac:toggle{
    name = 'strafe if locked',
    flag = 'camlock_orbit_enabled',
    default = false,
    callback = function(ad)
        getgenv().orbitMid = ad

        if ad then
            getgenv().orbitAngle = 0
        end
    end,
}
ac:slider{
    name = 'strafe speed',
    flag = 'camlock_orbit_speed',
    suffix = '',
    default = 5,
    min = 0,
    max = 100,
    interval = 1,
    callback = function(ad)
        getgenv().orbitSpeed = ad
    end,
}
game:GetService'RunService'.RenderStepped:Connect(LPH_JIT_MAX(function(ad)
    if not getgenv().lock or not getgenv().locktrgt then
        return
    end

    local ae = getgenv().locktrgt.Character
    local af = ae and ae:FindFirstChild(getgenv().lockpart)

    if not af then
        return
    end

    local ag = workspace.CurrentCamera
    local ah = game.Players.LocalPlayer.Character

    if not ah then
        return
    end

    local ai = ah:FindFirstChild'HumanoidRootPart'

    if not ai then
        return
    end

    local aj = af.Position

    if getgenv().lockUpred then
        local ak = ae:FindFirstChild'HumanoidRootPart'

        if ak then
            local al = ak.Velocity

            aj += Vector3.new(al.X * getgenv().lockpredX, al.Y * getgenv().lockpredY, al.Z * getgenv().lockpredZ)
        end
    end
    if getgenv().orbitMid then
        local ak = getgenv().orbitSpeed

        getgenv().orbitAngle += math.rad(ak * ad * 60)

        local al = 5
        local am = Vector3.new(math.cos(getgenv().orbitAngle) * al, 0, math.sin(getgenv().orbitAngle) * al)

        ai.CFrame = CFrame.new(aj + am, aj)
    end

    local ak = (aj - ag.CFrame.Position).Unit

    if getgenv().shalke and getgenv().shk > 0 then
        local al = getgenv().shk * 0.02

        ak += Vector3.new((math.random() - 0.5) * al, (math.random() - 0.5) * al, (math.random() - 0.5) * al)

        ak = ak.Unit
    end
    if getgenv().lockUsmooth then
        local al = ag.CFrame
        local am = CFrame.new(al.Position, al.Position + ak)

        ag.CFrame = al:Lerp(am, 1 - getgenv().locksmooth)
    else
        ag.CFrame = CFrame.new(ag.CFrame.Position, ag.CFrame.Position + ak)
    end
end))

getgenv().LastShootSoundTime = getgenv().LastShootSoundTime or 0

local ad = 0.1

_G.dzzzz = U.CameraMaxZoomDistance
_G.defaultFOV = V.FieldOfView
_G.fovonn = false
_G.fovalllll = 90
_G.aspectEnabled = false
_G.RegionSpoofer_Enabled = false
_G.RegionSpoofer_Text = ''
getgenv().Resolution = {
    x = 1,
    y = 1,
}
getgenv().origmaterials = getgenv().origmaterials or {}
getgenv().currenttxtg = getgenv().currenttxtg or {}

local ae = M:section{
    name = 'camera',
}
local af = M:section{
    name = 'color correction',
}
local ag = M:section{
    name = 'map textures',
}
local ah = M:section{
    name = 'region spoofer',
}

ae:toggle{
    name = 'infinite zoom',
    flag = 'cam_infzoom',
    callback = function(ai)
        U.CameraMaxZoomDistance = ai and math.huge or _G.dzzzz
    end,
}
ae:toggle{
    name = 'fov changer',
    flag = 'cam_fovchng',
    callback = function(ai)
        _G.fovonn = ai
    end,
}
ae:slider{
    name = 'fov',
    flag = 'cam_fovval',
    min = 0,
    max = 120,
    default = 90,
    interval = 0.1,
    callback = function(ai)
        _G.fovalllll = ai
    end,
}
ae:toggle{
    name = 'aspect ratio',
    flag = 'cam_aspect_toggle',
    callback = function(ai)
        _G.aspectEnabled = ai
    end,
}
ae:slider{
    name = 'ratio x',
    flag = 'cam_aspect_x',
    min = 0,
    max = 1,
    default = 1,
    interval = 0.1,
    callback = function(ai)
        getgenv().Resolution.x = ai
    end,
}
ae:slider{
    name = 'ratio y',
    flag = 'cam_aspect_y',
    min = 0,
    max = 1,
    default = 1,
    interval = 0.1,
    callback = function(ai)
        getgenv().Resolution.y = ai
    end,
}

_G.ColorCorrection = {
    Enabled = false,
    Saturation = 0,
    Contrast = 0,
    Brightness = 0,
}

local function ai()
    local aj = F:FindFirstChild'CustomColorCorrection'

    if not aj then
        aj = Instance.new'ColorCorrectionEffect'
        aj.Name = 'CustomColorCorrection'
        aj.Enabled = false
        aj.Parent = F
    end

    return aj
end

local aj = LPH_NO_VIRTUALIZE(function()
    local aj = ai()

    aj.Enabled = _G.ColorCorrection.Enabled
    aj.Saturation = _G.ColorCorrection.Saturation
    aj.Contrast = _G.ColorCorrection.Contrast
    aj.Brightness = _G.ColorCorrection.Brightness
end)

af:toggle{
    name = 'enabled',
    flag = 'cc_enabled',
    callback = function(ak)
        _G.ColorCorrection.Enabled = ak

        aj()
    end,
}
af:slider{
    name = 'saturation',
    flag = 'cc_sat',
    min = -1,
    max = 1,
    default = 0,
    interval = 0.1,
    callback = function(ak)
        _G.ColorCorrection.Saturation = ak

        aj()
    end,
}
af:slider{
    name = 'contrast',
    flag = 'cc_con',
    min = -1,
    max = 1,
    default = 0,
    interval = 0.1,
    callback = function(ak)
        _G.ColorCorrection.Contrast = ak

        aj()
    end,
}
af:slider{
    name = 'brightness',
    flag = 'cc_bri',
    min = -1,
    max = 1,
    default = 0,
    interval = 0.1,
    callback = function(ak)
        _G.ColorCorrection.Brightness = ak

        aj()
    end,
}

getgenv().TextureThemeEnabled = false

local ak = {}
local al = game:GetService'MaterialService'
local am = {}

local function an()
    for Y, Z in q(am)do
        if Z then
            Z:Destroy()
        end
    end

    table.clear(am)
end
local function Y(Z)
    an()

    if not getgenv().TextureThemeEnabled then
        return
    end

    for _, ao in q(Z)do
        local ap = ao[1]
        local aq = ao[2]

        if not aq:find'rbxassetid://' and not aq:find'http' then
            aq = 'rbxassetid://' .. aq
        end

        local ar = Instance.new'MaterialVariant'

        ar.Name = 'Vader_' .. ap
        ar.BaseMaterial = Enum.Material[ap]
        ar.ColorMap = aq
        ar.NormalMap = aq
        ar.RoughnessMap = aq
        ar.MetalnessMap = aq
        ar.StudsPerTile = 5
        ar.Parent = al

        table.insert(am, ar)
        al:SetBaseMaterialOverride(Enum.Material[ap], ar.Name)
    end
end
local function ao()
    an()

    local ap = Enum.Material:GetEnumItems()

    for aq, ar in q(ap)do
        pcall(function()
            al:SetBaseMaterialOverride(ar, '')
        end)
    end
end

ag:toggle{
    name = 'enabled',
    flag = 'texture_enabled_toggle',
    callback = function(ap)
        getgenv().TextureThemeEnabled = ap

        if ap then
            if #ak > 0 then
                Y(ak)
            end
        else
            ao()
        end
    end,
}
ag:dropdown{
    name = 'select theme',
    flag = 'map_texture_dropdown',
    items = {
        'playboi carti',
        'minecraft',
        'minecraft2',
        'icey',
        'weed minecraft',
    },
    callback = function(ap)
        local aq = {}

        if ap == 'playboi carti' then
            aq = {
                {
                    'Wood',
                    '14784281899',
                },
                {
                    'WoodPlanks',
                    '14784281899',
                },
                {
                    'Brick',
                    '12647798329',
                },
                {
                    'Cobblestone',
                    '12647798329',
                },
                {
                    'Concrete',
                    '12647798329',
                },
                {
                    'DiamondPlate',
                    '128808789797567',
                },
                {
                    'Fabric',
                    '128808789797567',
                },
                {
                    'Granite',
                    '4722586771',
                },
                {
                    'Grass',
                    '17303981964',
                },
                {
                    'Ice',
                    '17303981964',
                },
                {
                    'Marble',
                    '17303981964',
                },
                {
                    'Metal',
                    '114917525242362',
                },
                {
                    'Sand',
                    '114917525242362',
                },
                {
                    'Slate',
                    '114917525242362',
                },
            }
        elseif ap == 'minecraft' then
            aq = {
                {
                    'Wood',
                    '128754006217410',
                },
                {
                    'WoodPlanks',
                    '8676581022',
                },
                {
                    'Brick',
                    '8139086777',
                },
                {
                    'Cobblestone',
                    '17874801808',
                },
                {
                    'Concrete',
                    '9405731606',
                },
                {
                    'DiamondPlate',
                    '14197861013',
                },
                {
                    'Fabric',
                    '9744916443',
                },
                {
                    'Granite',
                    '4714662147',
                },
                {
                    'Grass',
                    '9267183930',
                },
                {
                    'Ice',
                    '11413423466',
                },
                {
                    'Marble',
                    '14974016515',
                },
                {
                    'Metal',
                    '14524282848',
                },
                {
                    'Sand',
                    '11119324718',
                },
                {
                    'Slate',
                    '7801228489',
                },
            }
        elseif ap == 'minecraft2' then
            aq = {
                {
                    'Slate',
                    '8676746437',
                },
                {
                    'Grass',
                    '9267183930',
                },
                {
                    'Sand',
                    '12624140843',
                },
                {
                    'Wood',
                    '3258599312',
                },
                {
                    'Brick',
                    '10777285622',
                },
                {
                    'Concrete',
                    '15622710576',
                },
                {
                    'CorrodedMetal',
                    '78612695839404',
                },
                {
                    'Metal',
                    '121650613091353',
                },
                {
                    'WoodPlanks',
                    '8676581022',
                },
            }
        elseif ap == 'icey' then
            aq = {
                {
                    'Wood',
                    '5933003775',
                },
                {
                    'WoodPlanks',
                    '5933003775',
                },
                {
                    'Brick',
                    '17295828838',
                },
                {
                    'Cobblestone',
                    '11760888310',
                },
                {
                    'Concrete',
                    '109017797659108',
                },
                {
                    'DiamondPlate',
                    '11760888310',
                },
                {
                    'Fabric',
                    '140018484507153',
                },
                {
                    'Granite',
                    '16833201065',
                },
                {
                    'Grass',
                    '140018484507153',
                },
                {
                    'Ice',
                    '1090177976591089',
                },
                {
                    'Marble',
                    '62967586',
                },
                {
                    'Metal',
                    '11760888310',
                },
                {
                    'Sand',
                    '16833201065',
                },
                {
                    'Slate',
                    '7397414089',
                },
            }
        elseif ap == 'weed minecraft' then
            local ar = {
                'Wood',
                'WoodPlanks',
                'Brick',
                'Cobblestone',
                'Concrete',
                'DiamondPlate',
                'Fabric',
                'Granite',
                'Grass',
                'Ice',
                'Marble',
                'Metal',
                'Sand',
            }

            for Z, _ in q(ar)do
                table.insert(aq, {
                    _,
                    '4722588177',
                })
            end
        end

        ak = aq

        if getgenv().TextureThemeEnabled and #ak > 0 then
            Y(ak)
        end
    end,
}

local ap

pcall(function()
    ap = U.PlayerGui.TopbarStandard.Holders.Left.Widget.IconButton.Menu.IconSpot.Contents.IconLabelContainer.IconLabel
    _G.OriginalRegionText = ap.Text
end)
ah:toggle{
    name = 'enabled',
    flag = 'region_enabled',
    callback = function(aq)
        _G.RegionSpoofer_Enabled = aq

        if ap then
            ap.Text = (aq and _G.RegionSpoofer_Text and _G.RegionSpoofer_Text ~= '') and _G.RegionSpoofer_Text or _G.OriginalRegionText
        end
    end,
}
ah:textbox{
    name = 'ur text',
    flag = 'region_custom_text',
    callback = function(aq)
        _G.RegionSpoofer_Text = aq

        if _G.RegionSpoofer_Enabled and ap and aq ~= '' then
            ap.Text = aq
        end
    end,
}
T.RenderStepped:Connect(LPH_NO_VIRTUALIZE(function()
    if _G.fovonn then
        V.FieldOfView = _G.fovalllll
    else
        V.FieldOfView = _G.defaultFOV
    end
    if _G.aspectEnabled then
        local aq = getgenv().Resolution

        V.CFrame = V.CFrame * CFrame.new(0, 0, 0, aq.x, 0, 0, 0, aq.y, 0, 0, 0, 1)
    end
    if _G.RegionSpoofer_Enabled and ap and _G.RegionSpoofer_Text and _G.RegionSpoofer_Text ~= '' then
        ap.Text = _G.RegionSpoofer_Text
    end
end))

_G.hit_effect_color = Color3.fromRGB(255, 81, 0)
_G.hit_effect_enabled = false
_G.selected_hit_effect = 'Nova'
_G.hiteffectTable = {
    Nova = function(aq)
        local ar = Instance.new'Part'

        ar.Position = aq
        ar.Anchored = true
        ar.Transparency = 1
        ar.CanCollide = false
        ar.Parent = Q

        local Z = ColorSequence.new(_G.hit_effect_color)
        local _ = Instance.new'ParticleEmitter'

        _.Color = Z
        _.Lifetime = NumberRange.new(0.5, 0.5)
        _.LightEmission = 1
        _.LockedToPart = true
        _.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
        _.Rate = 0
        _.Size = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0, 0),
            NumberSequenceKeypoint.new(1, 10, 0),
        }
        _.Speed = NumberRange.new(1.5, 1.5)
        _.Texture = 'rbxassetid://1084991215'
        _.Transparency = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 1, 0),
            NumberSequenceKeypoint.new(0.0996047, 0, 0),
            NumberSequenceKeypoint.new(0.602372, 0, 0),
            NumberSequenceKeypoint.new(1, 1, 0),
        }
        _.ZOffset = 1
        _.Parent = ar

        local as = Instance.new'ParticleEmitter'

        as.Color = Z
        as.Lifetime = NumberRange.new(0.5, 0.5)
        as.LightEmission = 1
        as.LockedToPart = true
        as.Rate = 0
        as.Size = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0, 0),
            NumberSequenceKeypoint.new(1, 10, 0),
        }
        as.Speed = NumberRange.new(0, 0)
        as.Texture = 'rbxassetid://1084991215'
        as.Transparency = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 1, 0),
            NumberSequenceKeypoint.new(0.0996047, 0, 0),
            NumberSequenceKeypoint.new(0.601581, 0, 0),
            NumberSequenceKeypoint.new(1, 1, 0),
        }
        as.ZOffset = 1
        as.Parent = ar

        local at = Instance.new'ParticleEmitter'

        at.Color = Z
        at.Lifetime = NumberRange.new(0.2, 0.5)
        at.LockedToPart = true
        at.Orientation = Enum.ParticleOrientation.VelocityParallel
        at.Rate = 0
        at.Rotation = NumberRange.new(-90, 90)
        at.Size = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 1, 0),
            NumberSequenceKeypoint.new(1, 8.5, 1.5),
        }
        at.Speed = NumberRange.new(0.1, 0.1)
        at.SpreadAngle = Vector2.new(180, 180)
        at.Texture = 'http://www.roblox.com/asset/?id=6820680001'
        at.Transparency = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 1, 0),
            NumberSequenceKeypoint.new(0.200791, 0, 0),
            NumberSequenceKeypoint.new(0.699605, 0, 0),
            NumberSequenceKeypoint.new(1, 1, 0),
        }
        at.ZOffset = 1.5
        at.Parent = ar

        _:Emit(1)
        as:Emit(1)
        at:Emit(1)
        task.delay(1, function()
            ar:Destroy()
        end)
    end,
    Blood = function(aq)
        local ar = Instance.new('Part', Q)

        ar.Transparency = 1
        ar.Size = Vector3.new(2, 2, 2)
        ar.Position = aq
        ar.CanCollide = false
        ar.Anchored = true

        local as = Instance.new('Attachment', ar)
        local at = Instance.new('ParticleEmitter', as)

        at.Acceleration = Vector3.new(0, -75, 0)
        at.Color = ColorSequence.new(_G.hit_effect_color)
        at.Lifetime = NumberRange.new(0.25, 0.5)
        at.Orientation = Enum.ParticleOrientation.VelocityParallel
        at.Rate = 100
        at.Size = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0.125, 0),
            NumberSequenceKeypoint.new(1, 0.25, 0.1),
        }
        at.Speed = NumberRange.new(5, 15)
        at.SpreadAngle = Vector2.new(90, 90)
        at.Texture = 'rbxassetid://4509687978'
        at.Transparency = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 1, 0),
            NumberSequenceKeypoint.new(0.25, 0, 0),
            NumberSequenceKeypoint.new(1, 1, 0),
        }

        at:Emit(3)
        task.delay(1, function()
            ar:Destroy()
        end)
    end,
    Glitch = function(aq)
        local ar = Instance.new('Part', Q)

        ar.Transparency = 1
        ar.Size = Vector3.new(2.6, 5.52, 2.8)
        ar.Position = aq
        ar.CanCollide = false
        ar.Anchored = true

        local as = 'rbxassetid://6888586040'

        for at = 1, 10 do
            local Z = Instance.new('ParticleEmitter', ar)

            Z.Color = ColorSequence.new(_G.hit_effect_color)
            Z.Lifetime = NumberRange.new(0.1, 0.1)
            Z.Rate = 30
            Z.Size = NumberSequence.new(0.4)
            Z.Texture = as
            Z.Transparency = NumberSequence.new(0)
        end

        task.delay(3, function()
            ar:Destroy()
        end)
    end,
    Slash = function(aq)
        local ar = Instance.new('Part', Q)

        ar.Size = Vector3.new(2, 2, 2)
        ar.Anchored = true
        ar.CanCollide = false
        ar.Transparency = 1
        ar.Position = aq

        local as = Instance.new('Attachment', ar)
        local at = Instance.new('ParticleEmitter', as)

        at.Lifetime = NumberRange.new(0.19, 0.38)
        at.Transparency = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.1932907, 0),
            NumberSequenceKeypoint.new(0.778754, 0),
            NumberSequenceKeypoint.new(1, 1),
        }
        at.LightEmission = 10
        at.Color = ColorSequence.new(_G.hit_effect_color)
        at.Speed = NumberRange.new(0.08)
        at.Brightness = 4
        at.Size = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(0.39, 8.8),
            NumberSequenceKeypoint.new(1, 11.4),
        }
        at.Texture = 'rbxassetid://12509373457'
        at.RotSpeed = NumberRange.new(800, 1000)
        at.Orientation = Enum.ParticleOrientation.VelocityPerpendicular

        task.delay(1.5, function()
            ar:Destroy()
        end)
    end,
    Cosmic = function(aq)
        local ar = Instance.new('Part', Q)

        ar.Size = Vector3.new(2, 2, 2)
        ar.Anchored = true
        ar.CanCollide = false
        ar.Transparency = 1
        ar.Position = aq

        local as = Instance.new('Attachment', ar)
        local at = ColorSequence.new(_G.hit_effect_color)

        local function Z(_, au, av)
            local aw = Instance.new('ParticleEmitter', as)

            aw.Color = at
            aw.Texture = _
            aw.Size = au
            aw.Lifetime = av
            aw.Brightness = 5

            return aw
        end

        Z('rbxassetid://8708637750', NumberSequence.new(9, 16), NumberRange.new(0.16))
        Z('rbxassetid://8196169974', NumberSequence.new(0, 11), NumberRange.new(0.3))
        task.delay(1.5, function()
            ar:Destroy()
        end)
    end,
    CrescentSlash = function(aq)
        local ar = Instance.new('Part', Q)

        ar.Size = Vector3.new(2, 2, 2)
        ar.Anchored = true
        ar.CanCollide = false
        ar.Transparency = 1
        ar.Position = aq

        local as = Instance.new('Attachment', ar)
        local at = ColorSequence.new(_G.hit_effect_color)
        local au = Instance.new('ParticleEmitter', as)

        au.Lifetime = NumberRange.new(0.16)
        au.Color = at
        au.Brightness = 5
        au.Size = NumberSequence.new(9, 16)
        au.Texture = 'rbxassetid://8708637750'

        local av = Instance.new('ParticleEmitter', as)

        av.Lifetime = NumberRange.new(0.2, 0.7)
        av.Color = at
        av.Speed = NumberRange.new(90, 140)
        av.Texture = 'rbxassetid://8030734851'

        task.delay(3, function()
            ar:Destroy()
        end)
    end,
}

local aq = M:section{
    name = 'hit effects',
}

aq:toggle{
    name = 'enabled',
    flag = 'hit_effect_toggle',
    callback = function(ar)
        _G.hit_effect_enabled = ar
    end,
}
aq:colorpicker{
    flag = 'hit_effect_color_picker',
    color = _G.hit_effect_color,
    callback = function(ar, as)
        _G.hit_effect_color = ar
    end,
}
aq:dropdown{
    name = 'effect',
    flag = 'hit_effect_dropdown',
    items = {
        'Nova',
        'Blood',
        'Glitch',
        'Slash',
        'Cosmic',
        'CrescentSlash',
    },
    callback = function(ar)
        _G.selected_hit_effect = ar
    end,
}

local ar = U.Character or U.CharacterAdded:Wait()

U.CharacterAdded:Connect(function(as)
    ar = as
end)

if workspace:FindFirstChild'Ignored' and workspace.Ignored:FindFirstChild'Siren' and workspace.Ignored.Siren:FindFirstChild'Radius' then
    workspace.Ignored.Siren.Radius.ChildAdded:Connect(LPH_NO_VIRTUALIZE(function(as)
        if as.Name ~= 'BULLET_RAYS' then
            return
        end

        local at = ar.Name

        if not as:GetAttribute'OwnerCharacter' or as:GetAttribute'OwnerCharacter' ~= at then
            return
        end
        if not _G.hit_effect_enabled then
            return
        end

        task.delay(0.05, function()
            if not as.Parent then
                return
            end

            local au = as.Position
            local av = as.CFrame.LookVector
            local aw = RaycastParams.new()

            aw.FilterDescendantsInstances = {
                ar,
                workspace.Ignored,
            }
            aw.FilterType = Enum.RaycastFilterType.Exclude

            local Z = workspace:Raycast(au, av * 1000, aw)

            if Z and Z.Instance then
                local _ = Z.Instance
                local ax = Z.Position
                local ay = _:FindFirstAncestorWhichIsA'Model'

                if ay and ay:FindFirstChild'Humanoid' and game.Players:GetPlayerFromCharacter(ay) then
                    local az = _G.hiteffectTable[_G.selected_hit_effect]

                    if az then
                        az(ax)
                    end
                end
            end
        end)
    end))
end

local as = M:section{
    name = 'brainrot spawner',
}

_G.dokjgongiudbfiudbeiugsb = 'rbxassetid://72466520546640'
_G.slighdfiugshdfiug = 5
_G.backflip_chance = 30
_G.oifughdfiughdfiug = game:GetService'Players'.LocalPlayer
_G.pfoighfduighdfiug = game:GetService'RunService'

local at = {}
local au

_G.qwoifughdfiugh = LPH_NO_VIRTUALIZE(function(av)
    local aw = 30

    for ax = 1, aw do
        local ay = math.rad(math.random(0, 360))
        local az = math.random(100, 1500)
        local Z = Vector3.new(math.cos(ay) * az, 500, math.sin(ay) * az)
        local _ = av + Z
        local aA = RaycastParams.new()

        aA.FilterType = Enum.RaycastFilterType.Exclude

        local aB = workspace:Raycast(_, Vector3.new(0, -2E3, 0), aA)

        if aB then
            local aC = RaycastParams.new()

            aC.FilterType = Enum.RaycastFilterType.Exclude

            local aD = workspace:Raycast(aB.Position + Vector3.new(0, 5, 0), Vector3.new(0, 20, 0), aC)

            if not aD then
                return aB.Position
            end
        end
    end

    return av + Vector3.new(math.random(-50, 50), 0, math.random(-50, 50))
end)

local function av()
    if au then
        au:Disconnect()

        au = nil
    end

    for aw, ax in r(at)do
        if ax.Model then
            ax.Model:Destroy()
        end
    end

    table.clear(at)
end
local function aw()
    av()

    local ax, ay = pcall(function()
        return game:GetObjects(_G.dokjgongiudbfiudbeiugsb)
    end)

    if ax and ay then
        local az = _G.oifughdfiughdfiug.Character or _G.oifughdfiughdfiug.CharacterAdded:Wait()
        local aA = az:WaitForChild'HumanoidRootPart'

        for aB = 1, _G.slighdfiugshdfiug do
            for aC, aD in r(ay)do
                local Z = aD:Clone()

                Z.Parent = workspace

                for _, aE in r(Z:GetDescendants())do
                    if aE:IsA'BasePart' then
                        aE.CanCollide = false
                        aE.CanTouch = false
                        aE.CanQuery = false
                    end
                end

                local aE = _G.qwoifughdfiugh(aA.Position)
                local _ = _G.qwoifughdfiugh(aE)

                table.insert(at, {
                    Model = Z,
                    CurrentPos = aE,
                    TargetPos = _,
                    CurrentLook = CFrame.lookAt(aE, _),
                    Speed = math.random(14, 24),
                    JumpHeight = 0,
                    JumpVel = 0,
                    IsJumping = false,
                    IsBackflipping = false,
                    FlipRot = 0,
                })
            end
        end

        au = _G.pfoighfduighdfiug.Heartbeat:Connect(LPH_JIT_MAX(function(aB)
            local aC = _G.oifughdfiughdfiug.Character
            local aD = aC and aC:FindFirstChild'HumanoidRootPart'

            if not aD then
                return
            end

            for aE = 1, #at do
                local Z = at[aE]
                local _ = Z.Model

                if not _ or not _.Parent then
                    continue
                end

                local aF = (Vector3.new(Z.TargetPos.X, Z.CurrentPos.Y, Z.TargetPos.Z) - Z.CurrentPos).Magnitude

                if aF < 12 then
                    Z.TargetPos = _G.qwoifughdfiugh(Z.CurrentPos)
                end

                local aG = RaycastParams.new()

                aG.FilterDescendantsInstances = {_, aC}
                aG.FilterType = Enum.RaycastFilterType.Exclude

                local aH = workspace:Raycast(Z.CurrentPos + Vector3.new(0, 4, 0), Z.CurrentLook.LookVector * 12, aG)

                if aH then
                    Z.TargetPos = _G.qwoifughdfiugh(Z.CurrentPos)
                end
                if not Z.IsJumping and math.random(1, 45) == 1 then
                    Z.IsJumping = true
                    Z.JumpVel = math.random(45, 65)

                    if math.random(1, 100) <= _G.backflip_chance then
                        Z.IsBackflipping = true
                        Z.FlipRot = 0
                    end
                end
                if Z.IsJumping then
                    Z.JumpVel = Z.JumpVel + (-110 * aB)
                    Z.JumpHeight = Z.JumpHeight + (Z.JumpVel * aB)

                    if Z.IsBackflipping then
                        Z.FlipRot = Z.FlipRot + (aB * 12)
                    end
                    if Z.JumpHeight <= 0 then
                        Z.JumpHeight = 0
                        Z.JumpVel = 0
                        Z.IsJumping = false
                        Z.IsBackflipping = false
                    end
                end

                local aI = CFrame.lookAt(Z.CurrentPos, Vector3.new(Z.TargetPos.X, Z.CurrentPos.Y, Z.TargetPos.Z))

                Z.CurrentLook = Z.CurrentLook:Lerp(aI, 4.5 * aB)
                Z.CurrentPos = Z.CurrentPos + (Z.CurrentLook.LookVector * Z.Speed * aB)

                local aJ = workspace:Raycast(Z.CurrentPos + Vector3.new(0, 100, 0), Vector3.new(0, -500, 0), aG)
                local aK = aJ and aJ.Position.Y or Z.CurrentPos.Y
                local aL = math.sin(n() * (Z.Speed * 0.9))
                local aM = CFrame.new(Z.CurrentPos.X, aK + (math.abs(aL) * 0.7) + Z.JumpHeight, Z.CurrentPos.Z) * Z.CurrentLook.Rotation * CFrame.Angles(math.rad((Z.JumpVel * 0.04) * 22) + (Z.IsBackflipping and Z.FlipRot or 0), 0, math.rad(aL * 12))

                _:PivotTo(aM)
            end
        end))
    end
end

as:toggle{
    name = 'enabled',
    flag = 'hit_effect_togg',
    callback = function(ax)
        if ax then
            aw()
        else
            av()
        end
    end,
}
as:slider{
    name = 'brainrots',
    flag = 'lighting_f',
    min = 1,
    max = 50,
    default = 5,
    interval = 1,
    callback = function(ax)
        _G.slighdfiugshdfiug = ax
    end,
}
as:slider{
    name = 'backflip chance',
    flag = 'lighting_f',
    min = 0,
    max = 100,
    default = 18,
    suffix = '%',
    interval = 1,
    callback = function(ax)
        _G.backflip_chance = ax
    end,
}

_G.LightingSettings = _G.LightingSettings or {
    Enabled = false,
    Ambient = {
        Enabled = false,
        Color = Color3.fromRGB(255, 255, 255),
    },
    ColorShiftTop = {
        Enabled = false,
        Color = Color3.fromRGB(255, 255, 255),
    },
    ColorShiftBottom = {
        Enabled = false,
        Color = Color3.fromRGB(0, 0, 0),
    },
    Fog = {
        Enabled = false,
        Color = Color3.fromRGB(100, 100, 150),
        Start = 0,
        End = 100,
    },
    ClockTime = {
        Enabled = false,
        Value = 12,
    },
}

local ax = game:GetService'Lighting'
local ay = {
    Ambient = ax.Ambient,
    ColorShift_Top = ax.ColorShift_Top,
    ColorShift_Bottom = ax.ColorShift_Bottom,
    FogColor = ax.FogColor,
    FogEnd = ax.FogEnd,
    FogStart = ax.FogStart,
    ClockTime = ax.ClockTime,
}
local az = LPH_NO_VIRTUALIZE(function()
    local az = _G.LightingSettings

    if not az.Enabled then
        ax.Ambient = ay.Ambient
        ax.ColorShift_Top = ay.ColorShift_Top
        ax.ColorShift_Bottom = ay.ColorShift_Bottom
        ax.FogColor = ay.FogColor
        ax.FogEnd = ay.FogEnd
        ax.FogStart = ay.FogStart
        ax.ClockTime = ay.ClockTime

        return
    end

    ax.Ambient = az.Ambient.Enabled and az.Ambient.Color or ay.Ambient
    ax.ColorShift_Top = az.ColorShiftTop.Enabled and az.ColorShiftTop.Color or ay.ColorShift_Top
    ax.ColorShift_Bottom = az.ColorShiftBottom.Enabled and az.ColorShiftBottom.Color or ay.ColorShift_Bottom

    if az.Fog.Enabled then
        ax.FogColor = az.Fog.Color
        ax.FogEnd = az.Fog.End
        ax.FogStart = az.Fog.Start
    else
        ax.FogColor = ay.FogColor
        ax.FogEnd = ay.FogEnd
        ax.FogStart = ay.FogStart
    end

    ax.ClockTime = az.ClockTime.Enabled and az.ClockTime.Value or ay.ClockTime
end)

game:GetService'RunService'.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
    local aA = _G.LightingSettings

    if aA and aA.Enabled and aA.ClockTime.Enabled then
        ax.ClockTime = aA.ClockTime.Value
    end
end))

local aA = M:section{
    name = 'lighting',
    side = 'right',
}

aA:toggle{
    name = 'enabled',
    flag = 'lighting_master',
    default = _G.LightingSettings.Enabled,
    callback = function(aB)
        _G.LightingSettings.Enabled = aB

        az()
    end,
}
aA:toggle{
    name = 'ambient',
    flag = 'lighting_ambient_toggle',
    callback = function(aB)
        _G.LightingSettings.Ambient.Enabled = aB

        az()
    end,
}
aA:colorpicker{
    name = 'ambient color',
    flag = 'lighting_ambient_color',
    color = Color3.fromRGB(255, 255, 255),
    callback = function(aB)
        _G.LightingSettings.Ambient.Color = aB

        az()
    end,
}
aA:toggle{
    name = 'color shift top',
    flag = 'lighting_top_toggle',
    callback = function(aB)
        _G.LightingSettings.ColorShiftTop.Enabled = aB

        az()
    end,
}
aA:colorpicker{
    name = 'top color',
    flag = 'lighting_top_color',
    color = Color3.fromRGB(255, 100, 100),
    callback = function(aB)
        _G.LightingSettings.ColorShiftTop.Color = aB

        az()
    end,
}
aA:toggle{
    name = 'color shift bottom',
    flag = 'lighting_bot_toggle',
    callback = function(aB)
        _G.LightingSettings.ColorShiftBottom.Enabled = aB

        az()
    end,
}
aA:colorpicker{
    name = 'bottom color',
    flag = 'lighting_bot_color',
    color = Color3.fromRGB(0, 50, 150),
    callback = function(aB)
        _G.LightingSettings.ColorShiftBottom.Color = aB

        az()
    end,
}
aA:toggle{
    name = 'custom fog',
    flag = 'lighting_fog_toggle',
    callback = function(aB)
        _G.LightingSettings.Fog.Enabled = aB

        az()
    end,
}
aA:colorpicker{
    name = 'fog color',
    flag = 'lighting_fog_color',
    color = Color3.fromRGB(80, 80, 120),
    callback = function(aB)
        _G.LightingSettings.Fog.Color = aB

        az()
    end,
}
aA:slider{
    name = 'fog end',
    flag = 'lighting_fogend',
    min = 0,
    max = 1000,
    default = 100,
    interval = 0.1,
    callback = function(aB)
        _G.LightingSettings.Fog.End = aB

        az()
    end,
}
aA:toggle{
    name = 'custom time',
    flag = 'lighting_time_toggle',
    callback = function(aB)
        _G.LightingSettings.ClockTime.Enabled = aB

        az()
    end,
}
aA:slider{
    name = 'clock time',
    flag = 'lighting_time_val',
    min = 0,
    max = 24,
    default = 12,
    interval = 0.1,
    callback = function(aB)
        _G.LightingSettings.ClockTime.Value = aB

        az()
    end,
}

local aB = M:section{
    name = 'motion blur',
    side = 'right',
}

_G.MotionBlurObj = nil
_G.MotionBlurLastVector = nil
_G.MotionBlurSmoothSize = 0
_G.MotionBlurConnection = nil

aB:toggle{
    name = 'enabled',
    flag = 'mo_T_I_O_N_B_L_U_R',
    callback = function(aC)
        _G.MotionBlurToggle = aC

        if _G.MotionBlurToggle then
            if not _G.MotionBlurObj then
                _G.MotionBlurObj = Instance.new'BlurEffect'
                _G.MotionBlurObj.Parent = ax
                _G.MotionBlurObj.Size = 0
            end
            if not _G.MotionBlurConnection then
                _G.MotionBlurLastVector = V.CFrame.LookVector
                _G.MotionBlurConnection = T.RenderStepped:Connect(function(aD)
                    if not _G.MotionBlurObj or not _G.MotionBlurLastVector then
                        _G.MotionBlurLastVector = V.CFrame.LookVector

                        return
                    end

                    local aE = V.CFrame.LookVector
                    local aF = _G.MotionBlurIntensity or 0
                    local aG = (aE - _G.MotionBlurLastVector).Magnitude * (aF * 110) * aD

                    _G.MotionBlurSmoothSize = _G.MotionBlurSmoothSize + (aG - _G.MotionBlurSmoothSize) * math.clamp(aD * 30, 0, 1)
                    _G.MotionBlurObj.Size = math.clamp(_G.MotionBlurSmoothSize, 0, 56)
                    _G.MotionBlurLastVector = aE
                end)
            end
        else
            if _G.MotionBlurConnection then
                _G.MotionBlurConnection:Disconnect()

                _G.MotionBlurConnection = nil
            end
            if _G.MotionBlurObj then
                _G.MotionBlurObj:Destroy()

                _G.MotionBlurObj = nil
            end

            _G.MotionBlurLastVector = nil
            _G.MotionBlurSmoothSize = 0
        end
    end,
}
aB:slider{
    name = 'blur intensity',
    flag = 'f__F_F__FSCCnfffj3c',
    min = 0,
    max = 100,
    default = 0,
    interval = 0.1,
    callback = function(aC)
        _G.MotionBlurIntensity = aC
    end,
}

_G.WeatherPart = _G.WeatherPart or nil
_G.WeatherEmitter = _G.WeatherEmitter or nil
_G.WeatherEnabled = false
_G.WeatherType = 'Rain'
_G.WeatherColor = Color3.fromRGB(255, 136, 0)
_G.WeatherRateMultiplier = 1

local aC = {
    Rain = {
        Speed = NumberRange.new(60, 60),
        LockedToPart = true,
        Rate = 600,
        Texture = 'rbxassetid://1822883048',
        EmissionDirection = Enum.NormalId.Bottom,
        Transparency = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 1),
            NumberSequenceKeypoint.new(0.25, 0.78),
            NumberSequenceKeypoint.new(0.75, 0.78),
            NumberSequenceKeypoint.new(1, 1),
        },
        Lifetime = NumberRange.new(0.8, 0.8),
        LightEmission = 0.05,
        LightInfluence = 0.9,
        Orientation = Enum.ParticleOrientation.FacingCameraWorldUp,
        Size = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 10),
            NumberSequenceKeypoint.new(1, 10),
        },
    },
    Snow = {
        Transparency = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0.73),
            NumberSequenceKeypoint.new(0.973, 0.76),
            NumberSequenceKeypoint.new(1, 1),
        },
        Texture = 'http://www.roblox.com/asset/?id=99851851',
        SpreadAngle = Vector2.new(50, 50),
        Speed = NumberRange.new(30, 30),
        LightEmission = 0.5,
        Rate = 1000,
        EmissionDirection = Enum.NormalId.Bottom,
        Size = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0.33),
            NumberSequenceKeypoint.new(0.551, 0.4),
            NumberSequenceKeypoint.new(1, 0.33),
        },
    },
    ['Light Rain'] = {
        LockedToPart = true,
        Rate = 500,
        Squash = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 3),
            NumberSequenceKeypoint.new(1, 3),
        },
        LightInfluence = 0.3,
        Transparency = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0),
            NumberSequenceKeypoint.new(0.435, 0),
            NumberSequenceKeypoint.new(1, 0),
        },
        Texture = 'rbxasset://textures/particles/sparkles_main.dds',
        Speed = NumberRange.new(30, 50),
        Lifetime = NumberRange.new(9, 9),
        LightEmission = 0.5,
        Brightness = 2,
        EmissionDirection = Enum.NormalId.Bottom,
        Orientation = Enum.ParticleOrientation.FacingCameraWorldUp,
        Size = NumberSequence.new{
            NumberSequenceKeypoint.new(0, 0.2),
            NumberSequenceKeypoint.new(1, 0.2),
        },
    },
}
local aD = LPH_NO_VIRTUALIZE(function()
    if _G.WeatherEmitter then
        _G.WeatherEmitter:Destroy()
    end
    if not _G.WeatherPart then
        return
    end

    local aD = aC[_G.WeatherType]
    local aE = Instance.new'ParticleEmitter'

    for aF, aG in r(aD)do
        aE[aF] = aG
    end

    aE.Color = ColorSequence.new(_G.WeatherColor)
    aE.Rate = aD.Rate * _G.WeatherRateMultiplier
    aE.Parent = _G.WeatherPart
    _G.WeatherEmitter = aE
end)
local aE = LPH_NO_VIRTUALIZE(function()
    if _G.WeatherPart then
        _G.WeatherPart:Destroy()

        _G.WeatherPart = nil
    end

    _G.WeatherEmitter = nil
end)

T.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
    if _G.WeatherEnabled and _G.WeatherPart then
        _G.WeatherPart.CFrame = V.CFrame * CFrame.new(0, 25, 0)
    end
end))

local aF = M:section{
    name = 'weather',
    side = 'right',
}

aF:toggle{
    name = 'enabled',
    flag = 'weather_enabled',
    default = false,
    callback = function(aG)
        _G.WeatherEnabled = aG

        if aG then
            _G.WeatherPart = Instance.new'Part'
            _G.WeatherPart.Size = Vector3.new(120, 5, 120)
            _G.WeatherPart.CanCollide = false
            _G.WeatherPart.Massless = true
            _G.WeatherPart.CastShadow = false
            _G.WeatherPart.Transparency = 1
            _G.WeatherPart.Anchored = true
            _G.WeatherPart.Name = 'WeatherPart'
            _G.WeatherPart.Parent = workspace

            aD()
        else
            aE()
        end
    end,
}
aF:colorpicker{
    flag = 'weather_color',
    color = Color3.fromRGB(255, 136, 0),
    callback = function(aG)
        _G.WeatherColor = aG

        if _G.WeatherEmitter then
            _G.WeatherEmitter.Color = ColorSequence.new(aG)
        end
    end,
}
aF:dropdown{
    name = 'type',
    flag = 'weather_type',
    items = {
        'Rain',
        'Snow',
        'Light Rain',
    },
    callback = function(aG)
        _G.WeatherType = aG

        if _G.WeatherEnabled then
            aD()
        end
    end,
}
aF:slider{
    name = 'rate multiplier',
    flag = 'weather_rate',
    min = 0,
    max = 500,
    default = 100,
    callback = function(aG)
        _G.WeatherRateMultiplier = aG / 100

        if _G.WeatherEmitter then
            local aH = aC[_G.WeatherType].Rate

            _G.WeatherEmitter.Rate = aH * _G.WeatherRateMultiplier
        end
    end,
}

_G.hitnotifyenabled = false
_G.hitnotifyduration = 3
_G.hitcustomnotify = false
_G.hitcustomtext = 'hit (user) for (%)'
_G.lasthitnotifyhealth = {}

local aG = M:section{
    name = 'hit notifications',
    side = 'right',
}

aG:toggle{
    name = 'enabled',
    flag = 'hit_notify_enabled',
    default = false,
    callback = function(aH)
        _G.hitnotifyenabled = aH
    end,
}
aG:slider{
    name = 'duration',
    flag = 'hit_notify_duration',
    min = 1,
    max = 10,
    default = 3,
    interval = 0.1,
    callback = function(aH)
        _G.hitnotifyduration = aH
    end,
}
aG:toggle{
    name = 'use custom notification',
    flag = 'hit_notify_custom_toggle',
    default = false,
    callback = function(aH)
        _G.hitcustomnotify = aH
    end,
}
aG:textbox{
    name = 'custom text format',
    flag = 'hit_notify_custom_text',
    default = 'cracked (user) for (%) in the head',
    callback = function(aH)
        _G.hitcustomtext = aH
    end,
}
workspace.Ignored.Siren.Radius.ChildAdded:Connect(LPH_NO_VIRTUALIZE(function(aH)
    if not _G.hitnotifyenabled or aH.Name ~= 'BULLET_RAYS' then
        return
    end

    local aI = game.Players.LocalPlayer.Character

    if not aI then
        return
    end

    local aJ = aH:GetAttribute'OwnerCharacter'

    if not aJ or aJ ~= aI.Name then
        return
    end

    local aK = RaycastParams.new()

    aK.FilterDescendantsInstances = {aI}
    aK.FilterType = Enum.RaycastFilterType.Exclude

    local aL = workspace:Raycast(aH.CFrame.Position, aH.CFrame.LookVector * 1000, aK)

    if not aL or not aL.Instance then
        return
    end

    local aM = aL.Instance:FindFirstAncestorOfClass'Model'

    if not aM then
        return
    end

    local Z = game.Players:GetPlayerFromCharacter(aM)

    if not Z then
        return
    end

    local _ = aM:FindFirstChildOfClass'Humanoid'

    if not _ then
        return
    end

    local aN = _G.lasthitnotifyhealth[Z] or _.MaxHealth
    local aO = _.Health
    local aP = math.max(aN - aO, 0)

    if aP > 0 then
        _G.lasthitnotifyhealth[Z] = aO

        local aQ = _G.hitcustomnotify and _G.hitcustomtext or 'cracked (user) for (%)'
        local aR = aQ:gsub('%(user%)', Z.Name):gsub('%(%)', tostring(math.floor(aP)))

        H:notification{
            text = aR,
            duration = _G.hitnotifyduration,
        }
    else
        _G.lasthitnotifyhealth[Z] = aO
    end
end))

_G.UIS = game:GetService'UserInputService'
_G.RS = game:GetService'RunService'
_G.LP = game:GetService'Players'.LocalPlayer
_G.lastrecord = nil
_G.wenabled = false
_G.keytooenabled = false
_G.wvalue = 1
_G.cframeactive = false
_G.keyheldcframe = false
_G.cframevalue = 1
_G.flyactive = false
_G.keyheldfly = false
_G.flyvalue = 1
_G.MovementSection = O:section{
    name = 'movement',
    side = 'left',
}

_G.MovementSection:toggle{
    name = 'walkspeed',
    flag = 'WalkSpeedToggle',
    default = false,
    callback = function(aH)
        _G.wenabled = aH

        if not aH then
            local aI = _G.LP.Character
            local aJ = aI and aI:FindFirstChildWhichIsA'Humanoid'

            if aJ and _G.lastrecord then
                aJ.WalkSpeed = _G.lastrecord
                _G.lastrecord = nil
            end
        end
    end,
}
_G.MovementSection:keybind{
    default = nil,
    flag = 'wspd_key',
    callback = function()
        _G.keytooenabled = not _G.keytooenabled
    end,
}
_G.MovementSection:slider{
    name = 'walkspeed value',
    flag = 'wspd_value',
    min = 1,
    max = 500,
    default = 16,
    interval = 0.01,
    callback = function(aH)
        _G.wvalue = aH
    end,
}
_G.RS.RenderStepped:Connect(LPH_NO_VIRTUALIZE(function()
    local aH = _G.LP.Character
    local aI = aH and aH:FindFirstChildWhichIsA'Humanoid'

    if not aI then
        return
    end
    if _G.wenabled and _G.keytooenabled then
        if not _G.lastrecord then
            _G.lastrecord = aI.WalkSpeed
        end

        aI.WalkSpeed = _G.wvalue
    elseif _G.lastrecord then
        aI.WalkSpeed = _G.lastrecord
        _G.lastrecord = nil
    end
end))
_G.MovementSection:toggle{
    name = 'cframe speed',
    flag = 'cframespf_enabled',
    default = false,
    callback = function(aH)
        _G.cframeactive = aH
    end,
}
_G.MovementSection:keybind{
    default = nil,
    flag = 'cframespf_key',
    callback = function()
        _G.keyheldcframe = not _G.keyheldcframe
    end,
}
_G.MovementSection:slider{
    name = 'cframe speed value',
    flag = 'spdd_value',
    min = 1,
    max = 60,
    default = 1,
    interval = 1,
    callback = function(aH)
        _G.cframevalue = aH
    end,
}
_G.RS.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function(aH)
    if _G.cframeactive and _G.keyheldcframe then
        local aI = _G.LP.Character
        local aJ = aI and aI:FindFirstChild'HumanoidRootPart'
        local aK = aI and aI:FindFirstChildOfClass'Humanoid'

        if aJ and aK then
            aJ.CFrame = aJ.CFrame + (aK.MoveDirection * (aH * _G.cframevalue * 10))
        end
    end
end))
_G.MovementSection:toggle{
    name = 'cframe flight',
    flag = 'flight_enabled',
    default = false,
    callback = function(aH)
        _G.flyactive = aH
    end,
}
_G.MovementSection:keybind{
    default = nil,
    flag = 'flight_key',
    callback = function()
        _G.keyheldfly = not _G.keyheldfly
    end,
}
_G.MovementSection:slider{
    name = 'flight speed',
    flag = 'flight_speed',
    min = 1,
    max = 100,
    default = 1,
    interval = 1,
    callback = function(aH)
        _G.flyvalue = aH
    end,
}
_G.RS.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function(aH)
    if _G.flyactive and _G.keyheldfly then
        local aI = _G.LP.Character
        local aJ = aI and aI:FindFirstChild'HumanoidRootPart'
        local aK = aI and aI:FindFirstChildOfClass'Humanoid'
        local aL = _G.UIS

        if aJ and aK then
            local aM = aK.MoveDirection
            local aN = Vector3.new(0, (aL:IsKeyDown(Enum.KeyCode.Space) and _G.flyvalue / 8) or (aL:IsKeyDown(Enum.KeyCode.LeftShift) and -_G.flyvalue / 8) or 0, 0)

            aJ.CFrame = aJ.CFrame + ((aM * aH) * _G.flyvalue * 10)
            aJ.CFrame = aJ.CFrame + aN
            aJ.Velocity = (aJ.Velocity * Vector3.new(1, 0, 1)) + Vector3.new(0, 1.9, 0)
        end
    end
end))

_G.GunSection = O:section{
    name = 'gun settings',
    side = 'left',
}
_G.rf_s = pcall(function()
    return getconnections
end)

if _G.rf_s and s(getconnections) == 'function' then
    _G.rf_a = false
    _G.rf_c = nil
    _G.rf_o = {}
    _G.rf_m = 1
    _G.rf_r = LPH_NO_VIRTUALIZE(function(aH)
        if not aH:IsA'Tool' then
            return
        end

        local aI = getconnections(aH.Activated)

        for aJ = 1, #aI do
            local aK = aI[aJ]
            local aL, aM = pcall(debug.getinfo, aK.Function)

            if aL and aM then
                for aN = 1, aM.nups do
                    local aO, aP = pcall(debug.getupvalue, aK.Function, aN)

                    if aO and s(aP) == 'number' then
                        if not _G.rf_o[aK.Function] then
                            _G.rf_o[aK.Function] = {}
                        end
                        if _G.rf_o[aK.Function][aN] == nil then
                            _G.rf_o[aK.Function][aN] = aP
                        end

                        local aQ = _G.rf_o[aK.Function][aN]
                        local aR = math.max(aQ * _G.rf_m, 0)

                        pcall(debug.setupvalue, aK.Function, aN, aR)
                    end
                end
            end
        end
    end)

    _G.GunSection:toggle{
        name = 'rapid fire',
        flag = 'rapidff_enabled',
        callback = function(aH)
            _G.rf_a = aH

            if aH then
                if _G.rf_c then
                    _G.rf_c:Disconnect()
                end

                _G.rf_c = game:GetService'RunService'.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
                    local aI = game.Players.LocalPlayer.Character
                    local aJ = aI and aI:FindFirstChildOfClass'Tool'

                    if aJ then
                        _G.rf_r(aJ)
                    end
                end))
            else
                if _G.rf_c then
                    _G.rf_c:Disconnect()

                    _G.rf_c = nil
                end

                for aI, aJ in r(_G.rf_o)do
                    for aK, aL in r(aJ)do
                        pcall(debug.setupvalue, aI, aK, aL)
                    end
                end

                _G.rf_o = {}
            end
        end,
    }
    _G.GunSection:slider{
        name = 'fire rate',
        flag = 'rapidfire_val',
        min = 0,
        max = 1,
        default = 1,
        interval = 0.1,
        callback = function(aH)
            _G.rf_m = aH
        end,
    }
else
    warn'executor not supported (rapid fire)'
end

_G.spreaddd = {
    on = false,
    int = 100,
}
_G.mathranbynig = _G.mathranbynig or math.random
_G.spreadman_target = math

setreadonly(_G.spreadman_target, false)

_G.spreadman_target.random = newcclosure(function(...)
    _G.spreadman_args = {...}
    _G.spreadman_result = _G.mathranbynig(...)
    _G.is_spread_call = (#_G.spreadman_args == 0) or (_G.spreadman_args[1] == -5E-2 and _G.spreadman_args[2] == 0.05) or (_G.spreadman_args[1] == -0.1) or (_G.spreadman_args[1] == -5E-2)

    if not checkcaller() and _G.spreaddd.on and _G.is_spread_call then
        return _G.spreadman_result * (_G.spreaddd.int / 100)
    end

    return _G.spreadman_result
end)

setreadonly(_G.spreadman_target, true)
_G.GunSection:toggle{
    name = 'gun spread',
    flag = 'BLTSPRTG',
    callback = function(aH)
        _G.spreaddd.on = aH
    end,
}
_G.GunSection:slider{
    name = 'spread intensity',
    flag = 'bulletsprd_val',
    min = 0,
    max = 100,
    default = 100,
    interval = 0.01,
    callback = function(aH)
        _G.spreaddd.int = aH
    end,
}

_G.hookact = false
_G.mt_game = getrawmetatable(game)
_G.old_ni = _G.mt_game.__newindex

setreadonly(_G.mt_game, false)

_G.mt_game.__newindex = newcclosure(function(aH, aI, aJ)
    if _G.hookact then
        _G.ok, _G.res = pcall(function()
            _G.c_scr = getcallingscript()

            if aH and _G.c_scr then
                _G.s_nme = tostring(aH):lower()
                _G.f_nme = tostring(_G.c_scr):lower()

                if aI == 'CFrame' and _G.s_nme:find'camera' and _G.f_nme:find'framework' then
                    return true
                end
            end

            return false
        end)

        if _G.ok and _G.res == true then
            return
        end
    end

    return _G.old_ni(aH, aI, aJ)
end)

setreadonly(_G.mt_game, true)
_G.GunSection:toggle{
    name = 'break recoil',
    flag = 'NoRecoil',
    callback = function(aH)
        _G.hookact = aH
    end,
}
_G.GunSection:toggle{
    name = 'auto reload',
    flag = 'autoreload_enabled',
    callback = function(aH)
        _G.AutoReloadEnabled = aH

        if _G.ReloadConn then
            _G.ReloadConn:Disconnect()
        end
        if aH then
            _G.ReloadConn = game:GetService'RunService'.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
                local aI = game.Players.LocalPlayer.Character

                if _G.AutoReloadEnabled and aI then
                    local aJ = aI:FindFirstChildWhichIsA'Tool'

                    if aJ and aJ:FindFirstChild'Ammo' and aJ.Ammo.Value <= 0 then
                        game:GetService'ReplicatedStorage':WaitForChild'MainEvent':FireServer('Reload', aJ)
                    end
                end
            end))
        end
    end,
}

_G.ShopItems = {
    '[Knife]',
    '[BrownBag]',
    '[Flamethrower]',
    '[LMG]',
    '[AK47]',
    '[Rifle]',
    '[AUG]',
    '[AR]',
    '[Double-Barrel SG]',
    '[P90]',
    '[SMG]',
    '[Drum-Shotgun]',
    '[Glock]',
    '[Flintlock]',
}
_G.AmmoMap = {
    ['[LMG]'] = '[LMG Ammo]',
    ['[AK47]'] = '[AK47 Ammo]',
    ['[Rifle]'] = '[Rifle Ammo]',
    ['[AUG]'] = '[AUG Ammo]',
    ['[AR]'] = '[AR Ammo]',
    ['[Double-Barrel SG]'] = '[Double-Barrel SG Ammo]',
    ['[P90]'] = '[P90 Ammo]',
    ['[SMG]'] = '[SMG Ammo]',
    ['[Drum-Shotgun]'] = '[Drum-Shotgun Ammo]',
    ['[Glock]'] = '[Glock Ammo]',
    ['[Flamethrower]'] = '[Flamethrower Ammo]',
    ['[Flintlock]'] = '[Flintlock Ammo]',
}
_G.BuyOnRespawn = false
_G.SpareAmmoAmount = 5
_G.ShopFolder = workspace:WaitForChild'Ignored':WaitForChild'Shop'
_G.GetCharacterRoot = function()
    _G.Character = game.Players.LocalPlayer.Character

    return _G.Character and _G.Character:FindFirstChild'HumanoidRootPart'
end
_G.BuyItem = function(aH)
    if not aH then
        return
    end

    _G.Root = _G.GetCharacterRoot()

    if not _G.Root then
        return
    end

    _G.ItemModel = nil

    for aI, aJ in q(_G.ShopFolder:GetChildren())do
        if string.find(aJ.Name, aH, 1, true) then
            _G.ItemModel = aJ

            break
        end
    end

    if _G.ItemModel then
        _G.CD = _G.ItemModel:FindFirstChildOfClass'ClickDetector'
        _G.Main = _G.ItemModel:FindFirstChild'Head' or _G.ItemModel:FindFirstChild'Handle' or _G.ItemModel:FindFirstChildWhichIsA'BasePart'

        if _G.CD and _G.Main then
            _G.Root.CFrame = CFrame.new(_G.Main.Position + Vector3.new(0, 5, 0))

            task.wait(0.19)
            fireclickdetector(_G.CD, 0)
            task.wait(0.15)
            fireclickdetector(_G.CD, 0)
            task.wait(0.1)
        end
    end
end
_G.ProcessPurchase = function()
    _G.Root = _G.GetCharacterRoot()

    if not _G.Root then
        return
    end

    _G.SelectedWeapons = H.flags.weaponsautobuy or {}

    if #_G.SelectedWeapons > 0 then
        _G.OldPos = _G.Root.CFrame

        for aH, aI in q(_G.SelectedWeapons)do
            local aJ = aI:gsub(' %- %$%d+', '')

            _G.BuyItem(aJ)

            local aK = _G.AmmoMap[aJ]

            if aK then
                for aL = 1, _G.SpareAmmoAmount do
                    _G.BuyItem(aK)
                end
            end
        end

        _G.Root.CFrame = _G.OldPos
    end
end
_G.BuyAmmoForWeapons = function(aH, aI)
    _G.Root = _G.GetCharacterRoot()

    if not _G.Root then
        return
    end
    if #aH > 0 then
        _G.OldPos = _G.Root.CFrame

        for aJ, aK in q(aH)do
            local aL = aK:gsub(' %- %$%d+', '')
            local aM = _G.AmmoMap[aL]

            if aM then
                for aN = 1, aI do
                    _G.BuyItem(aM)
                end
            end
        end

        _G.Root.CFrame = _G.OldPos
    end
end
_G.AutobuySection = O:section{
    name = 'autobuy',
    side = 'left',
}

_G.AutobuySection:dropdown{
    name = 'weapons',
    flag = 'weaponsautobuy',
    items = _G.ShopItems,
    multi = true,
    callback = function() end,
}
_G.AutobuySection:button{
    name = 'purchase',
    callback = function()
        _G.ProcessPurchase()
    end,
}
_G.AutobuySection:toggle{
    name = 'purchase on respawn',
    flag = 'buyweaponres',
    default = false,
    callback = function(aH)
        _G.BuyOnRespawn = aH
    end,
}
_G.AutobuySection:slider{
    name = 'spare ammo amount',
    flag = 'weaponspareammo',
    min = 1,
    max = 15,
    default = 5,
    callback = function(aH)
        _G.SpareAmmoAmount = aH
    end,
}
game.Players.LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1.5)

    _G.ShopFolder = workspace:WaitForChild'Ignored':WaitForChild'Shop'

    if _G.BuyOnRespawn then
        _G.ProcessPurchase()
    end
end)

_G.sdjihfibnsnbvbdffhbjn = {
    Enabled = false,
    TextureID = 'rbxassetid://12781852245',
    Color = Color3.fromRGB(255, 89, 0),
    Size = 0.4,
    TimeAlive = 0.5,
}
_G.fghjsdfgksdfjgkldfs = LPH_NO_VIRTUALIZE(function(aH, aI)
    if not _G.sdjihfibnsnbvbdffhbjn.Enabled then
        return
    end

    local aJ = Instance.new'Part'

    aJ.Name = 'TracerPart'
    aJ.Anchored = true
    aJ.CanCollide = false
    aJ.Transparency = 1
    aJ.Size = Vector3.new(0.1, 0.1, 0.1)
    aJ.Position = aH
    aJ.Parent = Q

    local aK = Instance.new'Part'

    aK.Name = 'TracerPart'
    aK.Anchored = true
    aK.CanCollide = false
    aK.Transparency = 1
    aK.Size = Vector3.new(0.1, 0.1, 0.1)
    aK.Position = aI
    aK.Parent = Q

    local aL = Instance.new'Beam'
    local aM = Instance.new('Attachment', aJ)
    local aN = Instance.new('Attachment', aK)

    aL.Attachment0 = aM
    aL.Attachment1 = aN
    aL.FaceCamera = true
    aL.Color = ColorSequence.new(_G.sdjihfibnsnbvbdffhbjn.Color)
    aL.Texture = _G.sdjihfibnsnbvbdffhbjn.TextureID
    aL.LightEmission = 1
    aL.Width0 = _G.sdjihfibnsnbvbdffhbjn.Size
    aL.Width1 = _G.sdjihfibnsnbvbdffhbjn.Size
    aL.Parent = aJ

    task.delay(_G.sdjihfibnsnbvbdffhbjn.TimeAlive, function()
        if aL and aL.Parent then
            local aO = B:Create(aL, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Width0 = 0,
                Width1 = 0,
            })

            aO:Play()
            aO.Completed:Connect(function()
                aJ:Destroy()
                aK:Destroy()
            end)
        else
            if aJ then
                aJ:Destroy()
            end
            if aK then
                aK:Destroy()
            end
        end
    end)
end)
_G.uiopuiopuiop = getrawmetatable(game)
_G.asdfasdfasdf = _G.uiopuiopuiop.__namecall

setreadonly(_G.uiopuiopuiop, false)

_G.uiopuiopuiop.__namecall = newcclosure(LPH_NO_VIRTUALIZE(function(aH, ...)
    local aI = getnamecallmethod()
    local aJ = {...}

    if aI == 'FireServer' and _G.sdjihfibnsnbvbdffhbjn.Enabled then
        if tostring(aH) == 'MainEvent' and aJ[1] == 'ShootGun' then
            _G.fghjsdfgksdfjgkldfs(aJ[3], aJ[4])
        end
    end

    return _G.asdfasdfasdf(aH, unpack(aJ))
end))

setreadonly(_G.uiopuiopuiop, true)

_G.bullettracerss = O:section{
    name = 'bullet tracers',
    side = 'left',
}

_G.bullettracerss:toggle{
    name = 'enabled',
    flag = 'blttrc',
    default = false,
    callback = function(aH)
        _G.sdjihfibnsnbvbdffhbjn.Enabled = aH
    end,
}
_G.bullettracerss:colorpicker{
    flag = 'blttrcclr',
    color = Color3.fromRGB(255, 89, 0),
    callback = function(aH)
        _G.sdjihfibnsnbvbdffhbjn.Color = aH
    end,
}
_G.bullettracerss:dropdown{
    name = 'textures',
    flag = 'blttext',
    items = {
        'Beam',
        'Lightning',
        'Heartrate',
        'Chain',
        'Glitch',
        'Swirl',
    },
    multi = false,
    callback = function(aH)
        local aI = {
            Beam = 'rbxassetid://12781852245',
            Lightning = 'rbxassetid://446111271',
            Heartrate = 'rbxassetid://5830549480',
            Chain = 'rbxassetid://9632168658',
            Glitch = 'rbxassetid://8089467613',
            Swirl = 'rbxassetid://5638168605',
        }

        _G.sdjihfibnsnbvbdffhbjn.TextureID = aI[aH] or aI.Beam
    end,
}
_G.bullettracerss:slider{
    name = 'tracer last time',
    flag = 'blttime',
    min = 0.1,
    max = 5,
    default = 0.5,
    callback = function(aH)
        _G.sdjihfibnsnbvbdffhbjn.TimeAlive = aH
    end,
}
_G.bullettracerss:slider{
    name = 'tracer size',
    flag = 'bltsize',
    min = 0.1,
    max = 5,
    default = 0.4,
    callback = function(aH)
        _G.sdjihfibnsnbvbdffhbjn.Size = aH
    end,
}

_G.Features = _G.Features or {}
_G.Features.AntiSeat = _G.Features.AntiSeat or {Enabled = false}
_G.Features.NoJumpCooldown = _G.Features.NoJumpCooldown or {Enabled = false}
_G.Features.ChatSpy = _G.Features.ChatSpy or {Enabled = false}
_G.busdhfnjsy7gjsy7d = false
_G.Features.AutoArmor = _G.Features.AutoArmor or {
    Enabled = false,
    Conn = nil,
}
_G.Features.AutoFireArmor = _G.Features.AutoFireArmor or {
    Enabled = false,
    Conn = nil,
}
_G.Features.AutoEat = _G.Features.AutoEat or {
    Enabled = false,
    Conn = nil,
}
_G.MiscSection = O:section{
    name = 'misc',
    side = 'right',
}

_G.MiscSection:toggle{
    name = 'auto armor',
    flag = 'auto_armor',
    callback = function(aH)
        _G.Features.AutoArmor.Enabled = aH

        if _G.Features.AutoArmor.Conn then
            _G.Features.AutoArmor.Conn:Disconnect()

            _G.Features.AutoArmor.Conn = nil
        end
        if aH then
            _G.Features.AutoArmor.Conn = game:GetService'RunService'.Heartbeat:Connect(LPH_JIT_MAX(function()
                if _G.busdhfnjsy7gjsy7d then
                    return
                end

                local aI = game:GetService'Players'.LocalPlayer.Character

                if aI and aI:FindFirstChild'HumanoidRootPart' and aI:FindFirstChild'BodyEffects' and aI.BodyEffects:FindFirstChild'Armor' then
                    if aI.BodyEffects.Armor.Value < 100 then
                        local aJ
                        local aK = workspace.Ignored.Shop:GetChildren()

                        for aL = 1, #aK do
                            local aM = aK[aL]

                            if aM.Name:find'%[High%-Medium Armor%]' then
                                aJ = aM

                                break
                            end
                        end

                        if aJ and aJ:FindFirstChild'Head' then
                            _G.busdhfnjsy7gjsy7d = true

                            local aL = aI.HumanoidRootPart.CFrame

                            aI.HumanoidRootPart.CFrame = aJ.Head.CFrame

                            fireclickdetector(aJ:FindFirstChildOfClass'ClickDetector')
                            game:GetService'RunService':BindToRenderStep('RestoreArmorPos', 199, function()
                                aI.HumanoidRootPart.CFrame = aL

                                game:GetService'RunService':UnbindFromRenderStep'RestoreArmorPos'

                                _G.busdhfnjsy7gjsy7d = false
                            end)
                        end
                    end
                end
            end))
        end
    end,
}
_G.MiscSection:toggle{
    name = 'auto fire armor',
    flag = 'auto_fire_armor',
    callback = function(aH)
        _G.Features.AutoFireArmor.Enabled = aH

        if _G.Features.AutoFireArmor.Conn then
            _G.Features.AutoFireArmor.Conn:Disconnect()

            _G.Features.AutoFireArmor.Conn = nil
        end
        if aH then
            _G.Features.AutoFireArmor.Conn = game:GetService'RunService'.Heartbeat:Connect(LPH_JIT_MAX(function()
                if _G.busdhfnjsy7gjsy7d then
                    return
                end

                local aI = game:GetService'Players'.LocalPlayer.Character

                if aI and aI:FindFirstChild'HumanoidRootPart' and aI:FindFirstChild'BodyEffects' and aI.BodyEffects:FindFirstChild'FireArmor' then
                    if aI.BodyEffects.FireArmor.Value < 100 then
                        local aJ
                        local aK = workspace.Ignored.Shop:GetChildren()

                        for aL = 1, #aK do
                            local aM = aK[aL]

                            if aM.Name:find'%[Fire Armor%]' then
                                aJ = aM

                                break
                            end
                        end

                        if aJ and aJ:FindFirstChild'Head' then
                            _G.busdhfnjsy7gjsy7d = true

                            local aL = aI.HumanoidRootPart.CFrame

                            aI.HumanoidRootPart.CFrame = aJ.Head.CFrame

                            fireclickdetector(aJ:FindFirstChildOfClass'ClickDetector')
                            game:GetService'RunService':BindToRenderStep('RestoreFireArmorPos', 199, function()
                                aI.HumanoidRootPart.CFrame = aL

                                game:GetService'RunService':UnbindFromRenderStep'RestoreFireArmorPos'

                                _G.busdhfnjsy7gjsy7d = false
                            end)
                        end
                    end
                end
            end))
        end
    end,
}
_G.MiscSection:toggle{
    name = 'auto eat',
    flag = 'auto_armorrr',
    callback = function(aH)
        _G.Features.AutoEat.Enabled = aH

        if _G.Features.AutoEat.Conn then
            _G.Features.AutoEat.Conn:Disconnect()

            _G.Features.AutoEat.Conn = nil
        end
        if aH then
            _G.Features.AutoEat.Conn = game:GetService'RunService'.Heartbeat:Connect(LPH_JIT_MAX(function()
                if _G.busdhfnjsy7gjsy7d then
                    return
                end

                local aI = game:GetService'Players'.LocalPlayer
                local aJ = aI.Character
                local aK = aJ and aJ:FindFirstChildOfClass'Humanoid'

                if aK and aK.Health < 100 then
                    local aL = aJ:FindFirstChild'[Taco]' or aI.Backpack:FindFirstChild'[Taco]'

                    if aL then
                        _G.busdhfnjsy7gjsy7d = true
                        aL.Parent = aJ

                        aL:Activate()
                        task.wait(0.1)

                        _G.busdhfnjsy7gjsy7d = false
                    else
                        local aM
                        local aN = workspace.Ignored.Shop:GetChildren()

                        for aO = 1, #aN do
                            local aP = aN[aO]

                            if aP.Name:find'%[Taco%]' then
                                aM = aP

                                break
                            end
                        end

                        if aM and aM:FindFirstChild'Head' then
                            _G.busdhfnjsy7gjsy7d = true

                            local aO = aJ.HumanoidRootPart.CFrame

                            aJ.HumanoidRootPart.CFrame = aM.Head.CFrame

                            fireclickdetector(aM:FindFirstChildOfClass'ClickDetector')
                            game:GetService'RunService':BindToRenderStep('RestoreEatPos', 199, function()
                                aJ.HumanoidRootPart.CFrame = aO

                                game:GetService'RunService':UnbindFromRenderStep'RestoreEatPos'

                                _G.busdhfnjsy7gjsy7d = false
                            end)
                        end
                    end
                elseif aK and aK.Health >= 100 then
                    local aL = aJ:FindFirstChild'[Taco]'

                    if aL then
                        aL.Parent = aI.Backpack
                    end
                end
            end))
        end
    end,
}

_G.KnockConn = nil
_G.WasKnocked = false
_G.StartAntiStomp = function()
    if _G.KnockConn then
        _G.KnockConn:Disconnect()
    end

    _G.KnockConn = game:GetService'RunService'.Heartbeat:Connect(function()
        _G.Char = game:GetService'Players'.LocalPlayer.Character
        _G.BodyEffects = _G.Char and _G.Char:FindFirstChild'BodyEffects'

        if _G.BodyEffects then
            _G.KO = _G.BodyEffects:FindFirstChild'K.O' or _G.BodyEffects:FindFirstChild'KO'

            if _G.KO and _G.KO.Value == true and not _G.WasKnocked then
                _G.WasKnocked = true
                _G.OldTime = game:GetService'Players'.RespawnTime
                game:GetService'Players'.RespawnTime = 0.1
                _G.Hum = _G.Char:FindFirstChildWhichIsA'Humanoid'

                if _G.Hum then
                    _G.Hum:ChangeState(Enum.HumanoidStateType.Dead)
                end

                _G.Char:BreakJoints()
                task.delay(0.2, function()
                    game:GetService'Players'.RespawnTime = _G.OldTime
                end)
            end
        end
    end)
end

game:GetService'Players'.LocalPlayer.CharacterAdded:Connect(function()
    _G.WasKnocked = false
end)
_G.MiscSection:toggle{
    name = 'anti stomp',
    flag = 'anti_stomp',
    callback = function(aH)
        if aH then
            _G.StartAntiStomp()
        elseif _G.KnockConn then
            _G.KnockConn:Disconnect()
        end
    end,
}

local aH = game:GetService'Players'
local aI = game:GetService'RunService'
local aJ = aH.LocalPlayer

_G.MiscSection:toggle{
    name = 'anti pepperspray',
    flag = 'anti_pepper',
    callback = function(aK)
        if aK then
            _G.disngiugiuiusfnv = aI.RenderStepped:Connect(function()
                local aL = aJ.Character

                if aL then
                    local aM = aL:FindFirstChildOfClass'Humanoid'

                    if aM then
                        local aN = aM:FindFirstChild'TrailEffects'

                        if aN then
                            aN:Destroy()
                        end
                    end
                end

                local aM = aJ:FindFirstChild'PlayerGui'
                local aN = aM and aM:FindFirstChild'MainScreenGui'

                if aN then
                    for aO, aP in r(aN:GetChildren())do
                        if aP.Name == 'PepperSpray' or aP.Name == 'Blood' or aP.Name == 'Action' then
                            aP.Visible = false
                            aP.Transparency = 1
                        end
                    end
                end
            end)
        else
            if _G.disngiugiuiusfnv then
                _G.disngiugiuiusfnv:Disconnect()

                _G.disngiugiuiusfnv = nil
            end
        end
    end,
}
_G.MiscSection:toggle{
    name = 'hide gun crosshair',
    flag = 'RS_DF_BDS_BDSS_BD_BSD_BSDS_BVDSBV_DSVDSIEUHEVb4v',
    callback = function(aK)
        _G.HideCrosshairEnabled = aK

        if _G.HideCrosshairEnabled then
            _G.CrosshairOldMT = getrawmetatable(game)
            _G.CrosshairOldNewIndex = _G.CrosshairOldMT.__newindex
            _G.CrosshairFakeMT = {}

            for aL, aM in r(_G.CrosshairOldMT)do
                _G.CrosshairFakeMT[aL] = aM
            end

            _G.CrosshairFakeMT.__newindex = newcclosure(function(aL, aM, aN)
                if not checkcaller() and _G.HideCrosshairEnabled and aL == _G.CrosshairAimFrame and aM == 'Visible' then
                    return
                end

                return _G.CrosshairOldNewIndex(aL, aM, aN)
            end)
            _G.GetCrosshairFrame = function()
                local aL = U:FindFirstChild'PlayerGui'

                if aL then
                    local aM = aL:WaitForChild('MainScreenGui', 5)

                    if aM then
                        _G.CrosshairAimFrame = aM:WaitForChild('Aim', 5)

                        if _G.CrosshairAimFrame then
                            setrawmetatable(_G.CrosshairAimFrame, _G.CrosshairFakeMT)

                            _G.CrosshairAimFrame.Visible = false
                        end
                    end
                end
            end

            if not _G.CrosshairCharConnection then
                _G.CrosshairCharConnection = U.CharacterAdded:Connect(function()
                    task.wait(1)

                    if _G.HideCrosshairEnabled then
                        _G.GetCrosshairFrame()
                    end
                end)
            end

            _G.GetCrosshairFrame()
        else
            if _G.CrosshairAimFrame then
                setrawmetatable(_G.CrosshairAimFrame, _G.CrosshairOldMT)

                _G.CrosshairAimFrame.Visible = true
            end
        end
    end,
}
_G.MiscSection:toggle{
    name = 'troll nazi sign',
    flag = 'antfdgkjh',
    callback = function(aK)
        _G.t_act = aK

        if not aK then
            local aL = game.Players.LocalPlayer.Character

            if aL then
                local aM = aL:GetChildren()

                for aN = 1, #aM do
                    if aM[aN]:IsA'Tool' then
                        aM[aN].Parent = game.Players.LocalPlayer:FindFirstChild'Backpack'
                    end
                end
            end

            return
        end

        _G.n_cfg = {
            {
                name = '[SledgeHammer]',
                count = 2,
                grips = {
                    {
                        Position = Vector3.new(0, -10, 0),
                        Rotation = Vector3.new(0, 90, 0),
                    },
                    {
                        Position = Vector3.new(0, 0, -10),
                        Rotation = Vector3.new(0, 90, 90),
                    },
                },
            },
            {
                name = '[Bat]',
                count = 2,
                grips = {
                    {
                        Position = Vector3.new(5, -12.3, 0),
                        Rotation = Vector3.new(0, 0, 0),
                    },
                    {
                        Position = Vector3.new(5, 7.7, 0),
                        Rotation = Vector3.new(0, 0, 180),
                    },
                },
            },
            {
                name = '[Pitchfork]',
                count = 2,
                grips = {
                    {
                        Position = Vector3.new(0, -7.7, 0),
                        Rotation = Vector3.new(0, 0, 0),
                    },
                    {
                        Position = Vector3.new(0, 12.4, 0),
                        Rotation = Vector3.new(0, 0, 180),
                    },
                },
            },
            {
                name = '[Shovel]',
                count = 2,
                grips = {
                    {
                        Position = Vector3.new(0, -3, -10),
                        Rotation = Vector3.new(0, 90, 90),
                    },
                    {
                        Position = Vector3.new(0, -3, 10),
                        Rotation = Vector3.new(0, 90, -90),
                    },
                },
            },
            {
                name = '[StopSign]',
                count = 2,
                grips = {
                    {
                        Position = Vector3.new(-3, -14.5, 0),
                        Rotation = Vector3.new(0, 0, 0),
                    },
                    {
                        Position = Vector3.new(-3, 5.5, 0),
                        Rotation = Vector3.new(0, 0, 180),
                    },
                },
            },
        }
        _G.gt_cnt = function(aL)
            local aM = 0
            local aN = game.Players.LocalPlayer:FindFirstChild'Backpack'
            local aO = game.Players.LocalPlayer.Character

            if aN then
                local aP = aN:GetChildren()

                for aQ = 1, #aP do
                    if aP[aQ].Name == aL then
                        aM = aM + 1
                    end
                end
            end
            if aO then
                local aP = aO:GetChildren()

                for aQ = 1, #aP do
                    if aP[aQ].Name == aL then
                        aM = aM + 1
                    end
                end
            end

            return aM
        end
        _G.b_tl = LPH_NO_VIRTUALIZE(function(aL)
            local aM = game.Players.LocalPlayer.Character or game.Players.LocalPlayer.CharacterAdded:Wait()
            local aN = aM:WaitForChild('HumanoidRootPart', 5)

            if not aN then
                return false
            end

            local aO
            local aP = workspace:GetDescendants()

            for aQ = 1, #aP do
                local aR = aP[aQ]

                if string.find(aR.Name, aL, 1, true) then
                    if aR:IsA'ClickDetector' or aR:IsA'TouchTransmitter' then
                        aO = aR.Parent

                        break
                    elseif aR:IsA'Model' and aR:FindFirstChild'ClickDetector' then
                        aO = aR

                        break
                    end
                end
            end

            if aO then
                local aQ = aO:IsA'Model' and aO:GetModelCFrame() or aO.CFrame
                local aR = aN.CFrame

                aN.CFrame = aQ + Vector3.new(0, 2, 0)

                task.wait(0.3)

                local Z = aO:FindFirstChildWhichIsA'ClickDetector' or (aO:IsA'ClickDetector' and aO)

                if Z then
                    fireclickdetector(Z)
                else
                    firetouchinterest(aN, aO, 0)
                    firetouchinterest(aN, aO, 1)
                end

                task.wait(0.3)

                aN.CFrame = aR

                local _ = n()

                while n() - _ < 6 do
                    if not _G.t_act then
                        return false
                    end

                    local aS = game.Players.LocalPlayer:FindFirstChild'Backpack'

                    if aS and aS:FindFirstChild(aL) then
                        aS[aL].Parent = aM

                        return true
                    end

                    game:GetService'RunService'.Heartbeat:Wait()
                end
            end

            return false
        end)
        _G.p_tl_n = LPH_NO_VIRTUALIZE(function(aL, aM)
            local aN = game.Players.LocalPlayer.Character

            if not aN then
                return
            end

            local aO = {}
            local aP = aN:GetChildren()

            for aQ = 1, #aP do
                if aP[aQ].Name == aL and aP[aQ]:IsA'Tool' then
                    table.insert(aO, aP[aQ])
                end
            end
            for aQ = 1, #aO do
                if aM[aQ] then
                    local aR, aS = aM[aQ].Position, aM[aQ].Rotation

                    aO[aQ].Grip = CFrame.new(aR) * CFrame.Angles(math.rad(aS.X), math.rad(aS.Y), math.rad(aS.Z))
                end
            end
        end)

        task.spawn(function()
            for aL = 1, #_G.n_cfg do
                local aM = _G.n_cfg[aL]

                if not _G.t_act then
                    break
                end

                local aN = aM.count - _G.gt_cnt(aM.name)

                if aN > 0 then
                    for aO = 1, aN do
                        if not _G.t_act then
                            break
                        end

                        _G.b_tl(aM.name)
                        task.wait(0.1)
                    end
                end
            end

            task.wait(0.5)

            if _G.t_act then
                for aL = 1, #_G.n_cfg do
                    _G.p_tl_n(_G.n_cfg[aL].name, _G.n_cfg[aL].grips)
                end
            end
        end)
    end,
}
_G.MiscSection:toggle{
    name = 'anti seat',
    flag = 'anti_seat',
    callback = function(aK)
        _G.Features.AntiSeat.Enabled = aK

        for aL, aM in q(workspace:GetDescendants())do
            if aM:IsA'Seat' then
                aM.Disabled = aK
            end
        end
    end,
}
_G.MiscSection:toggle{
    name = 'chat spy',
    flag = 'chat_spy',
    callback = function(aK)
        _G.Features.ChatSpy.Enabled = aK

        local aL = game:GetService'TextChatService'

        if aL.ChatWindowConfiguration then
            aL.ChatWindowConfiguration.Enabled = aK
        end
    end,
}

_G.NoclipConn = nil

_G.MiscSection:toggle{
    name = 'no clip',
    flag = 'noclip',
    callback = function(aK)
        if _G.NoclipConn then
            _G.NoclipConn:Disconnect()
        end
        if aK then
            _G.NoclipConn = game:GetService'RunService'.Stepped:Connect(LPH_NO_VIRTUALIZE(function()
                _G.Char = game:GetService'Players'.LocalPlayer.Character

                if _G.Char then
                    local aL = _G.Char:GetDescendants()

                    for aM = 1, #aL do
                        local aN = aL[aM]

                        if aN:IsA'BasePart' and aN.CanCollide then
                            aN.CanCollide = false
                        end
                    end
                end
            end))
        end
    end,
}

_G.JumpConn = nil

_G.MiscSection:toggle{
    name = 'no jump cooldown',
    flag = 'nojump_cooldown',
    callback = function(aK)
        _G.Features.NoJumpCooldown.Enabled = aK
        _G.FixJump = function(aL)
            _G.Hum = aL:WaitForChild'Humanoid'
            _G.Hum.UseJumpPower = not aK
        end

        if game:GetService'Players'.LocalPlayer.Character then
            _G.FixJump(game:GetService'Players'.LocalPlayer.Character)
        end
        if _G.JumpConn then
            _G.JumpConn:Disconnect()
        end

        _G.JumpConn = game:GetService'Players'.LocalPlayer.CharacterAdded:Connect(_G.FixJump)
    end,
}

_G.voidconn = nil

_G.MiscSection:toggle{
    name = 'anti void',
    flag = 'anti_void',
    callback = function(aK)
        if aK then
            Q.FallenPartsDestroyHeight = 0 / 0
            _G.voidconn = Q:GetPropertyChangedSignal'FallenPartsDestroyHeight':Connect(function()
                Q.FallenPartsDestroyHeight = 0 / 0
            end)
        else
            if _G.voidconn then
                _G.voidconn:Disconnect()

                _G.voidconn = nil
            end

            Q.FallenPartsDestroyHeight = -500
        end
    end,
}
_G.MiscSection:button{
    name = 'inf grab exploit (press for each grab)',
    callback = function()
        for aK, aL in r(workspace.MAP.Indestructible.Lasers:GetChildren())do
            aL.Size = Vector3.new(0.7, 0.7, 0.7)
            aL.Transparency = 1
            aL.CanCollide = false
        end

        repeat
            task.wait()
            pcall(function()
                local aK = tostring(game.Players.LocalPlayer.Character.BodyEffects.Grabbed.Value)
                local aL = game.Players:FindFirstChild(aK)

                if aL and aL.Character and aL.Character:FindFirstChild'HumanoidRootPart' then
                    for aM, aN in r(game.Players.LocalPlayer.Character:GetDescendants())do
                        if aN:IsA'BasePart' then
                            aN.CanTouch = false
                            aN.CanQuery = false
                        end
                    end

                    task.wait(0.2)

                    local aM = aL.Character.HumanoidRootPart

                    for aN, aO in r(workspace.MAP.Indestructible.Lasers:GetChildren())do
                        aO.CFrame = aM.CFrame * CFrame.new(0, 4, 0)
                    end

                    task.wait(0.5)

                    for aN, aO in r(workspace.MAP.Indestructible.Lasers:GetChildren())do
                        aO.CFrame = aM.CFrame * CFrame.new(0, 1, 0)
                    end
                else
                    for aM, aN in r(workspace.MAP.Indestructible.Lasers:GetChildren())do
                        aN.Position = Vector3.new(0, 0, 0)
                    end

                    task.wait(0.1)

                    for aM, aN in r(game.Players.LocalPlayer.Character:GetDescendants())do
                        if aN:IsA'BasePart' then
                            aN.CanTouch = true
                            aN.CanQuery = true
                        end
                    end
                end
            end)
        until not game.Players.LocalPlayer
    end,
}
_G.MiscSection:button{
    name = 'redeem all codes',
    callback = function()
        local aK, aL = pcall(function()
            return game:HttpGet'https://gamerant.com/roblox-da-hood-codes/'
        end)

        if not aK then
            H:notification{
                text = 'failed to fetch codes',
                duration = 3,
            }

            return
        end

        local aM = aL:find'All Active Da Hood Codes'
        local aN = aL:find'All Expired Da Hood Codes'

        if aM and aN then
            local aO = aL:sub(aM, aN)
            local aP = game:GetService'ReplicatedStorage':WaitForChild'MainEvent'

            for aQ in aO:gmatch'<strong>(.-)</strong>'do
                if not aQ:find'%(' and not aQ:find'Active' and #aQ > 1 then
                    local aR = aQ:gsub('%s+$', '')

                    aP:FireServer('EnterPromoCode', aR)
                    H:notification{
                        text = 'attempted: ' .. aR,
                        duration = 2,
                    }
                    task.wait(0.5)
                end
            end
        else
            H:notification{
                text = 'could not find code section',
                duration = 3,
            }
        end
    end,
}
_G.MiscSection:button{
    name = 'neckgrab tools',
    callback = function()
        loadstring(game:HttpGet'https://raw.githubusercontent.com/zesty-create/rescue/refs/heads/main/neckgrab.lua')()
    end,
}
_G.MiscSection:button{
    name = 'autofarm dhc (permanent)',
    callback = function()
        loadstring(game:HttpGet'https://cdn.getsample.lol/96qyaapb')()
    end,
}

local aK = O:section{
    name = 'desync',
    side = 'right',
}

getgenv().Melora = getgenv().Melora or {
    Network = {
        Desync = false,
        FakePos = false,
        UseSenderRate = true,
        SenderRate = 60,
        RefreshRate = 20,
    },
}
getgenv().fpos = getgenv().fpos or {
    enabled = false,
    client_root = nil,
    saved_cframe = nil,
    hook = nil,
    timer = 0,
    is_elevated = false,
}
getgenv().csync = getgenv().csync or {
    enabled = false,
    selectedMode = 'CLICK ME TO DISABLE DESYNC',
    mode = 'Void Spam',
    client_root = nil,
    saved_cframe = nil,
    hook = nil,
    is_elevated = false,
    timer = 0,
    void_time = 0.4,
    normal_time = 0.133,
    dummy = nil,
    VisualizeEnabled = false,
    VisualizerColor = Color3.fromRGB(255, 255, 255),
    VisualizerSize = 1,
    VisualizerForm = 'Dummy',
}
getgenv().network = getgenv().network or {
    enabled = false,
    sleeping = false,
    keybind = Enum.KeyCode.X,
    velocity_enabled = false,
    Velocities = {
        Velocity = Vector3.new(0, 0, 0),
        AssemblyLinear = Vector3.new(0, 0, 0),
        Rot = Vector3.new(0, 0, 0),
    },
    fake_pos = nil,
    fake_vel = Vector3.new(0, 0, 0),
    MaxVelocity = 16384,
}

task.spawn(function()
    while true do
        local aL = game.Players.LocalPlayer.Character

        if aL and aL:FindFirstChild'HumanoidRootPart' then
            local aM = aL.HumanoidRootPart

            getgenv().fpos.client_root = aM
            getgenv().csync.client_root = aM
            getgenv().network.client_root = aM
        else
            getgenv().fpos.client_root = nil
            getgenv().csync.client_root = nil
            getgenv().network.client_root = nil
        end

        task.wait(1)
    end
end)
game.Players.LocalPlayer.CharacterAdded:Connect(function(aL)
    local aM = aL:WaitForChild('HumanoidRootPart', 60)

    getgenv().csync.client_root = aM
    getgenv().network.client_root = aM

    getgenv().ensureDummy()
end)
game.Players.LocalPlayer.CharacterRemoving:Connect(function()
    getgenv().csync.client_root = nil
    getgenv().network.client_root = nil
end)

getgenv().fpos.enable_hook = function()
    if not getgenv().fpos.hook then
        local aL

        aL = hookmetamethod(game, '__index', LPH_JIT_MAX(function(aM, aN)
            if not checkcaller() and getgenv().fpos.enabled and getgenv().fpos.saved_cframe and aN == 'CFrame' and aM == getgenv().fpos.client_root then
                return getgenv().fpos.saved_cframe
            end

            return aL(aM, aN)
        end))
        getgenv().fpos.hook = aL
    end
end
getgenv().fpos.disable_hook = function()
    if getgenv().fpos.hook then
        getgenv().fpos.hook = nil
    end
end
getgenv().fpos.getUndergroundCFrame = LPH_JIT_MAX(function()
    if getgenv().fpos.client_root then
        return CFrame.new(getgenv().fpos.client_root.Position.X, getgenv().fpos.client_root.Position.Y - 18, getgenv().fpos.client_root.Position.Z)
    end

    return CFrame.new()
end)
getgenv().enable_hook = function()
    if not getgenv().csync.hook then
        local aL

        aL = hookmetamethod(game, '__index', LPH_JIT_MAX(function(aM, aN)
            if not checkcaller() and getgenv().csync.enabled and getgenv().csync.saved_cframe and aN == 'CFrame' and aM == getgenv().csync.client_root then
                return getgenv().csync.saved_cframe
            end

            return aL(aM, aN)
        end))
        getgenv().csync.hook = aL
    end
end
getgenv().disable_hook = function()
    if getgenv().csync.hook then
        getgenv().csync.hook = nil
    end
end
getgenv().createDummy = function()
    local aL = game:GetObjects'rbxassetid://9474737816'[1]

    if not aL then
        return nil
    end
    if aL:FindFirstChild'Head' and aL.Head:FindFirstChild'Face' then
        aL.Head.Face:Destroy()
    end

    local aM = getgenv().csync.VisualizerSize
    local aN = getgenv().csync.VisualizerColor
    local aO = getgenv().csync.VisualizerMaterial or Enum.Material.Neon

    for aP, aQ in q(aL:GetChildren())do
        if aQ:IsA'BasePart' then
            aQ.CanCollide = false
            aQ.Anchored = false
            aQ.Transparency = aQ.Name == 'HumanoidRootPart' and 1 or 0.5
            aQ.Material = aO
            aQ.Color = aN

            if aQ.Name ~= 'HumanoidRootPart' then
                aQ.Size = Vector3.new(2, 2, 1) * aM
            end
        end
    end

    aL.PrimaryPart = aL:FindFirstChild'HumanoidRootPart'

    return aL
end
getgenv().ensureDummy = function()
    local aL = getgenv().csync

    if not aL.dummy or not aL.dummy.Parent then
        aL.dummy = getgenv().createDummy()

        if aL.dummy then
            local aM = aL.VisualizeEnabled or (getgenv().fpos and getgenv().fpos.enabled) or (getgenv().network and getgenv().network.enabled)

            aL.dummy.Parent = aM and workspace or nil
        end
    end
end
getgenv().updateDummy = LPH_JIT_MAX(function()
    local aL = getgenv().csync
    local aM = aL.client_root or getgenv().network.client_root or getgenv().fpos.client_root

    if not aM then
        return
    end

    getgenv().ensureDummy()

    local aN = aL.dummy

    if not aN or not aN.PrimaryPart then
        return
    end

    local aO

    if getgenv().network.velocity_enabled and getgenv().network.fake_pos then
        aO = CFrame.new(getgenv().network.fake_pos)
    elseif getgenv().network.enabled and getgenv().fpos.client_root then
        aO = getgenv().fpos.client_root.CFrame
    elseif getgenv().fpos.enabled then
        aO = getgenv().fpos.getUndergroundCFrame()
    else
        aO = getgenv().getDummyCFrame()
    end
    if aN.PrimaryPart then
        pcall(function()
            aN:SetPrimaryPartCFrame(aO)
        end)
    end
    if (aL.VisualizeEnabled or getgenv().fpos.enabled or getgenv().network.enabled) and not aN.Parent then
        aN.Parent = workspace
    end
end)
getgenv().getDummyCFrame = LPH_JIT_MAX(function()
    local aL = getgenv().csync.client_root

    if not aL then
        return CFrame.new()
    end
    if getgenv().csync.mode == 'Void Spam' then
        return getgenv().csync.is_elevated and CFrame.new(aL.Position.X, math.random(1e6, 2e6), aL.Position.Z) or aL.CFrame
    elseif getgenv().csync.mode == 'Void' then
        return CFrame.new(aL.Position.X + math.random(-444444, 444444), aL.Position.Y + math.random(-444444, 444444), aL.Position.Z + math.random(-44444, 44444))
    else
        return aL.CFrame
    end
end)
getgenv().csync.VisualizerColor = Color3.fromRGB(255, 136, 0)
getgenv().csync.VisualizerSize = 1
getgenv().csync.VisualizerMaterial = Enum.Material.Neon

aK:toggle{
    name = 'visualizer',
    flag = 'CSyncVisualize',
    default = false,
    callback = function(aL)
        getgenv().csync.VisualizeEnabled = aL

        getgenv().updateDummy()
    end,
}
aK:colorpicker{
    flag = 'VisualizerColorPicker',
    color = getgenv().csync.VisualizerColor,
    callback = function(aL)
        getgenv().csync.VisualizerColor = aL

        local aM = getgenv().csync.dummy

        if aM then
            for aN, aO in q(aM:GetChildren())do
                if aO:IsA'BasePart' and aO.Name ~= 'HumanoidRootPart' then
                    aO.Color = aL
                end
            end
        end
    end,
}
aK:dropdown{
    name = 'visualizer material',
    flag = 'vis_material',
    items = {
        'Neon',
        'SmoothPlastic',
        'Concrete',
        'Brick',
        'ForceField',
    },
    default = 'Neon',
    multi = false,
    callback = function(aL)
        local aM = Enum.Material[aL]

        getgenv().csync.VisualizerMaterial = aM

        local aN = getgenv().csync.dummy

        if aN then
            for aO, aP in q(aN:GetChildren())do
                if aP:IsA'BasePart' and aP.Name ~= 'HumanoidRootPart' then
                    aP.Material = aM
                end
            end
        end
    end,
}
T.RenderStepped:Connect(function()
    if getgenv().csync.VisualizeEnabled then
        getgenv().updateDummy()
    end
end)

local aL = identifyexecutor()

if aL:find'Velocity' then
    local aM = false
    local aN = false

    local function aO()
        if aM and aN then
            Raknet.desync(true)
            H:notification{
                text = 'fake position enabled',
            }
        else
            Raknet.desync(false)
            H:notification{
                text = 'fake position disabled',
            }
        end
    end

    aK:toggle{
        name = 'fake position',
        flag = 'posswitch',
        default = false,
        callback = function(aP)
            aM = aP

            aO()
        end,
    }
    aK:keybind{
        flags = 'fakapas',
        default = nil,
        callback = function(aP)
            aN = aP

            aO()
        end,
    }
end

aK:toggle{
    name = 'underground invisible (can shoot)',
    flag = 'FakePosInvisible',
    default = false,
    callback = function(aM)
        local aN = getgenv().fpos.client_root

        getgenv().fpos.enabled = aM

        getgenv().updateDummy()

        if aM then
            getgenv().fpos.enable_hook()
        else
            if aN and getgenv().fpos.saved_cframe then
                aN.CFrame = getgenv().fpos.saved_cframe
            end

            getgenv().fpos.disable_hook()

            getgenv().fpos.saved_cframe = nil
            getgenv().fpos.is_elevated = false
        end
    end,
}
aK:keybind{
    flags = 'uginvs',
    default = nil,
    callback = function(aM)
        getgenv().fpos.enabled = not getgenv().fpos.enabled

        getgenv().updateDummy()
    end,
}
aK:toggle{
    name = 'void desync',
    flag = 'uytrrntyuntruntr',
    default = false,
    callback = function(aM)
        getgenv().csync.selectedMode = aM and 'Void' or 'CLICK ME TO DISABLE DESYNC'
    end,
}
aK:keybind{
    flags = 'ugiggggnvs',
    default = nil,
    callback = function(aM)
        local aN = getgenv().csync.selectedMode == 'Void'

        getgenv().csync.selectedMode = (not aN) and 'Void' or 'CLICK ME TO DISABLE DESYNC'
    end,
}
game:GetService'RunService'.Heartbeat:Connect(LPH_JIT_MAX(function(aM)
    local aN = getgenv().fpos.client_root

    if not aN then
        return
    end
    if getgenv().fpos.enabled then
        if not getgenv().fpos.hook then
            getgenv().fpos.enable_hook()
        end

        getgenv().fpos.timer = getgenv().fpos.timer + aM

        if getgenv().fpos.timer >= 0.133 then
            getgenv().fpos.timer = 0
            getgenv().fpos.is_elevated = not getgenv().fpos.is_elevated
        end

        local aO = CFrame.Angles(math.rad(math.random(-180, 180)), math.rad(math.random(-180, 180)), math.rad(math.random(-180, 180)))
        local aP = getgenv().fpos.getUndergroundCFrame() * aO

        getgenv().fpos.saved_cframe = aN.CFrame
        aN.CFrame = aP

        game:GetService'RunService'.RenderStepped:Wait()

        aN.CFrame = getgenv().fpos.saved_cframe
    end
end))
game:GetService'RunService'.RenderStepped:Connect(LPH_JIT_MAX(function()
    if getgenv().csync.VisualizeEnabled or getgenv().fpos.enabled or getgenv().network.velocity_enabled or getgenv().network.enabled then
        getgenv().updateDummy()
    elseif getgenv().csync.dummy and getgenv().csync.dummy.Parent then
        getgenv().csync.dummy.Parent = nil
    end
end))
game:GetService'RunService'.Heartbeat:Connect(LPH_JIT_MAX(function(aM)
    local aN = getgenv().csync.client_root

    if not aN then
        return
    end

    local aO = getgenv().csync.enabled

    getgenv().csync.enabled = getgenv().csync.selectedMode ~= 'CLICK ME TO DISABLE DESYNC'
    getgenv().csync.mode = getgenv().csync.selectedMode

    if getgenv().csync.enabled then
        if not aO then
            getgenv().enable_hook()
        end

        getgenv().csync.timer = getgenv().csync.timer + aM

        local aP = getgenv().csync.is_elevated and getgenv().csync.void_time or getgenv().csync.normal_time

        if getgenv().csync.timer >= aP then
            getgenv().csync.timer = 0
            getgenv().csync.is_elevated = not getgenv().csync.is_elevated
        end

        local aQ = CFrame.Angles(math.rad(math.random(-180, 180)), math.rad(math.random(-180, 180)), math.rad(math.random(-180, 180)))
        local aR = getgenv().getDummyCFrame() * aQ

        getgenv().csync.saved_cframe = aN.CFrame
        aN.CFrame = aR

        game:GetService'RunService'.RenderStepped:Wait()

        aN.CFrame = getgenv().csync.saved_cframe
    elseif aO then
        if getgenv().csync.hook then
            getgenv().disable_hook()
        end

        getgenv().csync.saved_cframe = nil
        getgenv().csync.is_elevated = false
    end
end))
game:GetService'RunService'.PostSimulation:Connect(LPH_JIT_MAX(function()
    if getgenv().network.enabled and getgenv().fpos.client_root then
        getgenv().network.sleeping = not getgenv().network.sleeping

        sethiddenproperty(getgenv().fpos.client_root, 'NetworkIsSleeping', getgenv().network.sleeping)
    end
end))
aK:toggle{
    name = 'void spam',
    flag = 'uhjh65hkg',
    default = false,
    callback = function(aM)
        getgenv().csync.selectedMode = aM and 'Void Spam' or 'CLICK ME TO DISABLE DESYNC'
    end,
}
aK:keybind{
    flags = 'ughjjkreggh',
    default = nil,
    callback = function()
        local aM = getgenv().csync.selectedMode == 'Void Spam'

        getgenv().csync.selectedMode = (not aM) and 'Void Spam' or 'CLICK ME TO DISABLE DESYNC'
    end,
}
aK:slider{
    name = 'in void',
    flag = 'dfdgehrt6hn',
    default = 0.4,
    min = 0,
    max = 1,
    interval = 0.001,
    callback = function(aM)
        getgenv().csync.void_time = aM
    end,
}
aK:slider{
    name = 'out of void',
    flag = 'dfdgehrhhhhht6hn',
    default = 0.133,
    min = 0,
    max = 1,
    interval = 0.001,
    callback = function(aM)
        getgenv().csync.normal_time = aM
    end,
}

_G.Emotes = {
    Enabled = false,
    CurrentAnimation = nil,
    DefaultAnim = 'rbxassetid://5917459365',
    Anims = {
        kickinglegs = 120370790028350,
        spongebobdance = 18443245017,
        teleport = 104767795538635,
        crossed = 128386160365167,
        imagination = 18443237526,
        yungblud = 15609995579,
        laugh = 3337966527,
        floss = 5917459365,
        sleep = 4686925579,
        hype = 3695333486,
        sad = 4841407203,
        goofyhands = 14496531574,
        heyyamove = 119734573196374,
        animeah = 78982325370329,
        invisibleme = 126995783634131,
        strangerthings = 70692992882447,
        tornado = 135373056067761,
        jabbaswitchway = 77791964179635,
        invisibleme2 = 112119483472206,
    },
}
_G.PlayEmote = function(aM, aN)
    aN = tonumber(aN) or 1
    _G.Char = game:GetService'Players'.LocalPlayer.Character or game:GetService'Players'.LocalPlayer.CharacterAdded:Wait()
    _G.Hum = _G.Char:WaitForChild('Humanoid', 5)

    if not _G.Hum then
        return
    end

    _G.Animator = _G.Hum:FindFirstChildOfClass'Animator'

    if not _G.Animator then
        return
    end
    if _G.Emotes.CurrentAnimation then
        pcall(function()
            _G.Emotes.CurrentAnimation:Stop()
        end)

        _G.Emotes.CurrentAnimation = nil
    end

    _G.Id = _G.Emotes.Anims[aM]

    if not _G.Id then
        return
    end

    _G.Anim = Instance.new'Animation'
    _G.Anim.AnimationId = 'rbxassetid://' .. tostring(_G.Id)
    _G.Track = _G.Animator:LoadAnimation(_G.Anim)
    _G.Track.Priority = Enum.AnimationPriority.Action4
    _G.Track.Looped = true

    _G.Track:Play()
    _G.Track:AdjustSpeed(aN)

    _G.Emotes.CurrentAnimation = _G.Track
end
_G.StopEmote = function()
    if _G.Emotes.CurrentAnimation then
        pcall(function()
            _G.Emotes.CurrentAnimation:Stop()
        end)

        _G.Emotes.CurrentAnimation = nil
    end
end
_G.EmotesGUI = O:section{
    name = 'emotes',
    side = 'right',
}

_G.EmotesGUI:toggle{
    name = 'enabled',
    flag = 'emotes_enabled',
    default = false,
    callback = function(aM)
        _G.Emotes.Enabled = aM

        if not aM then
            _G.StopEmote()

            return
        end

        _G.Sel = H.flags.emotes_select
        _G.Spd = (H.flags.emotes_speed or 10) / 10

        _G.PlayEmote(_G.Sel, _G.Spd > 0 and _G.Spd or 1)
    end,
}
_G.EmotesGUI:dropdown{
    name = 'selected emote',
    flag = 'emotes_select',
    items = {
        'kickinglegs',
        'heyyamove',
        'animeah',
        'spongebobdance',
        'crossed',
        'invisibleme',
        'imagination',
        'yungblud',
        'strangerthings',
        'laugh',
        'floss',
        'sleep',
        'hype',
        'sad',
        'goofyhands',
        'tornado',
        'jabbaswitchway',
    },
    callback = function(aM)
        if _G.Emotes.Enabled then
            _G.Spd = (H.flags.emotes_speed or 10) / 10

            _G.PlayEmote(aM, _G.Spd > 0 and _G.Spd or 1)
        end
    end,
}
_G.EmotesGUI:slider{
    name = 'emote speed',
    flag = 'emotes_speed',
    min = 0,
    max = 100,
    default = 10,
    callback = function(aM)
        if _G.Emotes.Enabled and _G.Emotes.CurrentAnimation then
            _G.Emotes.CurrentAnimation:AdjustSpeed(aM / 10)
        end
    end,
}
game:GetService'Players'.LocalPlayer.CharacterAdded:Connect(function()
    task.wait(2)

    if _G.Emotes.Enabled then
        _G.Sel = H.flags.emotes_select
        _G.Spd = (H.flags.emotes_speed or 10) / 10

        _G.PlayEmote(_G.Sel, _G.Spd > 0 and _G.Spd or 1)
    end
end)

_G.antimodd = O:section{
    name = 'anti mod',
    side = 'left',
}
getgenv().antistaff = {
    Enabled = false,
    Kick = true,
    Notify = false,
    GroupId = 8068202,
}

_G.antimodd:toggle{
    name = 'enabled',
    flag = 'antimod_enabled',
    default = false,
    callback = function(aM)
        getgenv().antistaff.Enabled = aM
    end,
}
_G.antimodd:dropdown{
    name = 'to do',
    flag = 'antimod_action',
    items = {
        'kick',
        'notify',
    },
    callback = function(aM)
        if aM == 'kick' then
            getgenv().antistaff.Kick = true
            getgenv().antistaff.Notify = false
        else
            getgenv().antistaff.Kick = false
            getgenv().antistaff.Notify = true
        end
    end,
}
game:GetService'Players'.PlayerAdded:Connect(function(aM)
    if getgenv().antistaff.Enabled and aM:IsInGroup(getgenv().antistaff.GroupId) then
        if getgenv().antistaff.Notify then
            H:notification{
                text = 'Moderator detected: ' .. aM.Name,
                duration = 8,
            }
        end
        if getgenv().antistaff.Kick then
            task.wait(3)
            game:GetService'Players'.LocalPlayer:Kick('Moderator detected: ' .. aM.Name)
        end
    end
end)

for aM, aN in q(game:GetService'Players':GetPlayers())do
    if aN ~= game:GetService'Players'.LocalPlayer and getgenv().antistaff.Enabled and aN:IsInGroup(getgenv().antistaff.GroupId) then
        if getgenv().antistaff.Notify then
            H:notification{
                text = 'Moderator in-game: ' .. aN.Name,
                duration = 8,
            }
        end
        if getgenv().antistaff.Kick then
            task.wait(3)
            game:GetService'Players'.LocalPlayer:Kick('Moderator already in-game: ' .. aN.Name)
        end

        break
    end
end

local aM = O:section{
    name = 'chat sender',
    side = 'right',
}

_G.ChatSpam_Enabled = false
_G.ChatSpam_TrashTalk_Enabled = false
_G.ChatSpam_Custom_Enabled = false
_G.ChatSpam_CustomText = 'ur noob, haha, too easy'
_G.ChatSpam_Delay = 3
_G.ChatSpam_LastTime = 0
_G.ChatSpam_Index = 1
_G.ChatSpam_History = {}
_G.TrashTalkList = {
    'imagine getting cracked by sample \u{1f480}',
    'getsample.lol',
    'get better buddy',
    'skill issue',
    'get sample.hit today',
    'stop \u{1f602}',
    'free script btw',
    'mad?',
    'cry about it',
    'trash',
    'noob lol',
    'owned by sample',
    'get rekt',
    "you're bad",
    'stay mad with no sample',
    'no sample = no skill',
    'washed',
    'dogwater',
    '200 pumped by sample',
}

aM:toggle{
    name = 'master toggle',
    flag = 'chat_master',
    default = false,
    callback = function(aN)
        _G.ChatSpam_Enabled = aN
    end,
}
aM:toggle{
    name = 'trash talk',
    flag = 'chat_trash',
    default = false,
    callback = function(aN)
        _G.ChatSpam_TrashTalk_Enabled = aN

        if aN then
            _G.ChatSpam_Custom_Enabled = false

            if I then
                I.chat_custom = false
            end
        end
    end,
}
aM:toggle{
    name = 'custom chats',
    flag = 'chat_custom',
    default = false,
    callback = function(aN)
        _G.ChatSpam_Custom_Enabled = aN

        if aN then
            _G.ChatSpam_TrashTalk_Enabled = false

            if I then
                I.chat_trash = false
            end
        end
    end,
}
aM:textbox{
    name = 'custom messages',
    flag = 'chat_custom_text',
    callback = function(aN)
        _G.ChatSpam_CustomText = aN
    end,
}
aM:slider{
    name = 'global delay',
    suffix = 's',
    flag = 'chat_delay',
    default = 3,
    min = 1.5,
    max = 20,
    interval = 0.5,
    callback = function(aN)
        _G.ChatSpam_Delay = aN
    end,
}
task.spawn(function()
    while task.wait(0.1) do
        if _G.ChatSpam_Enabled then
            if _G.ChatSpam_TrashTalk_Enabled or _G.ChatSpam_Custom_Enabled then
                local aN = n()

                if aN - _G.ChatSpam_LastTime >= _G.ChatSpam_Delay then
                    local aO = ''

                    if _G.ChatSpam_TrashTalk_Enabled then
                        aO = _G.TrashTalkList[_G.ChatSpam_Index]
                        _G.ChatSpam_Index = (_G.ChatSpam_Index % #_G.TrashTalkList) + 1
                    elseif _G.ChatSpam_Custom_Enabled then
                        local aP = {}

                        for aQ in _G.ChatSpam_CustomText:gmatch'([^,]+)'do
                            table.insert(aP, aQ:match'^%s*(.-)%s*$')
                        end

                        if #aP > 0 then
                            local aQ = ''
                            local aR = 0

                            repeat
                                aQ = aP[math.random(1, #aP)]
                                aR = aR + 1

                                local aS = false

                                for Z, _ in q(_G.ChatSpam_History)do
                                    if _ == aQ then
                                        aS = true

                                        break
                                    end
                                end
                            until not aS or aR > 10

                            aO = aQ
                        else
                            aO = _G.ChatSpam_CustomText
                        end
                    end
                    if aO ~= '' then
                        table.insert(_G.ChatSpam_History, aO)

                        if #_G.ChatSpam_History > 4 then
                            table.remove(_G.ChatSpam_History, 1)
                        end

                        pcall(function()
                            local aP = game:GetService'TextChatService'

                            if aP.ChatVersion == Enum.ChatVersion.TextChatService then
                                local aQ = aP.TextChannels:FindFirstChild'RBXGeneral' or aP.TextChannels:FindFirstChildOfClass'TextChannel'

                                if aQ then
                                    aQ:SendAsync(aO)
                                end
                            else
                                local aQ = game:GetService'ReplicatedStorage':FindFirstChild'DefaultChatSystemChatEvents'

                                if aQ then
                                    aQ.SayMessageRequest:FireServer(aO, 'All')
                                end
                            end
                        end)

                        _G.ChatSpam_LastTime = aN
                    end
                end
            end
        end
    end
end)

if not _G.Config then
    _G.Config = {}
end
if not _G.Config.Box then
    _G.Config.Box = {
        MasterEnabled = false,
        Enable = false,
        SelfESP = false,
        Rotatingg = false,
        AnimType = 'forward and backward',
        AnimSpeed = 1.5,
        OutlineColor = i(255, 255, 255),
        FillColor = i(255, 255, 255),
        Filled = {
            Enable = false,
            Transparency = 0.5,
            Color1 = i(255, 255, 255),
            Color2 = i(0, 0, 0),
        },
        Glow = {
            Enable = false,
            Intensity = 0.12,
            Color = i(0, 225, 255),
        },
        Healthbar = {
            Enable = false,
            Thickness = 1,
        },
        HealthLerp = {Enable = false},
        HealthLerpColors = {
            Color1 = i(255, 0, 0),
            Color2 = i(255, 255, 0),
            Color3 = i(0, 255, 0),
        },
        GradientOutline = {
            Color1 = i(255, 255, 255),
            Color2 = i(255, 255, 255),
            Color3 = i(255, 255, 255),
            Color4 = i(255, 255, 255),
            Color5 = i(255, 255, 255),
            Color6 = i(255, 255, 255),
        },
    }
end
if not _G.healthoffseth then
    _G.healthoffseth = 2
end
if not _G.ESPObjects then
    _G.ESPObjects = {}
end
if not _G.Config.TextESP then
    _G.Config.TextESP = {
        Names = false,
        Tools = false,
        NameSize = 11,
        ToolSize = 11,
        NameOffset = 16,
    }
end

local aN = _G.Config.Box
local aO = _G.ESPObjects
local aP = _G.Config.TextESP
local aQ = LPH_NO_VIRTUALIZE(function(aQ)
    if not aQ then
        return false
    end

    local aR, aS = V:WorldToViewportPoint(aQ.Position)

    return aS
end)
local aR = LPH_NO_VIRTUALIZE(function(aR, aS, Z, _)
    if _ < 0.5 then
        return aR:lerp(aS, _ * 2)
    else
        return aS:lerp(Z, (_ - 0.5) * 2)
    end
end)
local aS = LPH_NO_VIRTUALIZE(function(aS)
    if aO[aS] then
        return
    end

    local Z = {}
    local _ = 40

    Z.OutlineSegments = {}

    for aT = 1, _ do
        local aU = {}

        for aV = 1, 4 do
            local aW = e'Square'

            aW.Visible = false
            aW.Filled = true
            aU[aV] = aW
        end

        Z.OutlineSegments[aT] = aU
    end

    Z.OuterOutline = e'Square'
    Z.OuterOutline.Visible = false
    Z.OuterOutline.Thickness = 0.8
    Z.OuterOutline.Color = i(0, 0, 0)
    Z.InnerOutline = e'Square'
    Z.InnerOutline.Visible = false
    Z.InnerOutline.Thickness = 0.5
    Z.InnerOutline.Color = i(0, 0, 0)
    Z.Health = e'Square'
    Z.Health.Visible = false
    Z.Health.Filled = true
    Z.HealthOutline = e'Square'
    Z.HealthOutline.Visible = false
    Z.HealthOutline.Thickness = 0.5
    Z.HealthOutline.Color = i(0, 0, 0)
    Z.HealthSegments = {}

    for aT = 1, 29 do
        local aU = e'Square'

        aU.Visible = false
        aU.Filled = true
        Z.HealthSegments[aT] = aU
    end

    Z.GradientSegments = {}

    for aT = 1, 130 do
        local aU = e'Square'

        aU.Visible = false
        aU.Filled = true
        Z.GradientSegments[aT] = aU
    end

    Z.GlowLayers = {}

    for aT = 1, 15 do
        local aU = e'Square'

        aU.Visible = false
        aU.Filled = false
        aU.Thickness = aT * 2
        aU.Color = aN.Glow.Color
        Z.GlowLayers[aT] = aU
    end

    Z.NameText = e'Text'
    Z.NameText.Visible = false
    Z.NameText.Center = true
    Z.NameText.Outline = true
    Z.NameText.Color = i(255, 255, 255)
    Z.NameText.Font = 2
    Z.ToolText = e'Text'
    Z.ToolText.Visible = false
    Z.ToolText.Center = true
    Z.ToolText.Outline = true
    Z.ToolText.Color = i(255, 255, 255)
    Z.ToolText.Font = 2
    aO[aS] = Z
end)
local aT = LPH_NO_VIRTUALIZE(function(aT)
    local aU = aO[aT]

    if not aU then
        return
    end

    aU.OuterOutline:Remove()
    aU.InnerOutline:Remove()
    aU.Health:Remove()
    aU.HealthOutline:Remove()
    aU.NameText:Remove()
    aU.ToolText:Remove()

    for aV, aW in q(aU.OutlineSegments)do
        aW[1]:Remove()
        aW[2]:Remove()
        aW[3]:Remove()
        aW[4]:Remove()
    end
    for aV, aW in q(aU.HealthSegments)do
        aW:Remove()
    end
    for aV, aW in q(aU.GradientSegments)do
        aW:Remove()
    end
    for aV, aW in q(aU.GlowLayers)do
        aW:Remove()
    end

    aO[aT] = nil
end)
local aU = LPH_NO_VIRTUALIZE(function(aU)
    local aV = aU.Character

    if not aV then
        return false
    end

    local aW = aV:FindFirstChild'BodyEffects'

    if aW then
    end

    return false
end)
local aV = LPH_NO_VIRTUALIZE(function()
    local aV = n() * (aN.AnimSpeed or 1.5)
    local aW = aN.MasterEnabled
    local Z = aN.Enable
    local _ = aN.SelfESP
    local aX = aN.Rotatingg
    local aY = aN.AnimType
    local aZ = aN.Filled
    local a_ = aN.Glow
    local a0 = aN.Healthbar.Enable
    local a1 = aN.Healthbar.Thickness
    local a2 = aN.HealthLerpColors
    local a3 = aN.GradientOutline
    local a4 = P:GetPlayers()
    local a5 = g(4, 5.5, 2)
    local a6 = a5 / 2
    local a7 = workspace.CurrentCamera

    for a8 = 1, #a4 do
        local a9 = a4[a8]

        if a9 == U and not _ then
            aT(a9)

            continue
        end

        local ba = a9.Character
        local bb = ba and ba:FindFirstChild'Humanoid'
        local bc = ba and ba:FindFirstChild'HumanoidRootPart'

        if not bb or not bc then
            aT(a9)

            continue
        end
        if a9 ~= U and aU(a9) then
            aT(a9)

            continue
        end

        local bd = aO[a9]

        if not bd then
            aS(a9)

            bd = aO[a9]
        end

        local be, bf = a7:WorldToViewportPoint(bc.Position)

        if not (aW and (a9 == U or bf)) then
            bd.OuterOutline.Visible = false
            bd.InnerOutline.Visible = false
            bd.Health.Visible = false
            bd.HealthOutline.Visible = false
            bd.NameText.Visible = false
            bd.ToolText.Visible = false

            local bg = bd.OutlineSegments

            for bh = 1, #bg do
                local bi = bg[bh]

                bi[1].Visible = false
                bi[2].Visible = false
                bi[3].Visible = false
                bi[4].Visible = false
            end

            local bh = bd.HealthSegments

            for bi = 1, #bh do
                bh[bi].Visible = false
            end

            local bi = bd.GradientSegments

            for bj = 1, #bi do
                bi[bj].Visible = false
            end

            local bj = bd.GlowLayers

            for bk = 1, #bj do
                bj[bk].Visible = false
            end

            continue
        end

        local bg = bc.CFrame
        local bh, bi, bj, bk = j, j, -j, -j
        local bl = false
        local bm = {
            bg * h(-a6.X, a6.Y, a6.Z),
            bg * h(a6.X, a6.Y, a6.Z),
            bg * h(-a6.X, -a6.Y, a6.Z),
            bg * h(a6.X, -a6.Y, a6.Z),
            bg * h(-a6.X, a6.Y, -a6.Z),
            bg * h(a6.X, a6.Y, -a6.Z),
            bg * h(-a6.X, -a6.Y, -a6.Z),
            bg * h(a6.X, -a6.Y, -a6.Z),
        }

        for bn = 1, 8 do
            local bo, bp = a7:WorldToViewportPoint(bm[bn].Position)

            if bp then
                bl = true

                local bq, br = bo.X, bo.Y

                if bq < bh then
                    bh = bq
                end
                if br < bi then
                    bi = br
                end
                if bq > bj then
                    bj = bq
                end
                if br > bk then
                    bk = br
                end
            end
        end

        if not bl then
            local bn = bd.GradientSegments

            for bo = 1, #bn do
                bn[bo].Visible = false
            end

            local bo = bd.GlowLayers

            for bp = 1, #bo do
                bo[bp].Visible = false
            end

            continue
        end

        local bn, bo = bj - bh, bk - bi
        local bp = a_.Enable and Z
        local bq = bd.GlowLayers

        for br = 1, #bq do
            local bs = bq[br]

            if bp then
                local bt = br * 3

                bs.Visible = true
                bs.Size = f(bn + bt, bo + bt)
                bs.Position = f(bh - (bt / 2), bi - (bt / 2))
                bs.Transparency = k(a_.Intensity / (br * 0.8), 0, 1)
                bs.Color = a_.Color
            else
                bs.Visible = false
            end
        end

        local br = bd.OutlineSegments
        local bs = #br
        local bt = bo / bs
        local bu = bn / bs

        for bv = 1, bs do
            local bw = br[bv]
            local bx = (bv - 1) / (bs - 1)
            local by = bx

            if aX then
                if aY == 'circling box to left' then
                    by = (bx + aV) % 1
                elseif aY == 'circling box to right' then
                    by = (bx - aV) % 1
                elseif aY == 'forward and backward' then
                    by = (l(aV + (bx * m * 2)) + 1) * 0.5
                end
            end

            local bz = by <= 0.5 and a3.Color1:lerp(a3.Color5, by * 2) or a3.Color5:lerp(a3.Color3, (by - 0.5) * 2)
            local bA = by <= 0.5 and a3.Color2:lerp(a3.Color6, by * 2) or a3.Color6:lerp(a3.Color4, (by - 0.5) * 2)
            local bB = by <= 0.5 and a3.Color1:lerp(a3.Color2, by * 2) or a3.Color2:lerp(a3.Color1, (by - 0.5) * 2)
            local bC = by <= 0.5 and a3.Color3:lerp(a3.Color4, by * 2) or a3.Color4:lerp(a3.Color3, (by - 0.5) * 2)

            bw[1].Visible = Z
            bw[1].Size = f(1, bt)
            bw[1].Position = f(bh, bi + (bv - 1) * bt)
            bw[1].Color = bz
            bw[2].Visible = Z
            bw[2].Size = f(1, bt)
            bw[2].Position = f(bj - 1, bi + (bv - 1) * bt)
            bw[2].Color = bA
            bw[3].Visible = Z
            bw[3].Size = f(bu, 1)
            bw[3].Position = f(bh + (bv - 1) * bu, bi)
            bw[3].Color = bB
            bw[4].Visible = Z
            bw[4].Size = f(bu, 1)
            bw[4].Position = f(bh + (bv - 1) * bu, bk - 1)
            bw[4].Color = bC
        end

        local bv = bd.GradientSegments
        local bw = #bv

        if aZ.Enable and Z then
            local bx = (bo - 4) / bw

            for by = 1, bw do
                local bz = bv[by]

                bz.Visible = true
                bz.Size = f(bn - 4, bx + 0.5)
                bz.Position = f(bh + 2, bi + 2 + (by - 1) * bx)
                bz.Transparency = aZ.Transparency
                bz.Color = aZ.Color1:lerp(aZ.Color2, (by - 1) / (bw - 1))
            end
        else
            for bx = 1, bw do
                bv[bx].Visible = false
            end
        end

        bd.OuterOutline.Visible = Z
        bd.OuterOutline.Size = f(bn + 2, bo + 2)
        bd.OuterOutline.Position = f(bh - 1, bi - 1)
        bd.InnerOutline.Visible = Z
        bd.InnerOutline.Size = f(bn - 2, bo - 2)
        bd.InnerOutline.Position = f(bh + 1, bi + 1)

        if a0 then
            local bx = k(bb.Health / bb.MaxHealth, 0, 1)
            local by = bo * bx
            local bz = bh - a1 - 3

            bd.HealthOutline.Visible = true
            bd.HealthOutline.Size = f(a1 + 2, bo + 2)
            bd.HealthOutline.Position = f(bz - 1, bi - 1)

            local bA = bd.HealthSegments
            local bB = #bA
            local bC = by / bB

            for bD = 1, bB do
                local bE = bA[bD]

                bE.Visible = true
                bE.Size = f(a1, bC + 0.5)
                bE.Position = f(bz, bi + (bo - by) + (bD - 1) * bC)
                bE.Color = aR(a2.Color1, a2.Color2, a2.Color3, bx * (bD / bB))
            end
        else
            bd.HealthOutline.Visible = false

            local bx = bd.HealthSegments

            for by = 1, #bx do
                bx[by].Visible = false
            end
        end
        if aP.Names then
            bd.NameText.Visible = true
            bd.NameText.Text = a9.DisplayName or a9.Name
            bd.NameText.Size = aP.NameSize
            bd.NameText.Position = f(bh + bn * 0.5, bi - aP.NameOffset)
        else
            bd.NameText.Visible = false
        end
        if aP.Tools then
            local bx = ba:FindFirstChildOfClass'Tool'

            if bx then
                bd.ToolText.Visible = true
                bd.ToolText.Text = bx.Name
                bd.ToolText.Size = aP.ToolSize
                bd.ToolText.Position = f(bh + bn * 0.5, bk + 5)
            else
                bd.ToolText.Visible = false
            end
        else
            bd.ToolText.Visible = false
        end
    end
end)

P.PlayerRemoving:Connect(aT)
T.RenderStepped:Connect(aV)

local aW = N:section{
    name = 'esp',
}

aW:toggle{
    name = 'enabled',
    flag = 'box_master',
    default = _G.Config.Box.MasterEnabled,
    callback = function(aX)
        _G.Config.Box.MasterEnabled = aX
    end,
}
aW:toggle{
    name = 'self esp',
    flag = 'selfesp',
    default = false,
    callback = function(aX)
        _G.Config.Box.SelfESP = aX
    end,
}
aW:toggle{
    name = 'boxes',
    flag = 'box_enabled2',
    default = _G.Config.Box.Enable,
    callback = function(aX)
        _G.Config.Box.Enable = aX
    end,
}

for aX = 1, 6 do
    aW:colorpicker{
        flag = 'box_grad_' .. aX,
        color = _G.Config.Box.GradientOutline['Color' .. aX],
        callback = function(aY)
            _G.Config.Box.GradientOutline['Color' .. aX] = aY
        end,
    }
end

aW:toggle{
    name = 'outline moving animation',
    flag = 'box_anim_toggle',
    default = false,
    callback = function(aX)
        _G.Config.Box.Rotatingg = aX
    end,
}
aW:dropdown{
    name = 'moving animation type',
    flag = 'box_anim_type',
    items = {
        'circling box to left',
        'circling box to right',
        'forward and backward',
    },
    multi = false,
    callback = function(aX)
        _G.Config.Box.AnimType = aX
    end,
}
aW:slider{
    name = 'moving animation speed',
    flag = 'box_anim_speed',
    default = _G.Config.Box.AnimSpeed,
    min = 0,
    max = 10,
    interval = 0.05,
    callback = function(aX)
        _G.Config.Box.AnimSpeed = aX
    end,
}
aW:toggle{
    name = 'filled',
    flag = 'box_filled',
    default = _G.Config.Box.Filled.Enable,
    callback = function(aX)
        _G.Config.Box.Filled.Enable = aX
    end,
}
aW:colorpicker{
    flag = 'box_fill_c1',
    color = _G.Config.Box.Filled.Color1,
    callback = function(aX)
        _G.Config.Box.Filled.Color1 = aX
    end,
}
aW:colorpicker{
    flag = 'box_fill_c2',
    color = _G.Config.Box.Filled.Color2,
    callback = function(aX)
        _G.Config.Box.Filled.Color2 = aX
    end,
}
aW:slider{
    name = 'fill transparency',
    flag = 'box_fill_trans',
    default = _G.Config.Box.Filled.Transparency,
    min = 0,
    max = 1,
    interval = 0.05,
    callback = function(aX)
        _G.Config.Box.Filled.Transparency = aX
    end,
}
aW:toggle{
    name = 'glow',
    flag = 'box_glow_enabled',
    default = _G.Config.Box.Glow.Enable,
    callback = function(aX)
        _G.Config.Box.Glow.Enable = aX
    end,
}
aW:colorpicker{
    flag = 'box_glow_color',
    color = _G.Config.Box.Glow.Color,
    callback = function(aX)
        _G.Config.Box.Glow.Color = aX
    end,
}
aW:slider{
    name = 'glow intensity',
    flag = 'box_glow_intense',
    default = _G.Config.Box.Glow.Intensity * 100,
    min = 0,
    max = 8,
    interval = 2,
    callback = function(aX)
        _G.Config.Box.Glow.Intensity = aX / 100
    end,
}
aW:toggle{
    name = 'healthbar',
    flag = 'healthbar',
    default = _G.Config.Box.Healthbar.Enable,
    callback = function(aX)
        _G.Config.Box.Healthbar.Enable = aX
        _G.Config.Box.HealthLerp.Enable = aX
    end,
}

for aX = 1, 3 do
    aW:colorpicker{
        flag = 'hp_c' .. aX,
        color = _G.Config.Box.HealthLerpColors['Color' .. aX],
        callback = function(aY)
            _G.Config.Box.HealthLerpColors['Color' .. aX] = aY
        end,
    }
end

aW:toggle{
    name = 'names',
    flag = 'esp_names',
    default = _G.Config.TextESP.Names,
    callback = function(aX)
        _G.Config.TextESP.Names = aX
    end,
}
aW:toggle{
    name = 'tools',
    flag = 'esp_tools',
    default = _G.Config.TextESP.Tools,
    callback = function(aX)
        _G.Config.TextESP.Tools = aX
    end,
}
aW:slider{
    name = 'names size',
    flag = 'esp_names_size',
    default = _G.Config.TextESP.NameSize,
    min = 8,
    max = 32,
    interval = 1,
    callback = function(aX)
        _G.Config.TextESP.NameSize = aX
    end,
}
aW:slider{
    name = 'tools size',
    flag = 'esp_tools_size',
    default = _G.Config.TextESP.ToolSize,
    min = 8,
    max = 32,
    interval = 1,
    callback = function(aX)
        _G.Config.TextESP.ToolSize = aX
    end,
}

local aX = Color3.fromRGB(255, 136, 0)

_G.chams = _G.chams or false

local function aY(aZ)
    local a_ = aZ.Character

    if not a_ or a_:FindFirstChild'ChamHighlight' then
        return
    end
    if not a_:FindFirstChild'HumanoidRootPart' then
        return
    end

    local a0 = Instance.new'Highlight'

    a0.Name = 'ChamHighlight'
    a0.Parent = a_
    a0.Adornee = a_
    a0.FillColor = aX
    a0.FillTransparency = 0.5
    a0.OutlineTransparency = 1
    a0.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
end
local function aZ(a_)
    local a0 = a_.Character

    if a0 then
        local a1 = a0:FindFirstChild'ChamHighlight'

        if a1 then
            a1:Destroy()
        end
    end
end

aW:toggle{
    name = 'mesh chams',
    flag = 'chams_enabled',
    default = false,
    callback = function(a_)
        _G.chams = a_

        local a0 = game.Players:GetPlayers()

        for a1 = 1, #a0 do
            local a2 = a0[a1]

            if not _G.chams then
                aZ(a2)
            else
                if a2 ~= game.Players.LocalPlayer or _G.Config.Box.SelfESP then
                    aY(a2)
                else
                    aZ(a2)
                end
            end
        end
    end,
}
aW:colorpicker{
    flag = 'highlight_color',
    color = aX,
    callback = function(a_)
        aX = a_

        local a0 = game.Players:GetPlayers()

        for a1 = 1, #a0 do
            local a2 = a0[a1].Character and a0[a1].Character:FindFirstChild'ChamHighlight'

            if a2 then
                a2.FillColor = aX
            end
        end
    end,
}
game.Players.PlayerAdded:Connect(function(a_)
    a_.CharacterAdded:Connect(function(a0)
        if _G.chams then
            if a_ ~= game.Players.LocalPlayer or _G.Config.Box.SelfESP then
                a0:WaitForChild'HumanoidRootPart'
                aY(a_)
            end
        end
    end)
end)
game.Players.PlayerRemoving:Connect(function(a_)
    aZ(a_)
end)
game:GetService'RunService'.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
    if _G.chams then
        local a_ = game.Players:GetPlayers()
        local a0 = game.Players.LocalPlayer

        for a1 = 1, #a_ do
            local a2 = a_[a1]
            local a3 = (a2 == a0)

            if a3 and not _G.Config.Box.SelfESP then
                aZ(a2)

                continue
            end
            if (not a3 or _G.Config.Box.SelfESP) and a2.Character then
                if not a2.Character:FindFirstChild'ChamHighlight' then
                    local a4 = a2.Character:FindFirstChild'HumanoidRootPart'

                    if a4 then
                        local a5, a6 = game.Workspace.CurrentCamera:WorldToViewportPoint(a4.Position)

                        if a6 then
                            aY(a2)
                        end
                    end
                end
            end
        end
    else
        local a_ = game.Players:GetPlayers()

        for a0 = 1, #a_ do
            aZ(a_[a0])
        end
    end
end))

_G.v992kk_enabled = false
_G.v992kk_color = Color3.fromRGB(255, 255, 255)
_G.v992kk_cache = _G.v992kk_cache or {}
_G.v992kk_folder = _G.v992kk_folder or nil
_G.v992kk_parts = {
    'Head',
    'UpperTorso',
    'LowerTorso',
    'LeftUpperArm',
    'LeftLowerArm',
    'LeftHand',
    'RightUpperArm',
    'RightLowerArm',
    'RightHand',
    'LeftUpperLeg',
    'LeftLowerLeg',
    'LeftFoot',
    'RightUpperLeg',
    'RightLowerLeg',
    'RightFoot',
}
_G.v992kk_init = function()
    if not _G.v992kk_folder then
        _G.v992kk_folder = Instance.new'Folder'
        _G.v992kk_folder.Name = 'ch_rt'
        _G.v992kk_folder.Parent = game:GetService'Players'.LocalPlayer:WaitForChild'PlayerGui'
    end

    return _G.v992kk_folder
end
_G.v992kk_clear = function(a_)
    if _G.v992kk_cache[a_] then
        for a0 = 1, #_G.v992kk_cache[a_]do
            _G.v992kk_cache[a_][a0]:Destroy()
        end

        _G.v992kk_cache[a_] = nil
    end
end
_G.v992kk_apply = LPH_NO_VIRTUALIZE(function(a_)
    local a0 = a_.Character

    if not a0 or not _G.v992kk_enabled then
        _G.v992kk_clear(a_)

        return
    end
    if a_ == game.Players.LocalPlayer and not _G.Config.Box.SelfESP then
        _G.v992kk_clear(a_)

        return
    end

    local a1 = a0:FindFirstChild'HumanoidRootPart'

    if a1 then
        local a2, a3 = game.Workspace.CurrentCamera:WorldToViewportPoint(a1.Position)

        if not a3 then
            _G.v992kk_clear(a_)

            return
        end
    end
    if _G.v992kk_cache[a_] then
        local a2 = _G.v992kk_cache[a_]

        for a3 = 1, #a2 do
            a2[a3].Color3 = _G.v992kk_color
            a2[a3].Visible = true
        end

        return
    end

    local a2 = _G.v992kk_init()
    local a3 = {}

    for a4 = 1, #_G.v992kk_parts do
        local a5 = _G.v992kk_parts[a4]
        local a6 = a0:FindFirstChild(a5)

        if a6 and a6:IsA'BasePart' then
            local a7 = Instance.new'BoxHandleAdornment'

            a7.Size = (a5 == 'Head') and Vector3.new(1.1, 1.1, 1.1) or a6.Size
            a7.Adornee = a6
            a7.AlwaysOnTop = true
            a7.ZIndex = 5
            a7.Transparency = 0.5
            a7.Color3 = _G.v992kk_color
            a7.Parent = a2

            table.insert(a3, a7)
        end
    end

    _G.v992kk_cache[a_] = a3
end)
_G.v992kk_loop = LPH_NO_VIRTUALIZE(function()
    local a_ = game.Players:GetPlayers()

    for a0 = 1, #a_ do
        _G.v992kk_apply(a_[a0])
    end
end)

aW:toggle{
    name = 'blocky chams',
    flag = 'chamsaa_enabled',
    default = false,
    callback = function(a_)
        _G.v992kk_enabled = a_

        if not a_ then
            for a0, a1 in r(_G.v992kk_cache)do
                _G.v992kk_clear(a0)
            end

            if _G.v992kk_con then
                _G.v992kk_con:Disconnect()

                _G.v992kk_con = nil
            end
        else
            _G.v992kk_con = game:GetService'RunService'.RenderStepped:Connect(function()
                _G.v992kk_loop()
            end)
        end
    end,
}
aW:colorpicker{
    flag = 'highlightaaa_color',
    color = Color3.fromRGB(255, 255, 255),
    callback = function(a_)
        _G.v992kk_color = a_
    end,
}

_G.skel_sett_882 = {
    enabled = false,
    skeletonsMainColor = Color3.fromRGB(255, 255, 255),
    skeletonsOutlineColor = Color3.fromRGB(0, 0, 0),
    skeletonsMainThickness = 1,
    skeletonsOutlineThickness = 2.5,
    skeletonsMainAlpha = 0,
    skeletonsOutlineAlpha = 0,
}
_G.skel_data_991 = {
    cache = {},
    bones = {
        {
            'Head',
            'Neck',
        },
        {
            'Neck',
            'UpperTorso',
        },
        {
            'UpperTorso',
            'LowerTorso',
        },
        {
            'LowerTorso',
            'LeftUpperLeg',
        },
        {
            'LowerTorso',
            'RightUpperLeg',
        },
        {
            'LeftUpperLeg',
            'LeftLowerLeg',
        },
        {
            'RightUpperLeg',
            'RightLowerLeg',
        },
        {
            'LeftLowerLeg',
            'LeftFoot',
        },
        {
            'RightLowerLeg',
            'RightFoot',
        },
        {
            'UpperTorso',
            'LeftUpperArm',
        },
        {
            'UpperTorso',
            'RightUpperArm',
        },
        {
            'LeftUpperArm',
            'LeftLowerArm',
        },
        {
            'RightUpperArm',
            'RightLowerArm',
        },
        {
            'LeftLowerArm',
            'LeftHand',
        },
        {
            'RightLowerArm',
            'RightHand',
        },
    },
}

aW:toggle{
    name = 'skeletons',
    flag = 'skel_enabled_toggle',
    default = false,
    callback = function(a_)
        _G.skel_sett_882.enabled = a_
    end,
}
aW:colorpicker{
    flag = 'skel_color_picker',
    color = Color3.fromRGB(255, 255, 255),
    callback = function(a_)
        _G.skel_sett_882.skeletonsMainColor = a_
    end,
}

_G.skel_rem_v5 = function(a_)
    local a0 = _G.skel_data_991.cache[a_]

    if a0 then
        for a1 = 1, #a0.boneLines do
            if a0.boneLines[a1].outline then
                a0.boneLines[a1].outline:Remove()
            end
            if a0.boneLines[a1].main then
                a0.boneLines[a1].main:Remove()
            end
        end

        _G.skel_data_991.cache[a_] = nil
    end
end
_G.skel_upd_v5 = LPH_NO_VIRTUALIZE(function()
    local a_ = Q.CurrentCamera

    if not a_ then
        return
    end

    for a0, a1 in r(P:GetPlayers())do
        if a1 == U and not _G.Config.Box.SelfESP then
            _G.skel_rem_v5(a1)

            continue
        end

        local a2 = a1.Character
        local a3 = a2 and a2:FindFirstChildOfClass'Humanoid'
        local a4 = a2 and a2:FindFirstChild'HumanoidRootPart'

        if not _G.skel_sett_882.enabled or not a2 or not a3 or a3.Health <= 0 or not a4 then
            _G.skel_rem_v5(a1)

            continue
        end
        if not _G.skel_data_991.cache[a1] then
            local a5 = {}

            for a6 = 1, #_G.skel_data_991.bones do
                a5[a6] = {
                    outline = Drawing.new'Line',
                    main = Drawing.new'Line',
                }
            end

            _G.skel_data_991.cache[a1] = {
                boneLines = a5,
                player = a1,
            }
        end

        local a5 = _G.skel_data_991.cache[a1]
        local a6, a7 = a_:WorldToViewportPoint(a4.Position)

        for a8, a9 in q(_G.skel_data_991.bones)do
            local ba = a2:FindFirstChild(a9[1])
            local bb = a2:FindFirstChild(a9[2])

            if a7 and ba and bb and ba:IsA'BasePart' and bb:IsA'BasePart' then
                local bc, bd = a_:WorldToViewportPoint(ba.Position)
                local be, bf = a_:WorldToViewportPoint(bb.Position)

                if bd and bf and bc.Z > 0 and be.Z > 0 then
                    local bg = Vector2.new(bc.X, bc.Y)
                    local bh = Vector2.new(be.X, be.Y)

                    a5.boneLines[a8].outline.From = bg
                    a5.boneLines[a8].outline.To = bh
                    a5.boneLines[a8].outline.Color = _G.skel_sett_882.skeletonsOutlineColor
                    a5.boneLines[a8].outline.Thickness = _G.skel_sett_882.skeletonsOutlineThickness
                    a5.boneLines[a8].outline.Transparency = 1 - _G.skel_sett_882.skeletonsOutlineAlpha
                    a5.boneLines[a8].outline.Visible = true
                    a5.boneLines[a8].main.From = bg
                    a5.boneLines[a8].main.To = bh
                    a5.boneLines[a8].main.Color = _G.skel_sett_882.skeletonsMainColor
                    a5.boneLines[a8].main.Thickness = _G.skel_sett_882.skeletonsMainThickness
                    a5.boneLines[a8].main.Transparency = 1 - _G.skel_sett_882.skeletonsMainAlpha
                    a5.boneLines[a8].main.Visible = true
                else
                    a5.boneLines[a8].outline.Visible = false
                    a5.boneLines[a8].main.Visible = false
                end
            else
                a5.boneLines[a8].outline.Visible = false
                a5.boneLines[a8].main.Visible = false
            end
        end
    end
end)

T:UnbindFromRenderStep'SkelFinal'
T:BindToRenderStep('SkelFinal', Enum.RenderPriority.Camera.Value + 1, _G.skel_upd_v5)
P.PlayerRemoving:Connect(_G.skel_rem_v5)

getgenv().ChinaHatSettings = {
    enabled = false,
    hatColor = Color3.fromRGB(255, 136, 0),
    lightColor = Color3.fromRGB(255, 136, 0),
    lightBrightness = 1,
    lightRange = 12,
    scale = Vector3.new(1.7, 1.1, 1.7),
}

local a_ = {}

local function a0(a1)
    local a2 = a1:FindFirstChild'Head'

    if not a2 then
        return false
    end

    local a3, a4 = game.Workspace.CurrentCamera:WorldToScreenPoint(a2.Position)

    return a4
end
local function a1(a2)
    if a2 and a2.Parent then
        a2.Color = getgenv().ChinaHatSettings.hatColor

        local a3 = a2:FindFirstChildWhichIsA'PointLight'

        if a3 then
            a3.Color = getgenv().ChinaHatSettings.lightColor
            a3.Brightness = getgenv().ChinaHatSettings.lightBrightness
            a3.Range = getgenv().ChinaHatSettings.lightRange
        end
    end
end
local function a2(a3)
    if not a3 then
        return
    end

    local a4 = game.Players:GetPlayerFromCharacter(a3)

    if a4 == game.Players.LocalPlayer and not _G.Config.Box.SelfESP then
        return
    end

    local a5 = a3:FindFirstChild'Head'

    if not a5 or a3:FindFirstChild'ChinaHat' then
        return
    end

    local a6 = Instance.new'Part'

    a6.Name = 'ChinaHat'
    a6.Size = Vector3.new(1, 1, 1)
    a6.Color = getgenv().ChinaHatSettings.hatColor
    a6.Material = Enum.Material.Neon
    a6.Transparency = 0.2
    a6.CanCollide = false
    a6.Anchored = false

    local a7 = Instance.new'SpecialMesh'

    a7.MeshType = Enum.MeshType.FileMesh
    a7.MeshId = 'rbxassetid://1033714'
    a7.Scale = getgenv().ChinaHatSettings.scale
    a7.Parent = a6

    local a8 = Instance.new'Weld'

    a8.Part0 = a5
    a8.Part1 = a6
    a8.C0 = CFrame.new(0, 0.9, 0)
    a8.Parent = a6

    local a9 = Instance.new'PointLight'

    a9.Color = getgenv().ChinaHatSettings.lightColor
    a9.Brightness = getgenv().ChinaHatSettings.lightBrightness
    a9.Range = getgenv().ChinaHatSettings.lightRange
    a9.Shadows = true
    a9.Parent = a6
    a6.Parent = a3
    a_[a6] = a3

    task.spawn(function()
        while a6 and a6.Parent == a3 and a3.Parent and getgenv().ChinaHatSettings.enabled do
            if a4 == game.Players.LocalPlayer and not _G.Config.Box.SelfESP then
                break
            end

            a6.Transparency = a0(a3) and 0.2 or 1

            task.wait(0.1)
        end

        if a6 then
            a_[a6] = nil

            a6:Destroy()
        end
    end)
end
local function a3(a4)
    task.spawn(function()
        a4:WaitForChild('Head', 5)

        if getgenv().ChinaHatSettings.enabled then
            a2(a4)
        end
    end)
end

for a4, a5 in q(game.Players:GetPlayers())do
    a5.CharacterAdded:Connect(a3)

    if a5.Character then
        a3(a5.Character)
    end
end

game.Players.PlayerAdded:Connect(function(a4)
    a4.CharacterAdded:Connect(a3)
end)
aW:toggle{
    name = 'chinahat',
    flag = 'chinahat_enabled',
    default = false,
    callback = function(a4)
        getgenv().ChinaHatSettings.enabled = a4

        for a5, a6 in r(a_)do
            if a5 then
                a5:Destroy()
            end
        end

        a_ = {}

        if a4 then
            for a5, a6 in q(game.Players:GetPlayers())do
                if a6.Character then
                    a2(a6.Character)
                end
            end
        end
    end,
}

_G.d8ufjwye = {}
_G.v92mznw = workspace
_G.p01lxzq = game:GetService'TweenService'
_G.k47shrt = game:GetService'Players'
_G.q19pnvz = _G.k47shrt.LocalPlayer
_G.f28skdn = false
_G.z01nxpw = Color3.fromRGB(255, 0, 0)
_G.m33vbtq = Enum.Material.Neon
_G.j19dmxz = 3
_G.b44rpst = 0.5
_G.x02ksld = 0
_G.w99ncvz = {
    'Head',
    'UpperTorso',
    'LowerTorso',
    'LeftUpperArm',
    'LeftLowerArm',
    'LeftHand',
    'RightUpperArm',
    'RightLowerArm',
    'RightHand',
    'LeftUpperLeg',
    'LeftLowerLeg',
    'LeftFoot',
    'RightUpperLeg',
    'RightLowerLeg',
    'RightFoot',
}
_G.u77vmsq = LPH_NO_VIRTUALIZE(function(a4)
    if not _G.f28skdn or not a4 then
        return
    end

    local a5 = game.Players:GetPlayerFromCharacter(a4)

    if a5 == game.Players.LocalPlayer and not _G.Config.Box.SelfESP then
        return
    end

    _G.r01ncmx = n()

    if _G.r01ncmx - _G.x02ksld < 0.1 then
        return
    end

    _G.x02ksld = _G.r01ncmx
    _G.t55pqlm = a4:FindFirstChild'HumanoidRootPart'

    if not _G.t55pqlm then
        return
    end

    a4.Archivable = true

    local a6 = a4:Clone()

    a6.Name = 'BasePart'

    for a7, a8 in q(a6:GetChildren())do
        if a8:IsA'BasePart' then
            local a9 = false

            for ba, bb in q(_G.w99ncvz)do
                if a8.Name == bb then
                    a9 = true

                    break
                end
            end

            if not a9 then
                a8:Destroy()
            end
        elseif not a8:IsA'Humanoid' then
            a8:Destroy()
        end
    end

    if a6:FindFirstChild'Humanoid' then
        a6.Humanoid:Destroy()
    end

    for a7, a8 in q(a6:GetChildren())do
        if a8:IsA'BasePart' then
            a8.CanCollide = false
            a8.Anchored = true
            a8.Transparency = _G.b44rpst
            a8.Color = _G.z01nxpw
            a8.Material = _G.m33vbtq

            if a8.Name == 'Head' and a8:FindFirstChild'face' then
                a8.face:Destroy()
            end
        end
    end

    a6.Parent = _G.v92mznw

    local a7 = TweenInfo.new(_G.j19dmxz, Enum.EasingStyle.Sine, Enum.EasingDirection.Out)

    for a8, a9 in q(a6:GetChildren())do
        if a9:IsA'BasePart' then
            _G.p01lxzq:Create(a9, a7, {Transparency = 1}):Play()
        end
    end

    task.delay(_G.j19dmxz, function()
        if a6 then
            a6:Destroy()
        end
    end)
end)
getgenv().crosshair = {
    enabled = false,
    refreshrate = 0,
    mode = 'mouse',
    position = Vector2.new(0, 0),
    width = 1.5,
    length = 10,
    radius = 11,
    color = Color3.fromRGB(255, 136, 0),
    spin = true,
    spin_speed = 150,
    spin_max = 340,
    spin_style = Enum.EasingStyle.Sine,
}

local a4 = N:section{
    name = 'crosshair',
    side = 'right',
}
local a5 = N:section{
    name = 'fps overlay',
    side = 'right',
}
local a6 = game:GetService'RunService'
local a7 = game:GetService'UserInputService'
local a8 = game:GetService'TweenService'
local a9 = workspace.CurrentCamera
local ba = Drawing.new'Text'

ba.Size = 13
ba.Font = 2
ba.Outline = true
ba.Text = 'Sample'
ba.Color = Color3.new(1, 1, 1)

local bb = Drawing.new'Text'

bb.Size = 13
bb.Font = 2
bb.Outline = true
bb.Text = '.hit'

local bc = {}

for bd = 1, 8 do
    bc[bd] = Drawing.new'Line'
end

local bd = 0
local be = {
    0,
    90,
    180,
    270,
}

local function bf(bg, bh)
    local bi = math.rad(bg)

    return Vector2.new(math.sin(bi) * bh, math.cos(bi) * bh)
end

a6.PostSimulation:Connect(function()
    local bg = os.clock()

    if bg - bd < getgenv().crosshair.refreshrate then
        return
    end

    bd = bg

    local bh = getgenv().crosshair
    local bi = bh.mode == 'center' and a9.ViewportSize / 2 or bh.mode == 'mouse' and a7:GetMouseLocation() or bh.position
    local bj = bh.enabled

    ba.Visible = bj
    bb.Visible = bj

    if not bj then
        for bk = 1, 8 do
            bc[bk].Visible = false
        end

        return
    end

    local bk = bh.radius + bh.length + 15
    local bl = bi + Vector2.new(-(ba.TextBounds.X + bb.TextBounds.X) / 2, bk)

    ba.Position = bl
    bb.Position = bl + Vector2.new(ba.TextBounds.X)
    bb.Color = bh.color

    local bm = 0

    if bh.spin then
        local bn = -(bg * bh.spin_speed) % bh.spin_max

        bm = a8:GetValue(bn / 360, bh.spin_style, Enum.EasingDirection.InOut) * 360
    end

    for bn = 1, 4 do
        local bo = be[bn] + bm
        local bp = bi + bf(bo, bh.radius)
        local bq = bi + bf(bo, bh.radius + bh.length)
        local br = bc[bn + 4]

        br.Visible = true
        br.Color = bh.color
        br.From = bp
        br.To = bq
        br.Thickness = bh.width

        local bs = bc[bn]

        bs.Visible = true
        bs.Color = Color3.new(0, 0, 0)
        bs.From = bi + bf(bo, bh.radius - 1)
        bs.To = bi + bf(bo, (bh.radius + bh.length) + 1)
        bs.Thickness = bh.width + 1.5
    end
end)
a4:toggle{
    name = 'crosshair',
    flag = 'crosshaireeee',
    default = false,
    callback = function(bg)
        getgenv().crosshair.enabled = bg
    end,
}
a4:colorpicker{
    name = 'accent color',
    flag = 'crosshair_color',
    color = getgenv().crosshair.color,
    callback = function(bg)
        getgenv().crosshair.color = bg
    end,
}
a4:slider{
    name = 'spin speed',
    flag = 'crosshair_spin',
    default = getgenv().crosshair.spin_speed,
    min = 0,
    max = 340,
    interval = 1,
    callback = function(bg)
        getgenv().crosshair.spin_speed = bg
    end,
}

_G.FPSDrawing = Drawing.new'Text'
_G.FPSDrawing.Visible = false
_G.FPSDrawing.Size = 18
_G.FPSDrawing.Font = 2
_G.FPSDrawing.Color = Color3.fromRGB(255, 136, 0)
_G.FPSDrawing.Outline = true
_G.FPSDrawing.OutlineColor = Color3.fromRGB(0, 0, 0)
_G.FPSDrawing.Transparency = 1
_G.FPSDrawing.Position = Vector2.new(16, 417)
_G.FPSDrawing.Text = 'FPS: 000'
_G.FPSCount = 0
_G.FPSLast = n()
_G.FPSConnection = game:GetService'RunService'.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
    _G.FPSCount = _G.FPSCount + 1

    local bg = n()

    if bg - _G.FPSLast >= 0.5 then
        local bh = math.floor(_G.FPSCount / (bg - _G.FPSLast) + 0.5)

        _G.FPSDrawing.Text = 'FPS: ' .. string.format('%03d', bh)
        _G.FPSCount = 0
        _G.FPSLast = bg
    end
end))

a5:toggle{
    name = 'fps overlay',
    flag = 'fps_enabled',
    default = false,
    callback = function(bg)
        _G.FPSDrawing.Visible = bg
    end,
}
a5:colorpicker{
    name = 'fps color',
    flag = 'fps_color',
    color = Color3.fromRGB(255, 136, 0),
    callback = function(bg)
        _G.FPSDrawing.Color = bg
    end,
}
a5:slider{
    name = 'position x',
    flag = 'fps_x',
    default = 16,
    min = 0,
    max = 2000,
    interval = 1,
    callback = function(bg)
        _G.FPSDrawing.Position = Vector2.new(bg, _G.FPSDrawing.Position.Y)
    end,
}
a5:slider{
    name = 'position y',
    flag = 'fps_y',
    default = 417,
    min = 0,
    max = 2000,
    interval = 1,
    callback = function(bg)
        _G.FPSDrawing.Position = Vector2.new(_G.FPSDrawing.Position.X, bg)
    end,
}

getgenv().player = U
getgenv().forcefield = nil
getgenv().AuraFFEnabled = false
getgenv().createFF = function()
    if getgenv().player.Character and not getgenv().forcefield then
        getgenv().forcefield = Instance.new'ForceField'
        getgenv().forcefield.Visible = true
        getgenv().forcefield.Parent = getgenv().player.Character
    end
end
getgenv().removeFF = function()
    if getgenv().forcefield then
        getgenv().forcefield:Destroy()

        getgenv().forcefield = nil
    end
end
_G.KorbloxEnabled = false
_G.KorbloxAccessoryID = 18457575895
_G.ApplyKorblox = function(bg)
    if not _G.KorbloxEnabled or not bg then
        return
    end

    pcall(function()
        local bh = {
            'RightUpperLeg',
            'RightLowerLeg',
            'RightFoot',
        }

        for bi, bj in r(bh)do
            if bg:FindFirstChild(bj) then
                bg[bj].Transparency = 1
            end
        end

        local bi = game:GetObjects('rbxassetid://' .. _G.KorbloxAccessoryID)
        local bj = bi and bi[1]

        if bj and bg:FindFirstChild'RightUpperLeg' then
            bj.Parent = bg

            local bk = bj:FindFirstChild'Handle'

            if bk then
                bk.CFrame = bg.RightUpperLeg.CFrame

                local bl = Instance.new('Weld', bk)

                bl.Part0 = bk
                bl.Part1 = bg.RightUpperLeg
                bl.C0 = CFrame.new(0, -0.12, 0)
            end
        end
    end)
end
_G.RemoveKorblox = function(bg)
    if not bg then
        return
    end

    local bh = {
        'RightUpperLeg',
        'RightLowerLeg',
        'RightFoot',
    }

    for bi, bj in r(bh)do
        if bg:FindFirstChild(bj) then
            bg[bj].Transparency = 0
        end
    end
    for bi, bj in q(bg:GetChildren())do
        if bj:IsA'Accessory' and bj:FindFirstChild'Handle' then
            local bk = bj.Handle
            local bl = bk:FindFirstChildWhichIsA'SpecialMesh'

            if bl and (bl.MeshId:match'18457575888') then
                bj:Destroy()
            end
        end
    end
end
_G.HeadlessEnabled = false
_G.HeadlessLoop = function()
    if not _G.HeadlessEnabled then
        return
    end

    local bg = U.Character

    if bg and bg:FindFirstChild'Head' then
        bg.Head.Transparency = 1

        if bg.Head:FindFirstChild'face' then
            bg.Head.face.Transparency = 1
        end
    end
end

local bg = N:section{
    name = 'self visuals',
    side = 'right',
}

_G.aurp = _G.aurp or {}
_G.aurasst = {
    starlight = game:GetObjects'rbxassetid://134645216613107'[1],
    heavenly = game:GetObjects'rbxassetid://139300897520961'[1],
    ribbon = game:GetObjects'rbxassetid://132069507632161'[1],
    sakura = game:GetObjects'rbxassetid://81755778619404'[1],
    angel = game:GetObjects'rbxassetid://97658130917593'[1],
    wind = game:GetObjects'rbxassetid://80694081850877'[1],
    flow = game:GetObjects'rbxassetid://119913533725648'[1],
    star = game:GetObjects'rbxassetid://73754563740680'[1],
}
_G.updaurcol = LPH_NO_VIRTUALIZE(function()
    local bh = _G.aurcolwtff or Color3.fromRGB(255, 94, 0)
    local bi = ColorSequence.new(bh)

    for bj = 1, #_G.aurp do
        local bk = _G.aurp[bj]

        if bk then
            if bk:IsA'ParticleEmitter' or bk:IsA'Trail' or bk:IsA'Beam' then
                bk.Color = bi
            elseif bk:IsA'PointLight' then
                bk.Color = bh
            end

            local bl = bk:GetDescendants()

            for bm = 1, #bl do
                local bn = bl[bm]

                if bn:IsA'ParticleEmitter' or bn:IsA'Trail' or bn:IsA'Beam' then
                    bn.Color = bi
                elseif bn:IsA'PointLight' then
                    bn.Color = bh
                end
            end
        end
    end
end)
_G.clraur = function()
    for bh = 1, #_G.aurp do
        local bi = _G.aurp[bh]

        if bi then
            bi:Destroy()
        end
    end

    table.clear(_G.aurp)
end
_G.applaur = LPH_NO_VIRTUALIZE(function()
    _G.clraur()

    if not _G.aurenabwtff then
        return
    end

    local bh = game.Players.LocalPlayer.Character
    local bi = _G.aurasst[_G.selaurwtff or 'angel']

    if bh and bi then
        local bj = bi:Clone()
        local bk = bj:GetChildren()

        for bl = 1, #bk do
            local bm = bk[bl]
            local bn = bh:FindFirstChild(bm.Name)

            if bn then
                local bo = bm:GetChildren()

                for bp = 1, #bo do
                    local bq = bo[bp]

                    bq.Name = '\0'
                    bq.Parent = bn

                    table.insert(_G.aurp, bq)
                end
            end
        end

        bj:Destroy()
        _G.updaurcol()
    end
end)

bg:toggle{
    name = 'apply aura',
    flag = 'GRSB_FSGS_B_DS_DBEIUWHHUVCNBNB)',
    default = false,
    callback = function(bh)
        _G.aurenabwtff = bh

        if bh then
            _G.applaur()

            if not _G.aurconwtff then
                _G.aurconwtff = game.Players.LocalPlayer.CharacterAdded:Connect(function()
                    task.wait(1)

                    if _G.aurenabwtff then
                        _G.applaur()
                    end
                end)
            end
        else
            _G.clraur()
        end
    end,
}
bg:colorpicker{
    flag = 'dfgbdsfiuhuidfhiudfhjgidfoshgipsdhfgipufvdhsiudfhiu',
    color = Color3.fromRGB(255, 94, 0),
    callback = function(bh)
        _G.aurcolwtff = bh

        _G.updaurcol()
    end,
}
bg:dropdown{
    name = 'aura type',
    flag = 'shootsound_f',
    items = {
        'starlight',
        'heavenly',
        'ribbon',
        'sakura',
        'angel',
        'wind',
        'flow',
        'star',
    },
    default = 'angel',
    multi = false,
    callback = function(bh)
        _G.selaurwtff = bh

        if _G.aurenabwtff then
            _G.applaur()
        end
    end,
}

_G.ff_c = Color3.fromRGB(255, 94, 0)
_G.ff_en = false
_G.tff_c = Color3.fromRGB(255, 94, 0)
_G.tff_en = false

local function bh(bi, bj, bk)
    local bl = bi:GetDescendants()

    for bm = 1, #bl do
        local bn = bl[bm]

        if bn:IsA'BasePart' and not bn:FindFirstAncestorOfClass'Tool' then
            if bk then
                if bn.Material ~= Enum.Material.ForceField then
                    bn.Material = Enum.Material.ForceField
                    bn.Color = bj
                end
            else
                bn.Material = Enum.Material.Plastic
            end
        end
    end
end
local function bi(bj, bk, bl)
    local bm = bj:GetChildren()

    for bn = 1, #bm do
        local bo = bm[bn]

        if bo:IsA'Tool' then
            local bp = bo:GetDescendants()

            for bq = 1, #bp do
                local br = bp[bq]

                if br:IsA'BasePart' then
                    if bl then
                        if br.Material ~= Enum.Material.ForceField then
                            br.Material = Enum.Material.ForceField
                            br.Color = bk
                        end
                    else
                        br.Material = Enum.Material.Plastic
                    end
                end
            end
        end
    end
end

game:GetService'RunService'.RenderStepped:Connect(LPH_NO_VIRTUALIZE(function()
    if not (_G.ff_en or _G.tff_en) then
        return
    end

    local bj = game.Players.LocalPlayer.Character

    if not bj then
        return
    end
    if _G.ff_en then
        bh(bj, _G.ff_c, true)
    end
    if _G.tff_en then
        bi(bj, _G.tff_c, true)
    end
end))
bg:toggle{
    name = 'character forcefield',
    flag = 'chcccvv_enabled',
    default = false,
    callback = function(bj)
        _G.ff_en = bj

        if not bj and game.Players.LocalPlayer.Character then
            bh(game.Players.LocalPlayer.Character, Color3.new(1, 1, 1), false)
        end
    end,
}
bg:colorpicker{
    flag = 'dfgbdsfiuhufvdhsiudfhiu',
    color = Color3.fromRGB(255, 94, 0),
    callback = function(bj)
        _G.ff_c = (t(bj) == 'table') and Color3.new(bj.R or bj[1], bj.G or bj[2], bj.B or bj[3]) or bj
    end,
}
bg:toggle{
    name = 'tools forcefield',
    flag = 'tool_ff_enabled',
    default = false,
    callback = function(bj)
        _G.tff_en = bj

        if not bj and game.Players.LocalPlayer.Character then
            bi(game.Players.LocalPlayer.Character, Color3.new(1, 1, 1), false)
        end
    end,
}
bg:colorpicker{
    flag = 'dfgbdsfiiudfhiu',
    color = Color3.fromRGB(255, 94, 0),
    callback = function(bj)
        _G.tff_c = (t(bj) == 'table') and Color3.new(bj.R or bj[1], bj.G or bj[2], bj.B or bj[3]) or bj
    end,
}
bg:toggle{
    name = 'fake roblox forcefield',
    flag = 'aurafff_toggle',
    default = false,
    callback = function(bj)
        getgenv().AuraFFEnabled = bj

        if bj then
            getgenv().createFF()
        else
            getgenv().removeFF()
        end
    end,
}
bg:toggle{
    name = 'korblox',
    flag = 'korblox_toggle',
    default = false,
    callback = function(bj)
        _G.KorbloxEnabled = bj

        if bj then
            _G.ApplyKorblox(U.Character)
        else
            _G.RemoveKorblox(U.Character)
        end
    end,
}
bg:toggle{
    name = 'headless',
    flag = 'headless_toggle',
    default = false,
    callback = function(bj)
        _G.HeadlessEnabled = bj

        if bj then
            T:BindToRenderStep('HeadlessLoop', 201, _G.HeadlessLoop)
        else
            T:UnbindFromRenderStep'HeadlessLoop'

            if U.Character and U.Character:FindFirstChild'Head' then
                U.Character.Head.Transparency = 0

                if U.Character.Head:FindFirstChild'face' then
                    U.Character.Head.face.Transparency = 0
                end
            end
        end
    end,
}
U.CharacterAdded:Connect(function(bj)
    task.wait(1)

    if _G.KorbloxEnabled then
        _G.ApplyKorblox(bj)
    end
    if getgenv().AuraFFEnabled then
        getgenv().createFF()
    end
end)

_G.ShootSoundOverride = _G.ShootSoundOverride or false
_G.SelectedShootSound = _G.SelectedShootSound or 'Default'
_G.ShootSoundVolume = _G.ShootSoundVolume or 2
_G.ShootSoundPitch = _G.ShootSoundPitch or 1
_G.SHOOT_SOUNDS_DATA = {
    Default = '',
    ['Rust HS'] = 'rbxassetid://5043539486',
    Neverlose = 'rbxassetid://97643101798871',
    ['Minecraft Bow'] = 'rbxassetid://3442683707',
    Skeet = 'https://raw.githubusercontent.com/f1nobe7650/Nebula/refs/heads/main/Sounds/Skeet.mp3',
    Bathit = 'https://raw.githubusercontent.com/f1nobe7650/Nebula/refs/heads/main/Sounds/BatHit.mp3',
    Oblivity = 'https://cdn.getsample.lol/uz1lp3e6',
}
_G.OriginalSoundData = _G.OriginalSoundData or {}
_G.CachedAssets = _G.CachedAssets or {}
_G.getAsset_hdsy = function(bj, bk)
    if not bk or bk == '' then
        return ''
    end
    if not bk:find'http' then
        return bk
    end
    if _G.CachedAssets[bj] then
        return _G.CachedAssets[bj]
    end

    local bl = bj .. '.mp3'

    if not isfile(bl) then
        local bm, bn = pcall(function()
            return game:HttpGet(bk, true)
        end)

        if bm then
            writefile(bl, bn)
        end
    end

    local bm
    local bn, bo = pcall(function()
        return getsynasset(bl)
    end)

    if bn then
        bm = bo
    else
        local bp, bq = pcall(function()
            return getcustomasset(bl)
        end)

        if bp then
            bm = bq
        end
    end

    _G.CachedAssets[bj] = bm

    return bm
end
_G.reOverrideTool_hdsy = function(bj)
    if not bj or not _G.ShootSoundOverride or _G.SelectedShootSound == 'Default' then
        return
    end

    local bk = _G.SHOOT_SOUNDS_DATA[_G.SelectedShootSound]
    local bl = _G.getAsset_hdsy(_G.SelectedShootSound, bk)

    if bl == '' then
        return
    end

    local bm = bl
    local bn = _G.ShootSoundVolume * 10
    local bo = _G.ShootSoundPitch

    for bp, bq in q(bj:GetDescendants())do
        local br = bq.Name

        if bq:IsA'Sound' and (br:lower():find'shoot' or br == 'ShootSound' or br == 'Fire' or br == 'Gunshot') then
            if not _G.OriginalSoundData[bq] then
                _G.OriginalSoundData[bq] = {
                    SoundId = bq.SoundId,
                    Volume = bq.Volume,
                    PlaybackSpeed = bq.PlaybackSpeed,
                }
            end

            bq.SoundId = bm
            bq.Volume = bn
            bq.PlaybackSpeed = bo
        end
    end
end
_G.overrideShootSounds_hdsy = function()
    local bj = {
        U:FindFirstChild'Backpack',
        U.Character,
    }

    for bk, bl in q(bj)do
        if not bl then
            continue
        end

        for bm, bn in q(bl:GetChildren())do
            if bn:IsA'Tool' then
                _G.reOverrideTool_hdsy(bn)
            end
        end
    end
end
_G.restoreAllShootSounds_hdsy = function()
    for bj, bk in r(_G.OriginalSoundData)do
        if bj and bj.Parent then
            bj.SoundId = bk.SoundId
            bj.Volume = bk.Volume
            bj.PlaybackSpeed = bk.PlaybackSpeed
        end
    end

    _G.OriginalSoundData = {}
end
_G.soundSection = N:section{
    name = 'custom shoot sounds',
    side = 'right',
}

_G.soundSection:toggle{
    name = 'enabled',
    flag = 'shootsound_enabled',
    default = _G.ShootSoundOverride,
    callback = function(bj)
        _G.ShootSoundOverride = bj

        if bj then
            _G.overrideShootSounds_hdsy()
        else
            _G.restoreAllShootSounds_hdsy()
        end
    end,
}
_G.soundSection:dropdown{
    name = 'sound selection',
    flag = 'shootsound_val',
    items = {
        'Default',
        'Rust HS',
        'Neverlose',
        'Minecraft Bow',
        'Oblivity',
        'Skeet',
        'Bathit',
    },
    default = _G.SelectedShootSound,
    multi = false,
    callback = function(bj)
        _G.SelectedShootSound = bj

        if _G.ShootSoundOverride then
            _G.overrideShootSounds_hdsy()
        end
    end,
}
_G.soundSection:slider{
    name = 'volume booster',
    flag = 'shootsound_vol',
    min = 0,
    max = 10,
    default = _G.ShootSoundVolume,
    interval = 0.1,
    callback = function(bj)
        _G.ShootSoundVolume = bj

        if _G.ShootSoundOverride then
            _G.overrideShootSounds_hdsy()
        end
    end,
}
_G.soundSection:slider{
    name = 'sound pitch',
    flag = 'shootsound_ptc',
    min = 0,
    max = 10,
    default = _G.ShootSoundPitch,
    interval = 0.1,
    callback = function(bj)
        _G.ShootSoundPitch = bj

        if _G.ShootSoundOverride then
            _G.overrideShootSounds_hdsy()
        end
    end,
}
task.spawn(function()
    while task.wait(2) do
        if _G.ShootSoundOverride then
            _G.overrideShootSounds_hdsy()
        end
    end
end)

_G.skyboxes = {
    Sunset = {
        SkyboxBk = 'http://www.roblox.com/asset/?id=458016711',
        SkyboxDn = 'http://www.roblox.com/asset/?id=458016826',
        SkyboxFt = 'http://www.roblox.com/asset/?id=458016532',
        SkyboxLf = 'http://www.roblox.com/asset/?id=458016655',
        SkyboxRt = 'http://www.roblox.com/asset/?id=458016782',
        SkyboxUp = 'http://www.roblox.com/asset/?id=458016792',
    },
    ['Night Sky 1'] = {
        SkyboxBk = 'rbxassetid://48020371',
        SkyboxDn = 'rbxassetid://48020144',
        SkyboxFt = 'rbxassetid://48020234',
        SkyboxLf = 'rbxassetid://48020211',
        SkyboxRt = 'rbxassetid://48020254',
        SkyboxUp = 'rbxassetid://48020383',
    },
    Minecraft = {
        SkyboxBk = 'rbxassetid://1876545003',
        SkyboxDn = 'rbxassetid://1876544331',
        SkyboxFt = 'rbxassetid://1876542941',
        SkyboxLf = 'rbxassetid://1876543392',
        SkyboxRt = 'rbxassetid://1876543764',
        SkyboxUp = 'rbxassetid://1876544642',
    },
    Evening = {
        SkyboxLf = 'http://www.roblox.com/asset/?id=7950573918',
        SkyboxBk = 'http://www.roblox.com/asset/?id=7950569153',
        SkyboxDn = 'http://www.roblox.com/asset/?id=7950570785',
        SkyboxFt = 'http://www.roblox.com/asset/?id=7950572449',
        SkyboxRt = 'http://www.roblox.com/asset/?id=7950575055',
        SkyboxUp = 'http://www.roblox.com/asset/?id=7950627627',
    },
    ['Purple Nebula'] = {
        SkyboxBk = 'rbxassetid://159454299',
        SkyboxDn = 'rbxassetid://159454296',
        SkyboxFt = 'rbxassetid://159454293',
        SkyboxLf = 'rbxassetid://159454286',
        SkyboxRt = 'rbxassetid://159454300',
        SkyboxUp = 'rbxassetid://159454288',
    },
    ['Night Sky 2'] = {
        SkyboxBk = 'rbxassetid://12064107',
        SkyboxDn = 'rbxassetid://12064152',
        SkyboxFt = 'rbxassetid://12064121',
        SkyboxLf = 'rbxassetid://12063984',
        SkyboxRt = 'rbxassetid://12064115',
        SkyboxUp = 'rbxassetid://12064131',
    },
    ['Pink Daylight'] = {
        SkyboxBk = 'rbxassetid://271042516',
        SkyboxDn = 'rbxassetid://271077243',
        SkyboxFt = 'rbxassetid://271042556',
        SkyboxLf = 'rbxassetid://271042310',
        SkyboxRt = 'rbxassetid://271042467',
        SkyboxUp = 'rbxassetid://271077958',
    },
    ['Morning Glow'] = {
        SkyboxBk = 'rbxassetid://1417494030',
        SkyboxDn = 'rbxassetid://1417494146',
        SkyboxFt = 'rbxassetid://1417494253',
        SkyboxLf = 'rbxassetid://1417494402',
        SkyboxRt = 'rbxassetid://1417494499',
        SkyboxUp = 'rbxassetid://1417494643',
    },
    Chill = {
        SkyboxBk = 'rbxassetid://5084575798',
        SkyboxDn = 'rbxassetid://5084575916',
        SkyboxFt = 'rbxassetid://5103949679',
        SkyboxLf = 'rbxassetid://5103948542',
        SkyboxRt = 'rbxassetid://5103948784',
        SkyboxUp = 'rbxassetid://5084576400',
    },
    ['Setting Sun'] = {
        SkyboxBk = 'rbxassetid://626460377',
        SkyboxDn = 'rbxassetid://626460216',
        SkyboxFt = 'rbxassetid://626460513',
        SkyboxLf = 'rbxassetid://626473032',
        SkyboxRt = 'rbxassetid://626458639',
        SkyboxUp = 'rbxassetid://626460625',
    },
    ['Fade Blue'] = {
        SkyboxBk = 'rbxassetid://153695414',
        SkyboxDn = 'rbxassetid://153695352',
        SkyboxFt = 'rbxassetid://153695452',
        SkyboxLf = 'rbxassetid://153695320',
        SkyboxRt = 'rbxassetid://153695383',
        SkyboxUp = 'rbxassetid://153695471',
    },
    Twilight = {
        SkyboxBk = 'rbxassetid://264908339',
        SkyboxDn = 'rbxassetid://264907909',
        SkyboxFt = 'rbxassetid://264909420',
        SkyboxLf = 'rbxassetid://264909758',
        SkyboxRt = 'rbxassetid://264908886',
        SkyboxUp = 'rbxassetid://264907379',
    },
    ['Elegant Morning'] = {
        SkyboxBk = 'rbxassetid://153767241',
        SkyboxDn = 'rbxassetid://153767216',
        SkyboxFt = 'rbxassetid://153767266',
        SkyboxLf = 'rbxassetid://153767200',
        SkyboxRt = 'rbxassetid://153767231',
        SkyboxUp = 'rbxassetid://153767288',
    },
    Neptune = {
        SkyboxBk = 'rbxassetid://218955819',
        SkyboxDn = 'rbxassetid://218953419',
        SkyboxFt = 'rbxassetid://218954524',
        SkyboxLf = 'rbxassetid://218958493',
        SkyboxRt = 'rbxassetid://218957134',
        SkyboxUp = 'rbxassetid://218950090',
    },
    Redshift = {
        SkyboxBk = 'rbxassetid://401664839',
        SkyboxDn = 'rbxassetid://401664862',
        SkyboxFt = 'rbxassetid://401664960',
        SkyboxLf = 'rbxassetid://401664881',
        SkyboxRt = 'rbxassetid://401664901',
        SkyboxUp = 'rbxassetid://401664936',
    },
    ['Realistic Desert'] = {
        SkyboxBk = 'rbxassetid://161319957',
        SkyboxDn = 'rbxassetid://161319965',
        SkyboxFt = 'rbxassetid://161319970',
        SkyboxLf = 'rbxassetid://161319983',
        SkyboxRt = 'rbxassetid://161319989',
        SkyboxUp = 'rbxassetid://161319996',
    },
    ['Aesthetic Night'] = {
        SkyboxBk = 'rbxassetid://1045964490',
        SkyboxDn = 'rbxassetid://1045964368',
        SkyboxFt = 'rbxassetid://1045964655',
        SkyboxLf = 'rbxassetid://1045964655',
        SkyboxRt = 'rbxassetid://1045964655',
        SkyboxUp = 'rbxassetid://1045962969',
    },
}
_G.selected_skybox = 'Sunset'
_G.skybox_locked = false

local bj

local function bk()
    local bl = game.Lighting:FindFirstChildOfClass'Sky'

    if bl and not bj then
        bj = {
            Bk = bl.SkyboxBk,
            Dn = bl.SkyboxDn,
            Ft = bl.SkyboxFt,
            Lf = bl.SkyboxLf,
            Rt = bl.SkyboxRt,
            Up = bl.SkyboxUp,
        }
    end
end
local function bl()
    local bm = game.Lighting:FindFirstChildOfClass'Sky'

    if bm and bj then
        bm.SkyboxBk = bj.Bk
        bm.SkyboxDn = bj.Dn
        bm.SkyboxFt = bj.Ft
        bm.SkyboxLf = bj.Lf
        bm.SkyboxRt = bj.Rt
        bm.SkyboxUp = bj.Up
    end
end

local bm = LPH_NO_VIRTUALIZE(function()
    bk()

    local bm = game.Lighting:FindFirstChildOfClass'Sky'

    if not bm then
        bm = Instance.new'Sky'
        bm.Parent = game.Lighting
    end

    local bn = _G.skyboxes[_G.selected_skybox]

    if bn then
        if bm.SkyboxBk ~= bn.SkyboxBk then
            bm.SkyboxBk = bn.SkyboxBk
            bm.SkyboxDn = bn.SkyboxDn
            bm.SkyboxFt = bn.SkyboxFt
            bm.SkyboxLf = bn.SkyboxLf
            bm.SkyboxRt = bn.SkyboxRt
            bm.SkyboxUp = bn.SkyboxUp
        end
    end
end)
local bn = N:section{
    name = 'sky changer',
    side = 'right',
}

bn:toggle{
    name = 'enabled',
    flag = 'skybox_enabled',
    default = false,
    callback = function(bo)
        _G.skybox_locked = bo

        if bo then
            bm()
        else
            bl()
        end
    end,
}
bn:dropdown{
    name = 'selected skybox',
    flag = 'skybox_selection',
    items = {
        'Sunset',
        'Night Sky 1',
        'Evening',
        'Minecraft',
        'Realistic Desert',
        'Purple Nebula',
        'Night Sky 2',
        'Pink Daylight',
        'Morning Glow',
        'Chill',
        'Setting Sun',
        'Fade Blue',
        'Twilight',
        'Elegant Morning',
        'Neptune',
        'Redshift',
        'Aesthetic Night',
    },
    multi = false,
    callback = function(bo)
        _G.selected_skybox = bo

        if _G.skybox_locked then
            bm()
        end
    end,
}
game:GetService'RunService'.Heartbeat:Connect(LPH_NO_VIRTUALIZE(function()
    if _G.skybox_locked then
        local bo = game.Lighting:FindFirstChildOfClass'Sky'

        if not bo then
            bo = Instance.new'Sky'
            bo.Parent = game.Lighting
        end

        local bp = _G.skyboxes[_G.selected_skybox]

        if bp and bo.SkyboxBk ~= bp.SkyboxBk then
            bo.SkyboxBk = bp.SkyboxBk
            bo.SkyboxDn = bp.SkyboxDn
            bo.SkyboxFt = bp.SkyboxFt
            bo.SkyboxLf = bp.SkyboxLf
            bo.SkyboxRt = bp.SkyboxRt
            bo.SkyboxUp = bp.SkyboxUp
        end
    end
end))
game.Lighting.ChildRemoved:Connect(function(bo)
    if _G.skybox_locked and bo:IsA'Sky' then
        task.defer(bm)
    end
end)

_G.maingui_hdsy = U:WaitForChild'PlayerGui':WaitForChild'MainScreenGui'
_G.moneylabel_hdsy = _G.maingui_hdsy:WaitForChild'MoneyText'
_G.cashhhdjinsiub = _G.moneylabel_hdsy.Text
_G.colorhhdjinsiub = _G.moneylabel_hdsy.TextColor3
_G.valhhdjinsiub = '999999999'
_G.activehhdjinsiub = false
_G.cashspooof = N:section{
    name = 'cash spoofer',
    side = 'left',
}

_G.cashspooof:toggle{
    name = 'enabled',
    flag = 'cashspf_enabled',
    default = false,
    callback = function(bo)
        _G.activehhdjinsiub = bo

        if _G.activehhdjinsiub then
            _G.cashhhdjinsiub = _G.moneylabel_hdsy.Text
            _G.moneylabel_hdsy.Text = string.format('$%s', _G.valhhdjinsiub)
        else
            _G.moneylabel_hdsy.Text = _G.cashhhdjinsiub
            _G.moneylabel_hdsy.TextColor3 = _G.colorhhdjinsiub
        end
    end,
}
_G.cashspooof:textbox{
    name = 'ur text',
    flag = 'cashspf_custom_text',
    callback = function(bo)
        _G.valhhdjinsiub = bo

        if _G.activehhdjinsiub then
            _G.moneylabel_hdsy.Text = string.format('$%s', _G.valhhdjinsiub)
        end
    end,
}

_G.h88vbtz = N:section{
    name = 'hit chams',
    side = 'left',
}

_G.h88vbtz:toggle{
    name = 'enabled',
    flag = 'saifnjvm7wfeynwy79dfrfgfgfgggffgfgfg',
    default = false,
    callback = function(bo)
        _G.f28skdn = bo
    end,
}
_G.h88vbtz:colorpicker{
    flag = 'sdfogm8iej487r9tg',
    color = Color3.fromRGB(255, 0, 0),
    callback = function(bo)
        _G.z01nxpw = bo
    end,
}
_G.h88vbtz:slider{
    name = 'duration',
    flag = 'chgm_dur',
    default = 4.5,
    min = 1,
    max = 10,
    interval = 0.01,
    callback = function(bo)
        _G.j19dmxz = bo
    end,
}

_G.g44pwnd = _G.q19pnvz.Character or _G.q19pnvz.CharacterAdded:Wait()

_G.q19pnvz.CharacterAdded:Connect(function(bo)
    _G.g44pwnd = bo
end)

_G.Basescc = 40
_G.Nmbdsct = math.huge
_G.Popduration = 0.15
_G.Stayduration = 0.5
_G.Fadeduration = 0.4
_G.MaxOffset = 15
_G.DmgFont = Enum.Font.SourceSansBold
_G.IsEnabledDmg = _G.IsEnabledDmg or false
_G.DmgColor = Color3.fromRGB(255, 94, 0)
_G.PrevHealth = _G.PrevHealth or {}
_G.DoDmgDisplay = function(bo, bp)
    if not _G.IsEnabledDmg or bp <= 0 then
        return
    end

    local bq = (t(bo) == 'Instance' and bo:IsA'Player') and bo.Character or bo

    if not bq then
        return
    end

    local br = bq:FindFirstChild'Head'

    if not br then
        return
    end

    local bs = br:FindFirstChild'DamageContainer'

    if not bs then
        bs = Instance.new'BillboardGui'
        bs.Name = 'DamageContainer'
        bs.Parent = br
        bs.Adornee = br
        bs.Size = UDim2.new(0, 150, 0, 75)
        bs.StudsOffset = Vector3.new(0, 2, 0)
        bs.AlwaysOnTop = true
        bs.MaxDistance = _G.Nmbdsct
    end

    local bt = Instance.new'TextLabel'

    bt.Parent = bs
    bt.Text = '-' .. tostring(bp)
    bt.TextColor3 = _G.DmgColor
    bt.TextSize = _G.Basescc + math.clamp((bp / 5), 0, 20)
    bt.Font = _G.DmgFont
    bt.BackgroundTransparency = 1
    bt.Size = UDim2.new(1, 0, 0, _G.Basescc)
    bt.TextStrokeTransparency = 0
    bt.AnchorPoint = Vector2.new(0.5, 0.5)
    bt.Position = UDim2.new(0.5, math.random(-_G.MaxOffset, _G.MaxOffset), 0.5, math.random(-_G.MaxOffset, _G.MaxOffset))
    bt.Rotation = math.random(-15, 15)

    local bu = Instance.new'UIScale'

    bu.Scale = 0
    bu.Parent = bt

    local bv = game:GetService'TweenService':Create(bu, TweenInfo.new(_G.Popduration, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1})
    local bw = game:GetService'TweenService':Create(bt, TweenInfo.new(_G.Fadeduration, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
        TextTransparency = 1,
        TextStrokeTransparency = 1,
    })

    bv:Play()
    bv.Completed:Connect(function()
        task.wait(_G.Stayduration)
        bw:Play()
        bw.Completed:Connect(function()
            bt:Destroy()
        end)
    end)
end

local function bo(bp, bq)
    local br = bq:WaitForChild('Humanoid', 5)

    if br then
        _G.PrevHealth[bp.UserId] = br.Health

        br.HealthChanged:Connect(function(bs)
            local bt = _G.PrevHealth[bp.UserId] or br.MaxHealth

            if bs < bt then
                local bu = math.floor(bt - bs)

                if bu > 0 then
                    _G.DoDmgDisplay(bp, bu)
                end
            end

            _G.PrevHealth[bp.UserId] = bs
        end)
    end
end

for bp, bq in q(game:GetService'Players':GetPlayers())do
    if bq ~= game:GetService'Players'.LocalPlayer then
        if bq.Character then
            bo(bq, bq.Character)
        end

        bq.CharacterAdded:Connect(function(br)
            bo(bq, br)
        end)
    end
end

game:GetService'Players'.PlayerAdded:Connect(function(bp)
    bp.CharacterAdded:Connect(function(bq)
        bo(bp, bq)
    end)
end)

_G.v122 = N:section{
    name = 'damage numbers',
    side = 'left',
}

_G.v122:toggle{
    name = 'enabled',
    flag = 'sdmgnmbtgggltt',
    default = false,
    callback = function(bp)
        _G.IsEnabledDmg = bp
    end,
}
_G.v122:colorpicker{
    flag = 'dmgnmbgggggg',
    color = Color3.fromRGB(255, 94, 0),
    callback = function(bp)
        _G.DmgColor = bp
    end,
}

if _G.v92mznw:FindFirstChild'Ignored' and _G.v92mznw.Ignored:FindFirstChild'Siren' and _G.v92mznw.Ignored.Siren:FindFirstChild'Radius' then
    _G.v92mznw.Ignored.Siren.Radius.ChildAdded:Connect(function(bp)
        if bp.Name ~= 'BULLET_RAYS' then
            return
        end
        if not bp:GetAttribute'OwnerCharacter' or bp:GetAttribute'OwnerCharacter' ~= _G.g44pwnd.Name then
            return
        end

        task.spawn(function()
            if not bp.Parent then
                return
            end

            _G.y01mxpw = bp.Position
            _G.k92lvnc = bp.CFrame.LookVector
            _G.o00plqm = RaycastParams.new()
            _G.o00plqm.FilterDescendantsInstances = {
                _G.g44pwnd,
                _G.v92mznw.Ignored,
            }
            _G.o00plqm.FilterType = Enum.RaycastFilterType.Exclude
            _G.i11ncmz = _G.v92mznw:Raycast(_G.y01mxpw, _G.k92lvnc * 1000, _G.o00plqm)

            if _G.i11ncmz and _G.i11ncmz.Instance then
                _G.r33kspq = _G.i11ncmz.Instance
                _G.p77vbtz = _G.i11ncmz.Position
                _G.m00lskd = _G.r33kspq:FindFirstAncestorWhichIsA'Model'

                if _G.m00lskd and _G.m00lskd:FindFirstChild'Humanoid' then
                    local bq = game:GetService'Players':GetPlayerFromCharacter(_G.m00lskd)

                    if bq and bq ~= game:GetService'Players'.LocalPlayer then
                        _G.u77vmsq(_G.m00lskd)

                        if _G.hit_effect_enabled and _G.d8ufjwye and _G.d8ufjwye[_G.selected_hit_effect] then
                            _G.d8ufjwye[_G.selected_hit_effect](_G.p77vbtz)
                        end
                    end
                end
            end
        end)
    end)
end

local bp = L:section{
    name = 'target',
    side = 'right',
}
local bq = L:section{
    name = 'settings',
    side = 'left',
}
local br = L:section{
    name = 'misc',
    side = 'right',
}
local bs = L:section{
    name = 'resolver',
    side = 'left',
}
local bt = L:section{
    name = 'connection exploit',
    side = 'right',
}
local bu = L:section{
    name = 'void hide',
    side = 'left',
}
local bv = {
    main_event = R:WaitForChild'MainEvent',
    global_table = _G or {},
    nymus = nymus or {},
    target = {
        auto_kill = false,
        prediction_enabled = false,
        prediction_amount = 0.25462,
        target = nil,
        auto_kill_desync = false,
    },
    sentry = {
        safe_mode = false,
        last_pos = nil,
    },
    exploit_resolver = {
        exploitresolverat = {},
        scriptt = {},
        dataaa = {
            last_positions = {},
            last_timesssss = {},
        },
    },
    art_data = {
        position_log = {},
        last_refresh = 0,
        found_pattern = nil,
    },
    fake_pos_resolver_enabled = false,
    glue_resolver_enabled = false,
    current_real_pos = nil,
    prediction_breaker_enabled = false,
    strafe_offset = 25.73971,
    saved_cframe = nil,
    stomp_offset_value = 3,
    played_knock_effect_for = {},
    notif_cache = {},
    played_knock_sound_for = {},
}
local bw = bv.main_event
local bx = bv.global_table
local by = bv.nymus
local bz = bv.art_data
local bA = bv.strafe_offset
local bB = bv.saved_cframe
local bC = bv.stomp_offset_value

by.Target = bv.target
by.Sentry = bv.sentry
bx.exploitresolverat = bv.exploit_resolver
bx.exploitresolverat.scriptt = bv.exploit_resolver.scriptt
bx.exploitresolverat.scriptt.dataaa = bv.exploit_resolver.dataaa
bx.PlayedKnockEffectFor = bv.played_knock_effect_for
bx.notifakcache = bv.notif_cache
bx.PlayedKnockSoundFor = bv.played_knock_sound_for
getgenv().FakePosResolverEnabled = bv.fake_pos_resolver_enabled
getgenv().GlueResolverEnabled = bv.glue_resolver_enabled
getgenv().CurrentRealPos = bv.current_real_pos
getgenv().predictionBreakerEnabled = bv.prediction_breaker_enabled

local bD = {}

bD.shoot_target = LPH_JIT_MAX(function(bE, Z, _)
    if not _ or not _:FindFirstChild'Handle' then
        return
    end

    bw:FireServer('ShootGun', _.Handle, _.Handle.Position, bE, Z, Vector3.new(0, 1, 0))
end)
bD.reload_weapon = LPH_JIT_MAX(function(bE)
    if bE then
        bw:FireServer('Reload', bE)
    end
end)
bD.get_target_state = LPH_JIT_MAX(function(bE)
    if not bE or not bE.Character then
        return 'invalid'
    end

    local Z = bE.Character:FindFirstChild'BodyEffects'

    if Z then
        local _ = Z:FindFirstChild'K.O' or Z:FindFirstChild'KO'
        local bF = Z:FindFirstChild'SDeath'

        if _ and _.Value then
            return (bF and bF.Value) and 'dead' or 'knocked'
        end
    end
    if bE.Character:FindFirstChild'ForceField' then
        return 'forcefield'
    end

    return 'targeting'
end)
bD.handle_shooting = LPH_JIT_MAX(function(bE, bF, Z, _, bG)
    local bH = game.Players.LocalPlayer.Character

    if not bH then
        return
    end

    local bI = _ and bG or {
        bH:FindFirstChildOfClass'Tool',
    }

    for bJ, bK in q(bI)do
        if bK and bK:IsA'Tool' and bK.Parent == bH then
            local bL = bK:FindFirstChild'Ammo'

            if (bK.Name == '[Flintlock]' and bL and bL.Value == 0) or (bL and bL.Value <= 0) then
                bD.reload_weapon(bK)
            else
                bD.shoot_target(bF, Z, bK)

                if bL and bL.Value > 0 and bL.Value <= 3 then
                    task.spawn(function()
                        task.wait(0.1)
                        bD.reload_weapon(bK)
                    end)
                end
            end
        end
    end
end)

do
    local function bE()
        return function(bF)
            bx.hitDetection_ragebot = {}

            local bG = game:GetService'ReplicatedStorage'
            local bH = game:GetService'Stats'
            local bI = game:GetService'Players'
            local bJ = bI.LocalPlayer
            local bK = false
            local bL = false
            local Z = {}
            local _
            local bM
            local bN
            local bO

            local function bP()
                local bQ, bR = pcall(function()
                    return bH.Network.ServerStatsItem['Data Ping']:GetValue()
                end)

                return bQ and bR or 100
            end
            local function bQ()
                if bG:FindFirstChild'MainEvent' then
                    return bG.MainEvent
                elseif bG:FindFirstChild'MAINEVENT' then
                    return bG.MAINEVENT
                elseif bG:FindFirstChild'MainRemotes' and bG.MainRemotes:FindFirstChild'MainRemoteEvent' then
                    return bG.MainRemotes.MainRemoteEvent
                end

                return nil
            end
            local function bR(bS, bT)
                local bU, bV = bS

                for bW, bX in q(bI:GetPlayers())do
                    if bX ~= bJ and bX.Character then
                        local bY = bX.Character:FindFirstChild'HumanoidRootPart'

                        if bY then
                            local bZ = (bY.Position - bT).Magnitude

                            if bZ < bU then
                                bV, bU = bX, bZ
                            end
                        end
                    end
                end

                return bV
            end
            local function bS(bT)
                if not bT or not bT.Character then
                    return false
                end

                for bU, bV in q(bT.Character:GetDescendants())do
                    if (bV.Name == 'BloodSplatter' or bV.Name == 'BloodParticles' or bV.Name == 'BloodParticle') and not table.find(Z, bV) then
                        table.insert(Z, bV)

                        return true, bV.Parent
                    end
                end

                return false
            end
            local function bT(bU, bV)
                if not bU or not bU.Character then
                    return false
                end

                local bW = bU.Character:FindFirstChild'Humanoid'

                if not bW then
                    return false
                end

                local bX = bW.Health

                return bX < bV
            end
            local function bU(bV, bW, bX)
                local bY = bV and bV.Parent
                local bZ = bY and bY.Name or '?'
                local b_ = bR(10, bX)

                if not b_ then
                    return
                end

                local b0

                if b_.Character then
                    local b1 = b_.Character:FindFirstChild'Humanoid'

                    if b1 then
                        b0 = b1.Health
                    end
                end

                local b1 = (bP() + 30) / 1000

                task.delay(b1, function()
                    local b2, b3 = bS(b_)
                    local b4 = b0 and bT(b_, b0)

                    if b2 or b4 then
                        local b5 = 0

                        if b_.Character then
                            local b6 = b_.Character:FindFirstChild'Humanoid'

                            if b6 then
                                b5 = b6.Health
                            end
                        end

                        local b6 = b0 and (b0 - b5) or 0

                        if bM then
                            task.spawn(bM, b_, b3)
                        end
                        if bN then
                            task.spawn(bN, bW, bX)
                        end
                        if bO then
                            local b7 = {
                                hitdmg = math.floor(b6),
                                localgun = bZ,
                                targetlasthp = math.floor(b5),
                                hitpart = b3 and b3.Name or '?',
                                targetname = b_.Name,
                                targetdisplayname = b_.DisplayName,
                            }

                            task.spawn(bO, b7)
                        end
                    end
                end)
            end
            local function bV()
                if bK then
                    return
                end

                local bW = bQ()

                if not bW then
                    return
                end

                local bX = getrawmetatable(bW)

                if not bX then
                    return
                end

                setreadonly(bX, false)

                local bY = table.clone(bX)
                local bZ = bY.__namecall

                setrawmetatable(bW, {
                    __namecall = function(b_, ...)
                        local b0 = {...}

                        if getnamecallmethod() == 'FireServer' then
                            if b0[1] == 'ShootGun' then
                                local b1 = b0[3]
                                local b2 = b0[4]

                                if bL then
                                    task.spawn(bU, b0[2], b1, b2)
                                end
                                if _ then
                                    task.spawn(_, b1, b2)
                                end
                            end
                        end

                        return bZ(b_, ...)
                    end,
                    __index = bY.__index,
                    __newindex = bY.__newindex,
                    __call = bY.__call,
                    __tostring = bY.__tostring,
                })

                bK = true
            end

            function bx.hitDetection_ragebot:setEnabled(bW)
                bL = bW

                if bW and not bK then
                    bV()
                end
            end
            function bx.hitDetection_ragebot:onShot(bW)
                _ = bW

                if not bK then
                    bV()
                end
            end
            function bx.hitDetection_ragebot:onHit(bW)
                bM = bW

                if not bK then
                    bV()
                end
            end
            function bx.hitDetection_ragebot:onHitShot(bW)
                bN = bW

                if not bK then
                    bV()
                end
            end
            function bx.hitDetection_ragebot:onHitNotify(bW)
                bO = bW

                if not bK then
                    bV()
                end
            end

            return bx.hitDetection_ragebot
        end
    end

    bE()()
    bx.hitDetection_ragebot:setEnabled(true)
    bx.hitDetection_ragebot:onHitNotify(function(bF)
        local bG = game.Players:FindFirstChild(bF.targetname)

        if not bG or not bG.Character then
            return
        end

        local bH = bG.Name .. '_hit'

        if bx.notifakcache[bH] then
            return
        end

        bx.notifakcache[bH] = true

        task.delay(0.1, function()
            bx.notifakcache[bH] = nil
        end)

        local bI = bG.Character:FindFirstChildOfClass'Humanoid'

        if not bI then
            return
        end

        local bJ = bx.lasthitnotifyhealth[bG] or bI.MaxHealth
        local bK = bI.Health
        local bL = math.max(bJ - bK, 0)

        if bL > 0 then
            bx.lasthitnotifyhealth[bG] = bK
        else
            bx.lasthitnotifyhealth[bG] = bK
        end
        if bx.ShootSoundOverride and bx.SelectedShootSound ~= 'Default' then
            local bM = bx.SHOOT_SOUNDS_DATA[bx.SelectedShootSound]
            local bN = bx.getAsset_hdsy(bx.SelectedShootSound, bM)

            if bN and bN ~= '' then
                local bO = Instance.new'Sound'

                bO.SoundId = bN
                bO.Volume = bx.ShootSoundVolume * 5
                bO.PlaybackSpeed = bx.ShootSoundPitch
                bO.Parent = workspace

                bO:Play()
                game:GetService'Debris':AddItem(bO, 2)
            end
        end
        if bx.hit_effect_enabled then
            local bM = bG.Character:FindFirstChild'HumanoidRootPart'

            if bM then
                local bN = bx.hiteffectTable[bx.selected_hit_effect]

                if bN then
                    bN(bM.Position)
                end
            end
        end
        if bx.sdjihfibnsnbvbdffhbjn.Enabled then
            local bM = game.Players.LocalPlayer
            local bN = bM.Character

            if bN then
                local bO = bN:FindFirstChildOfClass'Tool'
                local bP = bN:FindFirstChild'HumanoidRootPart'
                local bQ = bG.Character:FindFirstChild'HumanoidRootPart'

                if bQ and bP then
                    local bR = (bO and bO:FindFirstChild'Handle') and bO.Handle.Position or bP.Position

                    bx.fghjsdfgksdfjgkldfs(bR, bQ.Position)
                end
            end
        end
        if bx.hitnotifyenabled and bL > 0 then
            local bM = bx.hitcustomnotify and bx.hitcustomtext or 'cracked (user) for (%)'
            local bN = bM

            bN = bN:gsub('%(user%)', bF.targetdisplayname or bF.targetname)
            bN = bN:gsub('%(%)', '99')

            H:notification{
                text = bN,
                duration = bx.hitnotifyduration,
            }
        end
        if bx.IsEnabledDmg then
            bx.DoDmgDisplay(bG, math.floor(bL))
        end
    end)
end

local bE = U
local bF = bx or {}

bF.Ammomapragebot = {
    ['[LMG]'] = '200 [LMG Ammo] - $338',
    ['[AK47]'] = '30 [AK47 Ammo] - $120',
    ['[Rifle]'] = '5 [Rifle Ammo] - $281',
    ['[AUG]'] = '90 [AUG Ammo] - $90',
    ['[Flintlock]'] = '6 [Flintlock Ammo] - $168',
}
bF.Multi_SpareAmmo = bF.Multi_SpareAmmo or 1
bF.GetCharacterRoot = function()
    local bG = game.Players.LocalPlayer.Character

    return bG and bG:FindFirstChild'HumanoidRootPart'
end
bF.BuyItem = function(bG)
    if not bG then
        return
    end

    local bH = bF.GetCharacterRoot()

    if not bH then
        return
    end

    local bI = workspace:WaitForChild'Ignored':WaitForChild'Shop'
    local bJ

    for bK, bL in q(bI:GetChildren())do
        if string.find(bL.Name, bG, 1, true) then
            bJ = bL

            break
        end
    end

    if bJ then
        local bK = bJ:FindFirstChildOfClass'ClickDetector'
        local bL = bJ:FindFirstChild'Head' or bJ:FindFirstChild'Handle' or bJ:FindFirstChildWhichIsA'BasePart'

        if bK and bL then
            bH.CFrame = CFrame.new(bL.Position + Vector3.new(0, 5, 0))

            task.wait(0.19)
            fireclickdetector(bK, 0)
            task.wait(0.1)
            fireclickdetector(bK, 0)
            task.wait(0.07)
        end
    end
end

local function bG()
    return bE.Character
end

local bH = game:GetService'ReplicatedStorage':WaitForChild'MainEvent'
local bI = false

getgenv().voidpsamragemethodeefwsuhefn = 'while targeting'

local bJ = {}

getgenv().connectionresolvderfgdg = false
bF.Multi_IsBuying = false
bF.flamethrower_hack = false
bF.flameOrbitAngle = 0
bF.flameOrbitSpeed = 4
getgenv().beanbag_method = false
bF.flameOrbitDistance = 8
bF.flameOrbitHeight = 8

local bK, bL, bM
local bN = {}
local bO = false
local bP = 0
local bQ = false
local bR = 60
local bS = false

bF.voidPatternIdx = bF.voidPatternIdx or 1
bF.lastPatternSwitch = bF.lastPatternSwitch or 0

local bT
local bU = 0
local bV = 'waiting'
local bW = 100
local bX = 0
local bY = Drawing.new'Text'

bY.Size = 14
bY.Font = 2
bY.Color = Color3.fromRGB(255, 255, 255)
bY.Outline = true
bY.Center = true
bY.Visible = true
bY.Text = ''

local function bZ() end

local b_ = LPH_NO_VIRTUALIZE(function(b_)
    if not b_ or not b_.Character then
        return 'invalid'
    end

    local b0 = b_.Character:FindFirstChild'BodyEffects'

    if b0 then
        local b1 = b0:FindFirstChild'K.O' or b0:FindFirstChild'KO'
        local b2 = b0:FindFirstChild'SDeath'

        if b1 and b1.Value then
            return (b2 and b2.Value) and 'dead' or 'knocked'
        end
    end
    if b_.Character:FindFirstChild'ForceField' then
        return 'forcefield'
    end

    return 'targeting'
end)
local b0 = LPH_NO_VIRTUALIZE(function()
    if not bF.MultiSelectedTargets or next(bF.MultiSelectedTargets) == nil then
        return nil
    end

    local b0 = game.Players.LocalPlayer

    for b1, b2 in q(game.Players:GetPlayers())do
        if b2 ~= b0 and bF.MultiSelectedTargets[b2.Name] then
            local b3 = b_(b2)

            if b3 ~= 'dead' and b3 ~= 'forcefield' then
                return b2
            end
        end
    end

    return nil
end)

if bF.RageRender1 then
    bF.RageRender1:Disconnect()
end

bF.RageRender1 = game:GetService'RunService'.RenderStepped:Connect(LPH_JIT_MAX(function()
    if not (by.Target.AutoKill and by.Target.Target) then
        bY.Visible = false
        bF.CurrentBuyingItem = nil
        bF.Multi_IsBuying = false
        bF.IsBuying = false
        bF.busdhfnjsy7gjsy7d = false

        return
    end

    bY.Visible = true

    local b1 = game.Players:FindFirstChild(by.Target.Target)

    if not b1 then
        bY.Text = 'target has left the server'
        bF.StopInvis = true
        by.Target.AutoKill = false
        bF.CurrentBuyingItem = nil
        bF.Multi_IsBuying = false
        bF.IsBuying = false
        bF.busdhfnjsy7gjsy7d = false

        if I then
            I.auto_sentry = false
        end

        local b2 = bE.Character

        if b2 then
            for b3, b4 in r(b2:GetDescendants())do
                if b4:IsA'BasePart' or b4:IsA'Decal' then
                    b4.LocalTransparencyModifier = 0
                end
            end

            local b3 = b2:FindFirstChild'HumanoidRootPart'

            if b3 and bB then
                b3.CFrame = bB
                bB = nil
            end
        end

        return
    end
    if not b1.Character then
        bY.Text = 'waiting for character'

        return
    end

    local b2 = b1.Character:FindFirstChildOfClass'Humanoid'
    local b3 = b_(b1)
    local b4 = b2 and math.floor(b2.Health) or 0
    local b5 = b1.DisplayName ~= '' and b1.DisplayName or b1.Name

    local function b6()
        if not I.sdgmuje4rmutirjmtg then
            return nil
        end

        local b7 = n()
        local Z = math.sin(b7 * 2) * 0.5 + 0.5
        local _ = math.cos(b7 * 3.7) * 0.5 + 0.5
        local b8 = math.random() * 0.1
        local b9 = (Z * 0.6 + _ * 0.4 + b8) * 49.999 + 0.001

        return string.format('%.3f', math.clamp(b9, 0.001, 50))
    end

    local b7 = b6()

    if b3 == 'dead' or b3 == 'forcefield' then
        bY.Text = 'hiding in void...'
    elseif bF.Multi_IsBuying or bF.IsBuying or bF.busdhfnjsy7gjsy7d then
        local b8 = 'buying...'

        if bF.CurrentBuyingItem then
            b8 = b8 .. ' (' .. bF.CurrentBuyingItem .. ')'
        end

        bY.Text = b8
    elseif b3 == 'knocked' then
        bY.Text = 'stomping:' .. b5
    else
        local b8 = bE.Character:FindFirstChildOfClass'Tool'
        local b9 = false

        if b8 and b8:FindFirstChild'Ammo' then
            b9 = b8.Ammo.Value <= 0
        end
        if b9 then
            bY.Text = 'reloading guns...'
        else
            if b7 then
                bY.Text = string.format('killing: %s(resolved:%s:false):health:%d', b5, b7, b4)
            else
                bY.Text = string.format('killing: %s:health:%d', b5, b4)
            end
        end
    end

    bY.Position = Vector2.new(workspace.CurrentCamera.ViewportSize.X / 2, workspace.CurrentCamera.ViewportSize.Y / 1.3)
end))

local function b1(b2, b3)
    b3 = b3 or 3

    if bF.notifakcache[b2] then
        return
    end

    bF.notifakcache[b2] = true

    task.delay(b3, function()
        bF.notifakcache[b2] = nil
    end)
    H:notification{b2}
end
local function b2()
    table.clear(bN)

    local b3 = I.gunsmulti

    if b3 and s(b3) == 'table' then
        for b4, b5 in q(b3)do
            bN[b5] = true
        end
    end
end
local function b3()
    local b4 = bE:FindFirstChild'Backpack'
    local b5 = bE.Character

    if not b4 or not b5 then
        return
    end

    for b6, b7 in q(b4:GetChildren())do
        if b7:IsA'Tool' and bN[b7.Name] and b7:FindFirstChild'Handle' then
            b7.Parent = b5
        end
    end
end
local function b4()
    if bK then
        bK:Disconnect()
    end
    if bL then
        bL:Disconnect()
    end

    table.clear(bJ)

    local b5 = bE.Character

    if not b5 then
        return
    end

    for b6, b7 in q(b5:GetChildren())do
        if b7:IsA'Tool' and bN[b7.Name] then
            if not table.find(bJ, b7) then
                table.insert(bJ, b7)
            end
        end
    end

    bK = b5.ChildAdded:Connect(function(b6)
        if b6:IsA'Tool' and bN[b6.Name] then
            if not table.find(bJ, b6) then
                table.insert(bJ, b6)
            end
        end
    end)
    bL = b5.ChildRemoved:Connect(function(b6)
        if b6:IsA'Tool' then
            local b7 = table.find(bJ, b6)

            if b7 then
                table.remove(bJ, b7)
            end
        end
    end)
end
local function b5()
    local b6 = bE:WaitForChild'Backpack'

    if bM then
        bM:Disconnect()
    end

    bM = b6.ChildAdded:Connect(function(b7)
        local b8 = bE.Character

        if b8 and b7:IsA'Tool' and bN[b7.Name] then
            task.wait(0.05)

            if b7.Parent == b6 then
                b7.Parent = b8
            end
        end
    end)
end

local b6 = LPH_JIT_MAX(function(b6)
    local b7 = b6.Character and b6.Character:FindFirstChild'HumanoidRootPart'

    if not b7 then
        return Vector3.new()
    end

    local b8 = bF.exploitresolverat.scriptt.dataaa.last_positions

    if not b8[b6] then
        b8[b6] = {}
    end

    local b9 = b8[b6]

    b9[#b9 + 1] = b7.Position

    if #b9 > bR then
        table.remove(b9, 1)
    end

    local Z = #b9

    if Z < 4 then
        return b9[Z]
    end

    return b9[Z - math.random(0, 3)]
end)

getgenv().ArtEnabled = false
getgenv().ArtRefreshTime = 3
getgenv().ArtForgiveness = 14.4
getgenv().ArtLogLimit = 500
getgenv().ArtMinMatches = 4
getgenv().ArtOutOfVoidBonus = 5
getgenv().ArtDistPenalty = 3.1

local b7 = {
    position_log = {},
    found_pattern = nil,
    last_refresh = n(),
}
local b8 = LPH_JIT_MAX(function(b8, b9)
    if not getgenv().ArtEnabled then
        return b9
    end

    local Z = n()
    local _ = game.Players.LocalPlayer

    if Z - b7.last_refresh >= (getgenv().ArtRefreshTime or 3) then
        b7.position_log = {}
        b7.found_pattern = nil
        b7.last_refresh = Z
    end

    local ca = getgenv().ArtForgiveness or 14.4
    local cb = getgenv().ArtMinMatches or 4
    local cc = getgenv().ArtDistPenalty or 2
    local cd = math.abs(b9.X) + math.abs(b9.Z)
    local ce = cd < 5700

    if ce then
        ca = ca + (getgenv().ArtOutOfVoidBonus or 5)
    end

    local cf = _.Character

    if cf and cf:FindFirstChild'HumanoidRootPart' then
        local cg = (b9 - cf.HumanoidRootPart.Position).Magnitude
        local ch = (cg / 100) * cc

        ca = math.clamp(ca - ch, 1, 100)
    end

    table.insert(b7.position_log, {
        pos = b9,
        time = Z,
    })

    local cg = getgenv().ArtLogLimit or 500

    if #b7.position_log > cg then
        table.remove(b7.position_log, 1)
    end

    local ch = b7.position_log

    if #ch < 10 then
        return b9
    end

    local ci = {}

    for cj = 1, #ch do
        local ck = ch[cj].pos
        local cl = 0
        local cm = Vector3.new(0, 0, 0)

        for cn = 1, #ch do
            local co = ch[cn].pos

            if (ck - co).Magnitude <= ca then
                cl = cl + 1
                cm = cm + co
            end
        end

        if cl >= cb then
            table.insert(ci, {
                pos = cm / cl,
                count = cl,
            })
        end
    end

    local cj

    for ck, cl in q(ci)do
        if not cj or cl.count > cj.count then
            cj = cl
        end
    end

    if cj then
        b7.found_pattern = cj.pos

        return cj.pos
    end

    return b9
end)
local b9 = LPH_JIT_MAX(function(b9)
    if not b9 or not b9.Character then
        return nil
    end

    local ca = b9.Character:FindFirstChild'HumanoidRootPart'

    if not ca then
        return nil
    end

    return b8(ca, ca.Position)
end)

local function ca()
    if not (I and I.auto_sentry) then
        return
    end
    if bF.Multi_IsBuying then
        return
    end

    local cb = I.gunsmulti

    if not cb or s(cb) ~= 'table' then
        return
    end

    local cc = bE:FindFirstChild'Backpack'
    local cd = bE.Character

    if not cc or not cd then
        return
    end

    local ce = cd:FindFirstChild'BodyEffects'

    if ce then
        local cf = ce:FindFirstChild'FULLY_LOADED_CHAR'

        if cf and not cf.Value then
            return
        end
    end

    local cf = {}

    for cg, ch in q(cb)do
        local ci = ch:gsub(' %- %$%d+', '')

        if not (cc:FindFirstChild(ci) or cd:FindFirstChild(ci)) then
            table.insert(cf, ci)
        end
    end

    if #cf > 0 then
        bF.Multi_IsBuying = true

        for cg, ch in q(cd:GetChildren())do
            if ch:IsA'Tool' then
                ch.Parent = cc
            end
        end

        task.wait(0.1)

        local cg = cd:FindFirstChild'HumanoidRootPart' or bF.GetCharacterRoot()
        local ch = cg and cg.CFrame

        for ci, cj in q(cf)do
            bF.CurrentBuyingItem = bF.Ammomapragebot[cj] or cj

            bF.BuyItem(cj)
            task.wait(0.06)
        end

        task.wait(0.5)

        if (bF.Multi_SpareAmmo or 0) > 0 then
            bF.BuyAmmoForWeapons(cf, bF.Multi_SpareAmmo or 0)
            task.wait(0.5)
        end
        if cg and ch then
            cg.CFrame = ch
        end

        task.wait(0.3)
        b2()
        b3()

        bF.CurrentBuyingItem = nil
        bF.Multi_IsBuying = false
    end
end

bF.PlayedKnockSoundFor = bF.PlayedKnockSoundFor or {}
bF.PlayedKnockEffectFor = bF.PlayedKnockEffectFor or {}
bF.PlayedKnockNotificationFor = bF.PlayedKnockNotificationFor or {}
bF.v88cksnwq = bF.v88cksnwq or {}

if bF.RageHeartbeat then
    bF.RageHeartbeat:Disconnect()
end

bF.RageHeartbeat = game:GetService'RunService'.Heartbeat:Connect(LPH_JIT_MAX(function(cb)
    local cc, cd = pcall(function()
        if not by.Target.AutoKill then
            return
        end

        local cc = game:GetService'Players'.LocalPlayer
        local cd = cc.Character

        if not cd or not cd.Parent then
            return
        end

        local ce = cd:FindFirstChild'HumanoidRootPart'
        local cf = cd:FindFirstChildOfClass'Humanoid'

        if not ce or not cf or cf.Health <= 0 or ce.Position.Y < -1E3 then
            pcall(function()
                sethiddenproperty(ce, 'PhysicsRepRootPart', nil)
            end)

            return
        end
        if bF.Multi_IsBuying or bF.IsBuying or bF.busdhfnjsy7gjsy7d then
            bZ()

            return
        end

        local cg = cd:FindFirstChild'BodyEffects'
        local ch = cg and (cg:FindFirstChild'K.O' or cg:FindFirstChild'KO') and (cg:FindFirstChild'K.O' or cg:FindFirstChild'KO').Value

        if ch then
            by.Target.AutoKill = false

            if I then
                I.auto_sentry = false
            end

            pcall(function()
                sethiddenproperty(ce, 'PhysicsRepRootPart', nil)
            end)

            return
        end

        local ci = game:GetService'Players':FindFirstChild(by.Target.Target or '')

        if not ci or not ci.Character or not ci.Character:FindFirstChild'HumanoidRootPart' then
            bX = 0
            bU = 0
            bV = 'waiting'

            pcall(function()
                sethiddenproperty(ce, 'PhysicsRepRootPart', nil)
            end)

            return
        end

        local cj = ci.Character
        local ck = cj:FindFirstChild'BodyEffects'
        local cl = ck and (ck:FindFirstChild'K.O' or ck:FindFirstChild'KO')
        local cm = ck and ck:FindFirstChild'SDeath'
        local cn = cl and cl.Value
        local co = cm and cm.Value
        local Z = cj:FindFirstChild'ForceField'
        local _ = {
            '[Knife]',
            '[Shovel]',
            '[Bat]',
        }

        if not cn and not co then
            bF.PlayedKnockSoundFor[ci.Name] = nil
            bF.PlayedKnockEffectFor[ci.Name] = nil
            bF.PlayedKnockNotificationFor[ci.Name] = nil
            bF.v88cksnwq[ci.Name] = nil
        end
        if by.Target.AutoKill and by.Target.Target and not cn and not co then
            local cp = cj:FindFirstChild'HumanoidRootPart'

            if cp and (getgenv().connectionresolvderfgdg or bF.flamethrower_hack or getgenv().beanbag_method) then
                pcall(function()
                    sethiddenproperty(ce, 'PhysicsRepRootPart', cp)
                end)
            else
                pcall(function()
                    sethiddenproperty(ce, 'PhysicsRepRootPart', nil)
                end)
            end
        else
            pcall(function()
                sethiddenproperty(ce, 'PhysicsRepRootPart', nil)
            end)
        end
        if by.Target.AutoKill and by.Target.Target then
            local cp = cj:FindFirstChild'HumanoidRootPart'
            local cq = cj:FindFirstChild'Head'
            local cr = cj:FindFirstChildOfClass'Humanoid'

            if not (cp and cr) then
                return
            end
            if co then
                bX = 0
                bU = 0
                bV = 'waiting'
                bF.HitPredictRunning = false
                ce.CFrame = CFrame.new(math.random(-1766E3, 1766000), 200000, math.random(-1766E3, 1766000))

                if bF.flamethrower_hack then
                    local cs = cd:FindFirstChild'[Flamethrower]'

                    if cs then
                        cs:Deactivate()
                    end
                end
                if I.glueresolver then
                    for cs, ct in q(_)do
                        local cu = cc.Backpack:FindFirstChild(ct)

                        if cu then
                            cf:EquipTool(cu)

                            break
                        end
                    end
                end

                return
            end

            local cs = false

            if by.Sentry.SafeMode and cf and cf.Health / cf.MaxHealth <= 0.2 then
                if not by.Sentry.LastPos then
                    by.Sentry.LastPos = ce.CFrame
                end

                ce.CFrame = CFrame.new(-2343245, -433224, -457732)
                cs = true
            elseif by.Sentry.LastPos then
                ce.CFrame = by.Sentry.LastPos
                by.Sentry.LastPos = nil
            end

            local ct = cd:FindFirstChildOfClass'Tool'

            if not cn then
                bF.HitPredictRunning = false

                local cu = cp.Position

                if I.sdgmuje4rmutirjmtg then
                    cu = b9(ci)
                elseif getgenv().FakePosResolverEnabled and getgenv().ResolvedPosition then
                    cu = getgenv().ResolvedPosition
                elseif bO then
                    cu = b6(ci)
                elseif by.Target.PredictionEnabled then
                    cu = cu + cp.Velocity * by.Target.PredictionAmount
                else
                    cu = (cq and cq.Position) or cu
                end
                if Z or (not bI and not ct and not bF.flamethrower_hack) or (bI and #bJ == 0 and not bF.flamethrower_hack) then
                    ce.CFrame = CFrame.new(math.random(-1766E3, 1766000), math.random(170000, 233000), math.random(-1766E3, 1766000))

                    if ct then
                        bw:FireServer('Reload', ct)
                    end
                elseif bF.flamethrower_hack then
                    local cv = cd:FindFirstChild'[Flamethrower]' or cc.Backpack:FindFirstChild'[Flamethrower]'

                    if cv then
                        if cv.Parent ~= cd then
                            cf:EquipTool(cv)
                        end

                        ce.CFrame = cp.CFrame * CFrame.new(0, 0, 3)

                        local cw = cv:FindFirstChild'Handle'

                        if cw and cq then
                            cw.CFrame = cq.CFrame * CFrame.new(0, (bF.flameOrbitHeight or 2), 0) * CFrame.Angles(math.rad(-90), 0, 0)
                        end

                        cv:Activate()
                    end
                elseif getgenv().connectionresolvderfgdg then
                    ce.CFrame = cj:GetPivot() * CFrame.new(0, 1.8, 2.4)

                    if bI then
                        for cv, cw in q(bJ)do
                            if cw.Parent == cd then
                                cw:Activate()
                            end
                        end
                    elseif ct and ct:IsDescendantOf(cd) and ct:FindFirstChild'Handle' then
                        ct:Activate()
                    end
                elseif getgenv().beanbag_method then
                    local cv = cd:FindFirstChild'[BeanBag]' or cc.Backpack:FindFirstChild'[BeanBag]'

                    if cv then
                        if cv.Parent ~= cd then
                            cf:EquipTool(cv)
                        end

                        ce.CFrame = cj:GetPivot() * CFrame.new(0, 1.8, 2.4)

                        local cw = cv:FindFirstChild'Handle'

                        if cw and cp then
                            cw.CFrame = cp.CFrame * CFrame.new(0, 0, 0)
                        end

                        cv:Activate()
                    end
                elseif not getgenv().GlueResolverEnabled then
                    local cv = false
                    local cw = I and I.ragebottemplehookunnamedenhancementsjujuascendifysample

                    if getgenv().ragevoidspm then
                        if cw then
                            if bX == 0 then
                                bX = n()
                                bU = 0
                                bV = 'waiting'
                                bW = cr and cr.Health or 100
                            end

                            local cx = cr and cr.Health or 100
                            local cy = cx < bW

                            bW = cx

                            local cz = I and I.smart_wait_seconds or 8
                            local cA = I and I.smart_void_seconds or 5

                            if bV == 'waiting' then
                                bU = bU + cb

                                if bU >= cz then
                                    if not cy and cx > 0 then
                                        bV = 'voiding'
                                        bU = 0
                                    else
                                        bU = 0
                                    end
                                end

                                cv = false
                            elseif bV == 'voiding' then
                                bU = bU + cb
                                cv = true

                                if bU >= cA then
                                    bV = 'waiting'
                                    bU = 0
                                end
                            end
                        else
                            local cx = getgenv().voidpsamragemethodeefwsuhefn

                            if cx == 'while targeting' or (cx == 'while reloading' and ct and ct:FindFirstChild'Ammo' and ct.Ammo.Value <= 0) then
                                cv = true
                            end
                        end
                    end
                    if cv then
                        bP = bP + cb

                        local cx = bQ and (getgenv().voidspaminvoidragee or 0.4) or 0.133

                        if bP >= cx then
                            bP = 0
                            bQ = not bQ
                        end
                    else
                        bQ = false

                        if not cw then
                            bX = 0
                        end
                    end
                    if bQ then
                        bF.patternType = I.s9dfoajobdhreywewdwedw
                        bF.vDirection = I.s9djjj22 or '+Y'
                        bF.switchSpeedVal = I.dfdgettdttrrrrttt6r or 0.01
                        bF.depthMult = I.dfdgettttfvrrrrttt6r or 1
                        bF.currentTime = n()
                        bF.lastPatternSwitch = bF.lastPatternSwitch or 0

                        if bF.currentTime - bF.lastPatternSwitch >= bF.switchSpeedVal then
                            bF.lastPatternSwitch = bF.currentTime

                            if bF.patternType == 'NaN point' then
                                local cx = 1e16 * bF.depthMult
                                local cy = {
                                    1E8,
                                    5E7,
                                    25E6,
                                    1E7,
                                    1E7,
                                    2.5E7,
                                    5E7,
                                    1E8,
                                }
                                local cz = (cy[math.random(1, #cy)] + math.random(1E4, 1E4)) * bF.depthMult
                                local cA = (cy[math.random(1, #cy)] + math.random(1E4, 1E4)) * bF.depthMult
                                local cB = math.random(1, 23)

                                if cB > 20 then
                                    local cC = {
                                        0,
                                        7.5E7 * bF.depthMult,
                                        -75E6 * bF.depthMult,
                                    }
                                    local cD = cC[math.random(1, #cC)]

                                    if bF.vDirection == '+Y' then
                                        bF.voidPos = Vector3.new(cD, cx, cD)
                                    elseif bF.vDirection == '+X' then
                                        bF.voidPos = Vector3.new(cx, cD, cD)
                                    elseif bF.vDirection == '+Z' then
                                        bF.voidPos = Vector3.new(cD, cD, cx)
                                    end
                                else
                                    if bF.vDirection == '+Y' then
                                        bF.voidPos = Vector3.new(cz, cx, cA)
                                    elseif bF.vDirection == '+X' then
                                        bF.voidPos = Vector3.new(cx, cz, cA)
                                    elseif bF.vDirection == '+Z' then
                                        bF.voidPos = Vector3.new(cz, cA, cx)
                                    end
                                end
                            elseif bF.patternType == 'deep void' then
                                local cx = {
                                    2E6,
                                    5E6,
                                    1E7,
                                    2E7,
                                    5E7,
                                }
                                local cy = {
                                    1E5,
                                    25E4,
                                    5E5,
                                    1E6,
                                    2E6,
                                }
                                local cz = cx[math.random(1, #cx)] * bF.depthMult
                                local cA = (cy[math.random(1, #cy)] + math.random(1E4, 2E4)) * bF.depthMult
                                local cB = (cy[math.random(1, #cy)] + math.random(1E4, 2E4)) * bF.depthMult

                                if bF.vDirection == '+Y' then
                                    bF.voidPos = Vector3.new(cA, cz, cB)
                                elseif bF.vDirection == '+X' then
                                    bF.voidPos = Vector3.new(cz, cA, cB)
                                elseif bF.vDirection == '+Z' then
                                    bF.voidPos = Vector3.new(cA, cB, cz)
                                end
                            else
                                local cx = math.random(150000, 250000) * bF.depthMult
                                local cy = math.random(1000, 5000) * bF.depthMult
                                local cz = math.random(1000, 5000) * bF.depthMult

                                if bF.vDirection == '+Y' then
                                    bF.voidPos = Vector3.new(cy, cx, cz)
                                elseif bF.vDirection == '+X' then
                                    bF.voidPos = Vector3.new(cx, cy, cz)
                                elseif bF.vDirection == '+Z' then
                                    bF.voidPos = Vector3.new(cy, cz, cx)
                                end
                            end
                        end

                        ce.CFrame = CFrame.new(bF.voidPos or ce.Position)
                        cs = true
                    else
                        local cx = bS and Vector3.new(math.random(-62, 63), math.random(-27, 25), math.random(-52, 60)) or Vector3.new(math.random(-bA, bA), math.random(-bA, bA), math.random(-bA, bA))

                        ce.CFrame = CFrame.lookAt(cu + cx, cu)
                    end
                end
                if not Z and not cs and not bF.flamethrower_hack then
                    bw:FireServer('UpdateMousePosI2', cu)

                    local cv = bI and bJ or {ct}

                    for cw, cx in q(cv)do
                        if cx and cx:IsA'Tool' and cx.Parent == cd then
                            local cy = cx:FindFirstChild'Ammo'

                            if (cx.Name == '[Flintlock]' and cy and cy.Value == 0) or (cy and cy.Value <= 0) then
                                bw:FireServer('Reload', cx)
                            else
                                if cx:FindFirstChild'Handle' then
                                    bw:FireServer('ShootGun', cx.Handle, cx.Handle.Position, cu, cq, Vector3.new(0, 1, 0))

                                    if bF.sdjihfibnsnbvbdffhbjn.Enabled then
                                        bF.fghjsdfgksdfjgkldfs(cx.Handle.Position, cu)
                                    end
                                    if cy and cy.Value > 0 and cy.Value <= 3 then
                                        task.spawn(function()
                                            task.wait(0.1)
                                            bw:FireServer('Reload', cx)
                                        end)
                                    end
                                elseif cx:IsDescendantOf(cd) then
                                    cx:Activate()

                                    if cy and cy.Value > 0 and cy.Value <= 3 then
                                        task.spawn(function()
                                            task.wait(0.1)
                                            bw:FireServer('Reload', cx)
                                        end)
                                    end
                                end
                            end
                        end
                    end
                end
            end
            if cn and not co then
                if bF.flamethrower_hack then
                    local cu = cd:FindFirstChild'[Flamethrower]'

                    if cu then
                        cu.Parent = cc.Backpack
                    end
                end
                if I.glueresolver then
                    for cu, cv in q(_)do
                        local cw = cd:FindFirstChild(cv)

                        if cw and cw:IsA'Tool' then
                            cw.Parent = cc.Backpack
                        end
                    end
                end

                local cu = cj:FindFirstChild'UpperTorso' or cj:FindFirstChild'Torso'

                if cu then
                    local cv = Vector3.new(0, I.edrfghhdetdffvvvvvvc or 3, 0)
                    local cw = cu.Position + (cu.Velocity * cb)

                    ce.CFrame = CFrame.new(cw + cv)
                    ce.Velocity = Vector3.zero
                    ce.AssemblyLinearVelocity = Vector3.zero

                    bw:FireServer'Stomp'
                    task.wait(0.02)
                    bw:FireServer'Stomp'

                    if I.glueresolver and getgenv().hitpedictglueee and not bF.HitPredictRunning then
                        bF.HitPredictRunning = true

                        task.spawn(function()
                            task.wait(13.3)

                            while by.Target.Target == ci.Name and cn and not co and not Z and I.glueresolver do
                                local cx

                                for cy, cz in q(_)do
                                    local cA = cc.Backpack:FindFirstChild(cz)

                                    if cA then
                                        cx = cA

                                        break
                                    end
                                end

                                if cx and cx.Parent == cc.Backpack then
                                    cf:EquipTool(cx)

                                    local cy = n()

                                    repeat
                                        task.wait()
                                    until cx.Parent == cd or n() - cy > 1

                                    if cx.Parent == cd then
                                        cx:Activate()
                                    end
                                end

                                task.wait(7)
                            end

                            bF.HitPredictRunning = false
                        end)
                    end
                    if not bF.PlayedKnockSoundFor[ci.Name] then
                        bF.PlayedKnockSoundFor[ci.Name] = true
                    end
                    if bF.f28skdn and not bF.v88cksnwq[ci.Name] then
                        bF.v88cksnwq[ci.Name] = true

                        bF.u77vmsq(cj)
                    end
                    if bF.IsEnabledDmg and not bF.PlayedKnockDamageFor[ci.Name] then
                        bF.PlayedKnockDamageFor[ci.Name] = true

                        local cx = bF.PrevHealth[ci.UserId] or 100

                        bF.DoDmgDisplay(ci, math.floor(cx))
                    end
                end
            elseif co then
                if not bF.HasReloadedAfterKill then
                    bF.HasReloadedAfterKill = true

                    LPH_NO_VIRTUALIZE(function()
                        if bI then
                            for cu, cv in q(bJ)do
                                if cv and cv.Parent == cd then
                                    bw:FireServer('Reload', cv)
                                end
                            end
                        else
                            local cu = cd:FindFirstChildOfClass'Tool'

                            if cu then
                                bw:FireServer('Reload', cu)
                            end
                        end

                        task.wait(0.5)

                        bF.HasReloadedAfterKill = nil
                    end)()
                end
            end
        end
    end)
end))

if bF.RageRender2 then
    bF.RageRender2:Disconnect()
end

bF.RageRender2 = game:GetService'RunService'.RenderStepped:Connect(LPH_JIT_MAX(function()
    local cb, cc = pcall(function()
        if bF.Multi_IsBuying or bF.IsBuying or bF.busdhfnjsy7gjsy7d then
            bZ()

            return
        end
        if not by.Target.AutoKill or not by.Target.Target then
            return
        end

        local cb = game:GetService'Players':FindFirstChild(by.Target.Target)

        if not cb or not cb.Character then
            return
        end

        local cc = game.Players.LocalPlayer
        local cd = cc.Character

        if not cd or not cd.Parent then
            return
        end

        local ce = cd:FindFirstChild'HumanoidRootPart'
        local cf = cd:FindFirstChildOfClass'Humanoid'

        if not ce or not cf or cf.Health <= 0 then
            return
        end

        local cg = cb.Character:FindFirstChild'BodyEffects'
        local ch = cg and cg:FindFirstChild'SDeath' and cg.SDeath.Value
        local ci = cb.Character:FindFirstChild'ForceField'
        local cj = cd:FindFirstChildOfClass'Tool'
        local ck = bI and (#bJ > 0) or (cj ~= nil)

        if (ch or ci or not ck) and by.Target.AutoKill then
            ce.CFrame = CFrame.new(math.random(-1766E3, 1766000), math.random(170000, 233000), math.random(-1766E3, 1766000))

            if bI then
                for cl, cm in q(bJ)do
                    if cm.Parent == cd then
                        bw:FireServer('Reload', cm)
                    end
                end
            elseif cj and cj.Parent == cd then
                bw:FireServer('Reload', cj)
            end
        end
    end)
end))
getgenv().ResolvedPosition = nil

game:GetService'ReplicatedStorage'.MainEvent.OnClientEvent:Connect(LPH_NO_VIRTUALIZE(function(cb, cc, cd, ce, cf, cg, ch)
    if not getgenv().FakePosResolverEnabled then
        return
    end

    local ci = by.Target.Target

    if not ci then
        return
    end

    local cj = game:GetService'Players':FindFirstChild(ci)

    if cj and cc == cj then
        if ce and t(ce) == 'Vector3' then
            getgenv().ResolvedPosition = ce

            task.delay(1, function()
                if getgenv().ResolvedPosition == ce then
                    getgenv().ResolvedPosition = nil
                end
            end)
        end
    end
end))
task.spawn(function()
    while task.wait(0.5) do
        local cb = by.Target.Target

        if cb then
            local cc = P:FindFirstChild(cb)

            if cc and cc.Character then
                local cd = cc.Character:FindFirstChild'BodyEffects'

                if cd then
                    local ce = cd:FindFirstChild'K.O' or cd:FindFirstChild'KO'

                    if not (ce and ce.Value) then
                        bF.PlayedKnockSoundFor[cb] = nil
                        bF.PlayedKnockEffectFor[cb] = nil
                    end
                end
            else
                bF.PlayedKnockSoundFor[cb] = nil
                bF.PlayedKnockEffectFor[cb] = nil
            end
        end
    end
end)
task.spawn(function()
    while task.wait(0.2) do
        local cb = game.Players.LocalPlayer
        local cc = cb.Character

        if cc and by.Target.AutoKill == false and currentTarget and I and I.auto_sentry == false then
            local cd = cc:FindFirstChild'BodyEffects'
            local ce = cd and (cd:FindFirstChild'K.O' or cd:FindFirstChild'KO') and (cd:FindFirstChild'K.O' or cd:FindFirstChild'KO').Value
            local cf = cc:FindFirstChildOfClass'Humanoid'

            if not ce and cf and cf.Health > 0 and currentTarget and game.Players:FindFirstChild(currentTarget) then
                local cg = game.Players:FindFirstChild(currentTarget)

                if cg and cg.Character then
                    local ch = cg.Character:FindFirstChild'BodyEffects'
                    local ci = ch and (ch:FindFirstChild'K.O' or ch:FindFirstChild'KO')
                    local cj = ch and ch:FindFirstChild'SDeath' and ch.SDeath.Value

                    if not (ci and ci.Value) and not cj then
                        I.auto_sentry = true
                        by.Target.AutoKill = true
                        bF.StopInvis = false

                        task.spawn(function()
                            while cc and cc.Parent and by.Target.AutoKill and not bF.StopInvis do
                                for ck, cl in r(cc:GetDescendants())do
                                    if cl:IsA'BasePart' or cl:IsA'Decal' then
                                        cl.LocalTransparencyModifier = 1
                                    end
                                end

                                game:GetService'RunService'.RenderStepped:Wait()
                            end
                        end)
                    end
                end
            end
        end
    end
end)

bF.BlacklistedPlayers = bF.BlacklistedPlayers or {}

local cb
local cc = bp:dropdown{
    name = 'ragebot target',
    flag = 'target_dropdown',
    items = {
        '[none]',
    },
    callback = function(cc)
        getgenv().ResolvedPosition = nil

        if cc and cc ~= '[none]' then
            local cd = tostring(cc)
            local ce = cd:match'^(.+)%s+%(' or cd

            cb = ce

            if by and by.Target then
                by.Target.Target = ce
            end
        else
            cb = nil

            if by and by.Target then
                by.Target.Target = nil
            end
        end
    end,
}

task.spawn(function()
    while task.wait(1) do
        local cd = {
            '[none]',
        }
        local ce = false

        for cf, cg in q(game:GetService'Players':GetPlayers())do
            if cg ~= game:GetService'Players'.LocalPlayer then
                local ch = (cg.DisplayName and cg.DisplayName ~= '') and cg.DisplayName or cg.Name
                local ci = cg.Name .. ' (' .. ch .. ')'

                table.insert(cd, ci)

                if cb == cg.Name then
                    ce = true
                end
            end
        end

        pcall(function()
            cc:list(cd)
        end)

        if cb then
            if not ce then
                cb = nil
                getgenv().ResolvedPosition = nil

                if by and by.Target then
                    by.Target.Target = nil
                end
                if I then
                    I.auto_sentry = false
                end
            end
        end
    end
end)
bq:slider{
    name = 'strafe random offset',
    flag = 'sentry_strafe656',
    default = 25.73971,
    min = 2,
    suffix = 'x',
    max = 50,
    interval = 0.001,
    callback = function(cd)
        bA = cd
    end,
}
bq:slider{
    name = 'stomp offset',
    flag = 'edrfghhdetdffvvvvvvc',
    default = 4.5,
    min = 0,
    suffix = 'x',
    max = 10,
    interval = 0.01,
    callback = function(cd)
        bC = cd
    end,
}
bq:slider{
    name = 'prediction',
    flag = 'aexecpred',
    default = 0.25462,
    suffix = 'x',
    min = 0,
    max = 1,
    interval = 0.001,
    callback = function(cd)
        by.Target.PredictionAmount = cd
        by.Target.PredictionEnabled = (cd > 0)
    end,
}
bp:toggle{
    name = 'ragebot',
    flag = 'auto_sentry',
    default = false,
    callback = function(cd)
        if cd then
            if bF.IsRespawning then
                H:notification{
                    text = 'ragebot will reinitialize after spawn',
                }

                return
            end

            local ce = bE:FindFirstChild'Backpack'
            local cf = bE.Character
            local cg = cf and cf:FindFirstChildOfClass'Humanoid'
            local ch = I.gunsmulti or {}
            local ci = true
            local cj = I.fgh845yhdg

            if not cj then
                if #ch == 0 then
                    ci = false
                else
                    for ck, cl in q(ch)do
                        local cm = cl:gsub(' %- %$%d+', '')

                        if not (ce:FindFirstChild(cm) or cf:FindFirstChild(cm)) then
                            ci = false

                            break
                        end
                    end
                end
            end
            if not ci and not cj then
                b2()
                ca()
                b3()
                b4()
                b5()

                bI = true
                ci = true

                for ck, cl in q(ch)do
                    local cm = cl:gsub(' %- %$%d+', '')

                    if not (ce:FindFirstChild(cm) or cf:FindFirstChild(cm)) then
                        ci = false

                        break
                    end
                end

                if not ci then
                    by.Target.AutoKill = false

                    if I then
                        I.auto_sentry = false
                    end

                    H:notification{
                        text = 'failed to buy required guns',
                    }

                    return
                end
            end
            if not cj and #ch > 0 then
                b2()
                b3()
                b4()
                b5()

                bI = true
            end
            if not cb or not game.Players:FindFirstChild(cb) then
                by.Target.AutoKill = false

                if I then
                    I.auto_sentry = false
                end

                H:notification{
                    text = 'no ragebot target selected',
                }

                return
            end

            by.Target.AutoKill = true
            by.Target.Target = cb

            local ck = cf and cf:FindFirstChild'HumanoidRootPart'

            if ck and cg and cg.Health > 0 and ck.Position.Y > -1E3 and ck.Position.Y < 5000 then
                bB = ck.CFrame
            end

            bF.StopInvis = false

            local function cl(cm)
                if not cm then
                    return
                end

                task.spawn(function()
                    while cm and cm.Parent and by.Target.AutoKill and not bF.StopInvis do
                        for cn, co in r(cm:GetDescendants())do
                            if co:IsA'BasePart' or co:IsA'Decal' then
                                co.LocalTransparencyModifier = 1
                            end
                        end

                        game:GetService'RunService'.RenderStepped:Wait()
                    end
                end)
            end

            if bE.Character then
                cl(bE.Character)
            end

            H:notification{
                text = 'ragebot enabled',
            }
        else
            bF.StopInvis = true
            by.Target.AutoKill = false
            bF.HitPredictRunning = false
            bI = false

            if bK then
                bK:Disconnect()
            end
            if bL then
                bL:Disconnect()
            end
            if bM then
                bM:Disconnect()
            end

            local ce = bE.Character
            local cf = bE:FindFirstChild'Backpack'

            if ce and cf then
                for cg, ch in q(ce:GetChildren())do
                    if ch:IsA'Tool' then
                        ch.Parent = cf
                    end
                end
            end

            table.clear(bJ)

            local cg = bE.Character

            if cg then
                for ch, ci in r(cg:GetDescendants())do
                    if ci:IsA'BasePart' or ci:IsA'Decal' then
                        ci.LocalTransparencyModifier = 0
                    end
                end

                local ch = cg:FindFirstChild'HumanoidRootPart'

                if ch then
                    pcall(function()
                        sethiddenproperty(ch, 'PhysicsRepRootPart', nil)
                    end)

                    ch.Velocity = Vector3.new(0, 0, 0)
                    ch.RotVelocity = Vector3.new(0, 0, 0)

                    if bB and t(bB) == 'CFrame' then
                        if not bF.IsRespawning and cg.Parent then
                            ch.CFrame = bB
                        end

                        bB = nil
                    end
                end
            end
        end
    end,
}

bF.vmsivb94j = game:GetService'Players'.LocalPlayer
bF.xcmvi84k2 = game:GetService'RunService'
bF.pqiwe02k1 = workspace.CurrentCamera
bF.zxcv92k1s = Drawing.new'Circle'
bF.zxcv92k1s.Visible = false
bF.zxcv92k1s.Transparency = 0.5
bF.zxcv92k1s.Thickness = 2
bF.zxcv92k1s.Filled = true
bF.asdf81l0p = Drawing.new'Circle'
bF.asdf81l0p.Visible = false
bF.asdf81l0p.Transparency = 1
bF.asdf81l0p.Color = Color3.new(0, 0, 0)
bF.asdf81l0p.Thickness = 1
bF.asdf81l0p.Filled = false
bF.qwer73m1n = Drawing.new'Circle'
bF.qwer73m1n.Visible = false
bF.qwer73m1n.Transparency = 1
bF.qwer73m1n.Color = Color3.new(0, 0, 0)
bF.qwer73m1n.Thickness = 1
bF.qwer73m1n.Filled = false
bF.dsgusnrmhgursg = LPH_NO_VIRTUALIZE(function()
    bF.hjkl55v9x = bF.vmsivb94j.Character
    bF.tyui66b8z = bF.hjkl55v9x and bF.hjkl55v9x:FindFirstChild'HumanoidRootPart'

    if bF.tyui66b8z and H.flags.cmdexe then
        bF.bnm12c4r, bF.op09x8z7 = bF.pqiwe02k1:WorldToViewportPoint(bF.tyui66b8z.Position)

        if bF.op09x8z7 then
            bF.lkj44h3g = Vector2.new(bF.bnm12c4r.X, bF.bnm12c4r.Y)
            bF.zxcv92k1s.Position = bF.lkj44h3g
            bF.asdf81l0p.Position = bF.lkj44h3g
            bF.qwer73m1n.Position = bF.lkj44h3g
            bF.zxcv92k1s.Visible = true
            bF.asdf81l0p.Visible = true
            bF.qwer73m1n.Visible = true
        else
            bF.zxcv92k1s.Visible = false
            bF.asdf81l0p.Visible = false
            bF.qwer73m1n.Visible = false
        end
    else
        bF.zxcv92k1s.Visible = false
        bF.asdf81l0p.Visible = false
        bF.qwer73m1n.Visible = false
    end
end)

bF.xcmvi84k2.RenderStepped:Connect(bF.dsgusnrmhgursg)
br:toggle{
    name = 'client circle visualizer',
    flag = 'cmdexe',
    default = false,
    callback = function(cd) end,
}
br:colorpicker{
    flag = 'cmdixi',
    color = Color3.new(1, 0.4, 0.7),
    callback = function(cd)
        bF.zxcv92k1s.Color = cd
    end,
}
br:colorpicker{
    flag = 'cmdixee',
    color = Color3.new(0, 0, 0),
    callback = function(cd)
        bF.asdf81l0p.Color = cd
        bF.qwer73m1n.Color = cd
    end,
}
br:slider{
    name = 'circle size',
    flag = 'cmdixe',
    default = 10,
    min = 1,
    suffix = 'px',
    max = 100,
    interval = 0.001,
    callback = function(cd)
        bF.zxcv92k1s.Radius = cd
        bF.asdf81l0p.Radius = cd + 1
        bF.qwer73m1n.Radius = cd - 1
    end,
}

bF.ifdjgudhguyerhghedfgn = Drawing.new'Line'
bF.ifdjgudhguyerhghedfgn.Thickness = 3
bF.ifdjgudhguyerhghedfgn.Color = Color3.new(0, 0, 0)
bF.ifdjgudhguyerhghedfgn.Visible = false
bF.fghjksdhfgjkhsdfgjk = Drawing.new'Line'
bF.fghjksdhfgjkhsdfgjk.Thickness = 1
bF.fghjksdhfgjkhsdfgjk.Color = Color3.new(1, 1, 1)
bF.fghjksdhfgjkhsdfgjk.Visible = false

local cd = false

br:toggle{
    name = 'client tracer visualizer',
    flag = 'dfjisnijnijvdsdjdfvjddvddddddd',
    default = false,
    callback = function(cf)
        cd = cf

        if not cf then
            bF.ifdjgudhguyerhghedfgn.Visible = false
            bF.fghjksdhfgjkhsdfgjk.Visible = false
        end
    end,
}
br:colorpicker{
    flag = 'cmdixeegggeer',
    color = Color3.new(1, 1, 1),
    callback = function(cf)
        bF.fghjksdhfgjkhsdfgjk.Color = cf
    end,
}
T.RenderStepped:Connect(LPH_NO_VIRTUALIZE(function()
    if not cd then
        bF.ifdjgudhguyerhghedfgn.Visible = false
        bF.fghjksdhfgjkhsdfgjk.Visible = false

        return
    end

    local cf = U.Character
    local cg = cf and cf:FindFirstChild'HumanoidRootPart'

    if cg then
        local ch, ci = V:WorldToViewportPoint(cg.Position)
        local cj = S:GetMouseLocation()

        if ci then
            bF.ifdjgudhguyerhghedfgn.From = cj
            bF.ifdjgudhguyerhghedfgn.To = Vector2.new(ch.X, ch.Y)
            bF.fghjksdhfgjkhsdfgjk.From = cj
            bF.fghjksdhfgjkhsdfgjk.To = Vector2.new(ch.X, ch.Y)
            bF.ifdjgudhguyerhghedfgn.Visible = true
            bF.fghjksdhfgjkhsdfgjk.Visible = true
        else
            bF.ifdjgudhguyerhghedfgn.Visible = false
            bF.fghjksdhfgjkhsdfgjk.Visible = false
        end
    else
        bF.ifdjgudhguyerhghedfgn.Visible = false
        bF.fghjksdhfgjkhsdfgjk.Visible = false
    end
end))
bs:toggle{
    name = 'enabled',
    flag = 'art_enabled_toggle',
    default = false,
    callback = function(cf)
        getgenv().ArtEnabled = cf
    end,
}
bs:slider{
    name = 'refresh time',
    flag = 'art_refresh_time',
    min = 1,
    suffix = 's',
    max = 10,
    default = 3,
    interval = 0.1,
    callback = function(cf)
        getgenv().ArtRefreshTime = cf
    end,
}
bs:slider{
    name = 'forgiveness',
    flag = 'art_forgiveness',
    min = 5,
    suffix = 'x',
    max = 20,
    default = 14.4,
    interval = 0.01,
    callback = function(cf)
        getgenv().ArtForgiveness = cf
    end,
}
bs:slider{
    name = 'position log limit',
    flag = 'art_poslog',
    min = 5,
    suffix = 'x',
    max = 800,
    default = 500,
    interval = 1,
    callback = function(cf)
        getgenv().ArtLogLimit = cf
    end,
}
bs:slider{
    name = 'min verify hits',
    flag = 'art_matchessss',
    min = 1,
    suffix = 'x',
    max = 10,
    default = 4,
    interval = 1,
    callback = function(cf)
        getgenv().ArtMinMatches = cf
    end,
}
bs:slider{
    name = 'out of void bonus',
    flag = 'art_out_of_void_bonus',
    min = 0,
    suffix = 'x',
    max = 20,
    default = 5,
    interval = 0.1,
    callback = function(cf)
        getgenv().ArtOutOfVoidBonus = cf
    end,
}
bs:slider{
    name = 'distance based penalty',
    flag = 'art_dist_penalty',
    min = 0,
    suffix = 'x',
    max = 5,
    default = 3.1,
    interval = 0.1,
    callback = function(cf)
        getgenv().ArtDistPenalty = cf
    end,
}
bu:toggle{
    name = 'enabled',
    flag = 'uhjh65hkg',
    default = false,
    callback = function(cf)
        getgenv().ragevoidspm = cf
        I.uhjh65hkg = cf
    end,
}
bu:dropdown{
    name = 'pattern',
    flag = 's9dfoajobdhreywewdwedw',
    items = {
        'deep void',
        'NaN point',
        'default void',
    },
    default = 'deep void',
    callback = function(cf)
        I.s9dfoajobdhreywewdwedw = cf
    end,
}
bu:dropdown{
    name = 'direction',
    flag = 's9djjj22',
    items = {
        '+Y',
        '+X',
        '+Z',
    },
    default = '+Y',
    callback = function(cf)
        I.s9djjj22 = cf
    end,
}
bu:slider{
    name = 'time in void',
    flag = 'dfgfthj564wfv',
    default = 0.133,
    suffix = 'sec',
    min = 0.01,
    max = 5,
    interval = 0.001,
    callback = function(cf)
        getgenv().voidspaminvoidragee = cf
    end,
}
bu:slider{
    name = 'void positions switch speed',
    flag = 'dfdgettdttrrrrttt6r',
    default = 0.02,
    suffix = 'x',
    min = 0.01,
    max = 5,
    interval = 0.01,
    callback = function(cf)
        I.dfdgettdttrrrrttt6r = cf
    end,
}
bu:slider{
    name = 'depth multiply',
    flag = 'dfdgettttfvrrrrttt6r',
    default = 13,
    min = 0,
    suffix = 'x',
    max = 20,
    interval = 1,
    callback = function(cf)
        I.dfdgettttfvrrrrttt6r = cf
    end,
}
bu:toggle{
    name = 'smart cycle',
    flag = 'ragebottemplehookunnamedenhancementsjujuascendifysample',
    default = false,
    callback = function(cf) end,
}
bu:slider{
    name = 'pause void hide for',
    flag = 'smart_wait_seconds',
    min = 1,
    max = 20,
    suffix = 'sec',
    default = 8,
    interval = 0.1,
    callback = function(cf) end,
}
bu:slider{
    name = 'void hide for',
    flag = 'smart_void_seconds',
    min = 1,
    max = 15,
    default = 5,
    suffix = 'sec',
    interval = 0.1,
    callback = function(cf) end,
}
br:toggle{
    name = 'abuse spawn protection',
    flag = 'sdjnfuewshjnfghj3eu7rgedj',
    default = false,
    callback = function(cf)
        bF.spawnProtectionAbuse = cf

        if cf then
            task.spawn(function()
                while bF.spawnProtectionAbuse do
                    if I.auto_sentry then
                        local cg = game.Players.LocalPlayer
                        local ch = cg.Character

                        if ch and ch:FindFirstChild'HumanoidRootPart' then
                            local ci = ch:FindFirstChildWhichIsA'Humanoid'

                            if ci then
                                ci:ChangeState(Enum.HumanoidStateType.Dead)
                            end

                            ch:ClearAllChildren()

                            local cj = Instance.new('Model', workspace)

                            cg.Character = cj

                            task.wait()

                            cg.Character = cg.Character

                            cj:Destroy()
                        end
                    end

                    task.wait(5.4)
                end
            end)
        end
    end,
}

bF.SpectateEnabled = true
bF.SpectateMode = 'spectate while ragebot active'

if bF.SpectateConnection then
    bF.SpectateConnection:Disconnect()
end

bF.SpectateConnection = T.RenderStepped:Connect(LPH_NO_VIRTUALIZE(function()
    if not bF.SpectateEnabled then
        if U.Character then
            local cf = U.Character:FindFirstChild'Humanoid'

            if cf and V.CameraSubject ~= cf then
                V.CameraSubject = cf
            end
        end

        return
    end

    local cf = by.Target.AutoKill
    local cg = by.Target.Target
    local ch = cg and P:FindFirstChild(cg)
    local ci = false

    if bF.SpectateMode == 'always spectate' then
        ci = true
    elseif bF.SpectateMode == 'spectate while ragebot active' and cf then
        ci = true
    end
    if ci and ch and ch.Character then
        local cj = ch.Character:FindFirstChild'Humanoid'

        if cj then
            if V.CameraSubject ~= cj then
                V.CameraSubject = cj
            end
        end
    else
        if U.Character then
            local cj = U.Character:FindFirstChild'Humanoid'

            if cj and V.CameraSubject ~= cj then
                V.CameraSubject = cj
            end
        end
    end
end))

bp:dropdown{
    name = 'guns to use',
    flag = 'gunsmulti',
    items = {
        '[AUG]',
        '[Rifle]',
        '[Flintlock]',
        '[LMG]',
        '[AK47]',
    },
    multi = true,
    callback = function(cf)
        b2()
    end,
}
bp:slider{
    name = 'spare ammo to buy',
    flag = 'spare_ammo_count',
    default = 1,
    min = 0,
    suffix = 'pcs',
    max = 7,
    interval = 1,
    callback = function(cf)
        bF.Multi_SpareAmmo = cf
    end,
}
br:button{
    name = 'teleport',
    callback = function()
        if cb and game.Players:FindFirstChild(cb) then
            game.Players.LocalPlayer.Character.HumanoidRootPart.CFrame = game.Players[cb].Character.HumanoidRootPart.CFrame
        end
    end,
}

local function cf(cg)
    ar = cg

    task.spawn(function()
        bE:WaitForChild('Backpack', 10)

        local ch = cg:WaitForChild('BodyEffects', 10)
        local ci = ch:WaitForChild('FULLY_LOADED_CHAR', 10)

        if ci then
            ci.Value = true
        end
        if bI then
            b2()
            task.wait(0.2)
            ca()
            b4()
            b5()
            task.wait(0.1)
            b3()
        end
    end)
end

bE.CharacterAdded:Connect(cf)

if bE.Character then
    task.spawn(cf, bE.Character)
end

task.spawn(function()
    while true do
        if bI and not bF.Multi_IsBuying then
            local cg = bE:FindFirstChild'Backpack'
            local ch = bE.Character

            if cg and ch then
                local ci = cg:GetChildren()

                for cj = 1, #ci do
                    local ck = ci[cj]

                    if ck:IsA'Tool' and bN[ck.Name] then
                        ck.Parent = ch
                    end
                end
            end
        end

        task.wait(0.3)
    end
end)

local cg = function(cg)
    local ch = game.Players.LocalPlayer
    local ci = ch:FindFirstChild'Backpack'
    local cj = ch.Character
    local ck = (ci and ci:FindFirstChild(cg)) or (cj and cj:FindFirstChild(cg))

    if not ck then
        local cl = bF.GetCharacterRoot() and bF.GetCharacterRoot().CFrame

        bF.BuyItem(cg)
        task.wait(0.2)

        if cl then
            bF.GetCharacterRoot().CFrame = cl
        end
    end
end

bt:toggle{
    name = 'enabled',
    flag = 'fgh845yhdg',
    default = false,
    callback = function(ch)
        local ci = H.flags.ghj45yhjg

        if ch then
            getgenv().connectionresolvderfgdg = false
            bF.flamethrower_hack = false
            getgenv().beanbag_method = false

            if ci == 'knife method' then
                cg'[Knife]'

                getgenv().connectionresolvderfgdg = true
                getgenv().hitpedictglueee = true
            elseif ci == 'flamethrower method' then
                cg'[Flamethrower]'

                bF.flamethrower_hack = true
            elseif ci == 'bag method' then
                cg'[BrownBag]'

                getgenv().beanbag_method = true
                getgenv().connectionresolvderfgdg = true
            end
        else
            getgenv().connectionresolvderfgdg = false
            getgenv().hitpedictglueee = false
            getgenv().beanbag_method = false
            bF.flamethrower_hack = false

            local cj = game.Players.LocalPlayer.Character and game.Players.LocalPlayer.Character:FindFirstChild'HumanoidRootPart'

            if cj then
                pcall(function()
                    sethiddenproperty(cj, 'PhysicsRepRootPart', nil)
                end)
            end
        end
    end,
}
bt:dropdown{
    name = 'method',
    flag = 'ghj45yhjg',
    items = {
        'knife method',
        'flamethrower method',
        'bag method',
    },
    default = 'knife method',
    multi = false,
    callback = function(ch)
        if H.flags.fgh845yhdg then
            bF.flamethrower_hack = false
            getgenv().connectionresolvderfgdg = false
            getgenv().beanbag_method = false

            if ch == 'knife method' then
                cg'[Knife]'

                getgenv().connectionresolvderfgdg = true
            elseif ch == 'flamethrower method' then
                cg'[Flamethrower]'

                bF.flamethrower_hack = true
            elseif ch == 'bag method' then
                cg'[BrownBag]'

                getgenv().beanbag_method = true
                getgenv().connectionresolvderfgdg = true
            end
        end
    end,
}
bt:slider{
    name = 'height offset (flamethrower)',
    flag = 'dfgh67hfgh',
    default = 8,
    min = 3,
    suffix = 'x',
    max = 15,
    interval = 0.001,
    callback = function(ch)
        bF.flameOrbitHeight = ch
    end,
}
game:GetService'Players'.LocalPlayer.CharacterAdded:Connect(function(ch)
    bF.IsRespawning = true

    local ci = I and I.auto_sentry or false
    local cj = by.Target.Target

    bF.StopInvis = true

    table.clear(bJ)

    bF.HitPredictRunning = false
    bF.Multi_IsBuying = false
    bP = 0
    bQ = false
    getgenv().ResolvedPosition = nil

    local ck = game.Players.LocalPlayer.Character

    if ck then
        for cl, cm in r(ck:GetDescendants())do
            if cm:IsA'BasePart' or cm:IsA'Decal' then
                cm.LocalTransparencyModifier = 0
            end
        end

        local cl = ck:FindFirstChild'HumanoidRootPart'

        if cl then
            pcall(function()
                sethiddenproperty(cl, 'PhysicsRepRootPart', nil)
            end)

            cl.Velocity = Vector3.new(0, 0, 0)
            cl.RotVelocity = Vector3.new(0, 0, 0)
        end
    end

    local cl = ch:WaitForChild('BodyEffects', 10)

    if cl then
        local cm = cl:FindFirstChild'FULLY_LOADED_CHAR'

        if cm then
            cm.Value = true
        end
    end
    if t(bZ) == 'function' then
        bZ()
    end

    bF.CurrentBuyingItem = nil
    bF.Multi_IsBuying = false
    bF.IsBuying = false
    bF.busdhfnjsy7gjsy7d = false
    bF.IsRespawning = false

    if ci and cj then
        by.Target.Target = cj
        by.Target.AutoKill = true
        bF.StopInvis = false

        task.spawn(function()
            while ch and ch.Parent and by.Target.AutoKill and not bF.StopInvis do
                for cm, cn in r(ch:GetDescendants())do
                    if cn:IsA'BasePart' or cn:IsA'Decal' then
                        cn.LocalTransparencyModifier = 1
                    end
                end

                game:GetService'RunService'.RenderStepped:Wait()
            end
        end)
    end

    task.spawn(function()
        local cm = game.Players.LocalPlayer:WaitForChild('Backpack', 10)

        if not cm then
            return
        end

        task.wait(0.1)

        if t(b2) == 'function' then
            b2()
        end
        if t(b4) == 'function' then
            b4()
        end
        if t(b5) == 'function' then
            b5()
        end
        if by.Target.AutoKill then
            H:notification{
                text = 'reloading all guns please wait',
            }
        end

        task.wait(0.2)

        if I and I.auto_sentry and t(ca) == 'function' then
            ca()
        end

        task.wait(0.2)

        if bI then
            b3()
            task.wait(0.1)

            for cn, co in q(bJ)do
                if co and co.Parent == ch then
                    bw:FireServer('Reload', co)
                end
            end
        end
    end)
end)

bF.SoundService = game:GetService'SoundService'
bF.HttpService = game:GetService'HttpService'
bF.folderPath = 'sample-songs'

if not isfolder(bF.folderPath) then
    makefolder(bF.folderPath)
end

bF.songs = {
    {
        name = 'Tame Impala - One More Hour',
        file = 'One More Hour.mp3',
        url = 'https://pomf2.lain.la/f/s8k21saj.mp3',
    },
    {
        name = 'Trippie Redd - Wish',
        file = 'Wishtrp.mp3',
        url = 'https://pomf2.lain.la/f/ytgag6nr.mp3',
    },
    {
        name = 'Kate Bush - Running Up That Hill',
        file = 'maxfromstrangerthingssongah.mp3',
        url = 'https://cdn.getsample.lol/4n3jkiqw',
    },
    {
        name = 'Xxx & Trippie - Fuck Love',
        file = 'Fuhlve.mp3',
        url = 'https://pomf2.lain.la/f/v1v8je0j.mp3',
    },
    {
        name = 'Chris Grey - LET THE WORLD BURN',
        file = 'tiktokahedit.mp3',
        url = 'https://cdn.getsample.lol/lsgkdiry',
    },
    {
        name = 'Djo - End of Beggining',
        file = 'stevefromstrangerthings.mp3',
        url = 'https://cdn.getsample.lol/64swey4v',
    },
    {
        name = 'Miss Me',
        file = 'MissMe.mp3',
        url = 'https://github.com/NewbieScripter-web/mp3/raw/refs/heads/main/MissMe.mp3',
    },
    {
        name = 'Lil Peep - Nuts',
        file = 'Nuts.mp3',
        url = 'https://pomf2.lain.la/f/3rp08d8.mp3',
    },
    {
        name = 'Somewhere Only We Know',
        file = 'Somewhere.mp3',
        url = 'https://pomf2.lain.la/f/v4kygzal.mp3',
    },
    {
        name = 'Headlock x Headlock',
        file = 'Headlock.mp3',
        url = 'https://pomf2.lain.la/f/uwr5n4vz.mp3',
    },
    {
        name = 'King Von - Anti Piracy',
        file = 'AntiPiracyKing.mp3',
        url = 'https://pomf2.lain.la/f/5xltbwdx.mp3',
    },
    {
        name = 'xaviersobased - in the yo',
        file = 'in_the_yo.mp3',
        url = 'https://pomf2.lain.la/f/dfdqazh.mp3',
    },
    {
        name = 'Ken Carson - margiela',
        file = 'margiela.mp3',
        url = 'https://pomf2.lain.la/f/e2zpwgt3.mp3',
    },
    {
        name = 'Ken Carson - ss',
        file = 'ss.mp3',
        url = 'https://pomf2.lain.la/f/s3jb1j5g.mp3',
    },
    {
        name = 'Scars',
        file = 'scrs.mp3',
        url = 'https://cdn.getsample.lol/3f4mufoc',
    },
    {
        name = 'Ken Carson - Fighting My Demons',
        file = 'Fighting_My_Demons.mp3',
        url = 'https://pomf2.lain.la/f/zwhwa8z2.mp3',
    },
    {
        name = 'Playboi Carti - EVIL J0RDAN',
        file = 'EVIL_J0RDAN.mp3',
        url = 'https://pomf2.lain.la/f/yg82v42f.mp3',
    },
    {
        name = 'Playboi Carti - Timeless',
        file = 'Timeless.mp3',
        url = 'https://pomf2.lain.la/f/dd43lkk3.mp3',
    },
    {
        name = "Skepta - That's Not Me",
        file = 'Thats_Not_Me.mp3',
        url = 'https://pomf2.lain.la/f/t8qdrudt.mp3',
    },
}
bF.currentSound = nil
bF.currentSongIndex = 1
bF.isPlaying = false
bF.musicVolume = 5
bF.getFilePath = function(ch)
    return bF.folderPath .. '/' .. ch.file
end
bF.downloadSong = function(ch)
    local ci = bF.getFilePath(ch)

    if isfile(ci) then
        return ci
    end

    local cj, ck = pcall(function()
        return game:HttpGet(ch.url, true)
    end)

    if cj and ck and #ck > 10000 then
        writefile(ci, ck)

        return ci
    end

    return nil
end
bF.preloadAllSongs = function()
    for ch, ci in q(bF.songs)do
        task.spawn(function()
            bF.downloadSong(ci)
        end)
    end
end
bF.playCurrentSong = function()
    if #bF.songs == 0 then
        H:notification{
            text = 'no songs available',
        }

        return
    end

    local ch = bF.songs[bF.currentSongIndex]

    if bF.currentSound then
        bF.currentSound:Stop()
        bF.currentSound:Destroy()

        bF.currentSound = nil
    end

    local ci = bF.downloadSong(ch)

    if not ci then
        H:notification{
            text = 'fail (download issue)',
        }

        return
    end

    local cj
    local ck, cl = pcall(function()
        return getsynasset(ci)
    end)

    if ck and cl then
        cj = cl
    else
        local cm, cn = pcall(function()
            return getcustomasset(ci)
        end)

        if cm and cn then
            cj = cn
        end
    end
    if not cj then
        H:notification{
            text = 'failed to load asset (executor issue)',
        }

        return
    end

    bF.currentSound = Instance.new'Sound'
    bF.currentSound.Name = 'MusicPlayer'
    bF.currentSound.SoundId = cj
    bF.currentSound.Volume = bF.musicVolume / 10
    bF.currentSound.Looped = false
    bF.currentSound.Parent = bF.SoundService

    bF.currentSound.Ended:Connect(function()
        bF.isPlaying = false
        bF.currentSongIndex = bF.currentSongIndex + 1

        if bF.currentSongIndex > #bF.songs then
            bF.currentSongIndex = 1
        end

        task.wait(1)
        bF.playCurrentSong()
    end)
    bF.currentSound:Play()

    bF.isPlaying = true

    H:notification{
        text = 'playing: ' .. ch.name,
    }
end
bF.stopMusic = function()
    if bF.currentSound then
        bF.currentSound:Stop()
        bF.currentSound:Destroy()

        bF.currentSound = nil
    end

    bF.isPlaying = false

    H:notification{
        text = 'music stopped',
    }
end
bF.nextSong = function()
    bF.currentSongIndex = bF.currentSongIndex + 1

    if bF.currentSongIndex > #bF.songs then
        bF.currentSongIndex = 1
    end
    if bF.isPlaying then
        bF.playCurrentSong()
    end
end
bF.songNames = {}

for ch, ci in q(bF.songs)do
    table.insert(bF.songNames, ci.name)
end
