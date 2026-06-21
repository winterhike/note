--======================================================================
-- $$ banknote $$  -  REDLINER (universe 7265339759)  [NATIVE + ACTOR]
--
-- REDLINER runs its client controllers inside game Actors (separate Luau
-- VMs); on the main thread ClientRoot.Classes is empty, so controller-based
-- features can't work here. Like Vape, the feature logic must run on a game
-- actor (redliner/actor.lua). The banknote UI stays on the main thread and
-- can't share Lua tables across VMs, so feature state is bridged through
-- Attributes on a shared DataModel instance.
--
-- This file: builds the banknote UI, mirrors every control onto bridge
-- attributes, spawns the actor runtime, and natively handles the two
-- features that need no controllers (Timer, StaffDetector).
--
-- Marker for the loader: BanknoteLibrary
--======================================================================
if getgenv()._RedlinerLoaded then return end
getgenv()._RedlinerLoaded = true

local BN = getgenv().BanknoteLibrary
assert(BN, "[banknote] BanknoteLibrary not set by loader")

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local lplr = Players.LocalPlayer

local function log(...) print("[banknote/REDLINER]", ...) end
local function notify(msg) pcall(function() BN:Notification(tostring(msg), 5) end) end

local BASE = "https://raw.githubusercontent.com/endmylifehahahahahahahahaha/banknote-hub/refs/heads/master/"
do
    local ok, body = pcall(function()
        return game:HttpGet("https://api.github.com/repos/endmylifehahahahahahahahaha/banknote-hub/commits/master")
    end)
    if ok and type(body) == "string" then
        local sha = body:match('"sha"%s*:%s*"(%x+)"')
        if sha then
            BASE = "https://raw.githubusercontent.com/endmylifehahahahahahahahaha/banknote-hub/" .. sha .. "/"
            log("pinned to commit", sha:sub(1, 7))
        end
    end
end

--======================================================================
-- shared bridge (Attributes cross the main<->actor VM boundary)
--======================================================================
local BRIDGE_NAME = "BanknoteRedlinerBridge"
local bridge = ReplicatedStorage:FindFirstChild(BRIDGE_NAME)
if bridge then bridge:Destroy() end
bridge = Instance.new("Configuration")
bridge.Name = BRIDGE_NAME
bridge.Parent = ReplicatedStorage

local function setState(name, v) pcall(function() bridge:SetAttribute(name, v) end) end
local function setOpt(name, opt, v) pcall(function() bridge:SetAttribute(name .. "_" .. opt, v) end) end

--======================================================================
-- banknote window + UI framework (mirrors controls -> bridge attributes)
--======================================================================
local window = BN:Window({ Name = "$$ banknote: REDLINER $$" })
pcall(function() window:Watermark({ Name = "$$ banknote $$" }) end)
pcall(function() window:KeybindList() end)

local pages, sideCounter = {}, {}
local function getPage(name)
    if not pages[name] then pages[name] = window:Page({ Name = name }) sideCounter[name] = 0 end
    return pages[name]
end
local function nextSide(name) sideCounter[name] = (sideCounter[name] or 0) + 1 return ((sideCounter[name] % 2) == 1) and 1 or 2 end

local flagN = 0
local function uflag() flagN = flagN + 1 return "rl_" .. flagN end

local features = {}

-- Feature: section + Enabled toggle (+keybind) that writes bridge[name];
-- onLocal (optional) runs the feature on the MAIN thread (Timer/StaffDetector).
local function Feature(category, name, onLocal)
    local section = getPage(category):Section({ Name = name, Side = nextSide(category) })
    local self = { Name = name, Enabled = false, Section = section, cleans = {} }
    setState(name, false)

    function self:Clean(c) table.insert(self.cleans, c) return c end
    local function disconnect()
        for _, c in ipairs(self.cleans) do
            pcall(function()
                if typeof(c) == "RBXScriptConnection" then c:Disconnect()
                elseif type(c) == "table" and c.Disconnect then c:Disconnect()
                elseif typeof(c) == "Instance" then c:Destroy() end
            end)
        end
        table.clear(self.cleans)
    end

    local function setEnabled(v)
        v = v and true or false
        if self.Enabled == v then return end
        self.Enabled = v
        setState(name, v)
        if onLocal then
            if v then task.spawn(function() pcall(onLocal, self, true) end)
            else pcall(onLocal, self, false) disconnect() end
        end
    end
    self.setEnabled = setEnabled

    self.toggle = section:Toggle({ Name = "Enabled", Flag = uflag(), Default = false, Callback = setEnabled })
    if self.toggle and self.toggle.Keybind then
        pcall(function()
            self.toggle:Keybind({ Name = name, Flag = uflag(), Mode = "Toggle",
                -- use the value the keybind computes from its mode (Toggle/Hold/Always);
                -- do NOT flip independently or Hold/Always break.
                Callback = function(toggled)
                    setEnabled(toggled and true or false)
                    if self.toggle.Set then pcall(function() self.toggle:Set(self.Enabled) end) end
                end })
        end)
    end

    -- mirror an actor-initiated disable (HighJump/LongJump self-off) back to the toggle
    bridge:GetAttributeChangedSignal(name):Connect(function()
        if bridge:GetAttribute(name) == false and self.Enabled then
            self.Enabled = false
            if self.toggle and self.toggle.Set then pcall(function() self.toggle:Set(false) end) end
            if onLocal then disconnect() end
        end
    end)

    function self:Slider(d)
        setOpt(name, d.Opt, d.Default or d.Min or 0)
        local obj
        pcall(function()
            obj = section:Slider({ Name = d.Name, Flag = uflag(), Min = d.Min or 0, Max = d.Max or 100, Default = d.Default or d.Min or 0,
                Decimals = (d.Decimal and d.Decimal > 0) and (1 / d.Decimal) or 1, Suffix = type(d.Suffix) == "string" and d.Suffix or "",
                Callback = function(val) setOpt(name, d.Opt, val) end })
        end)
        return obj
    end
    function self:Toggle(d)
        setOpt(name, d.Opt, d.Default or false)
        local obj
        pcall(function()
            obj = section:Toggle({ Name = d.Name, Flag = uflag(), Default = d.Default or false,
                Callback = function(v) setOpt(name, d.Opt, v) end })
        end)
        return obj
    end
    function self:Dropdown(d)
        setOpt(name, d.Opt, d.Default)
        local obj
        pcall(function()
            obj = section:Dropdown({ Name = d.Name, Flag = uflag(), Items = d.Items or {}, Default = d.Default, Multi = false,
                Callback = function(v) setOpt(name, d.Opt, v) if d.OnChange then pcall(d.OnChange, v) end end })
        end)
        return obj
    end
    function self:Targets(d)
        d = d or {}
        self:Toggle({ Name = "Target Players", Opt = "Players", Default = d.Players and true or false })
        self:Toggle({ Name = "Target NPCs", Opt = "NPCs", Default = false })
        if d.Walls then self:Toggle({ Name = "Wall Check", Opt = "Walls", Default = false }) end
    end

    features[name] = self
    return self
end

--======================================================================
-- UI definitions (must match the attribute names the actor reads)
--======================================================================
-- Combat
do
    local KA = Feature("Combat", "KillAura")
    KA:Targets({ Players = true })
    KA:Slider({ Name = "Attack range", Opt = "AttackRange", Min = 1, Max = 40, Default = 40, Suffix = "m" })
    KA:Slider({ Name = "Max angle", Opt = "MaxAngle", Min = 1, Max = 360, Default = 360 })
    KA:Toggle({ Name = "Auto Swing", Opt = "AutoSwing", Default = true })

    local SA = Feature("Combat", "SilentAim")
    SA:Targets({ Players = true })
    SA:Slider({ Name = "Range", Opt = "Range", Min = 1, Max = 1000, Default = 150, Suffix = "m" })
    SA:Slider({ Name = "Hit Chance", Opt = "HitChance", Min = 0, Max = 100, Default = 85, Suffix = "%" })

    local RB = Feature("Combat", "RageBot")
    RB:Targets({ Players = true })
    RB:Slider({ Name = "Range", Opt = "Range", Min = 1, Max = 1000, Default = 200, Suffix = "m" })
    RB:Slider({ Name = "Swing Delay", Opt = "SwingDelay", Min = 0.05, Max = 1, Decimal = 100, Default = 0.1, Suffix = "s" })
end
-- Blatant
do
    local AS = Feature("Blatant", "AlwaysStun")
    AS:Slider({ Name = "Spoof value", Opt = "Spoof", Min = 300, Max = 800, Default = 800, Suffix = "sps" })

    local GC = Feature("Blatant", "GrapplerCooldown")
    GC:Slider({ Name = "Cooldown", Opt = "Cooldown", Min = 0, Max = 1, Decimal = 100, Default = 1 })

    Feature("Blatant", "AntiParry")
    Feature("Blatant", "AutoParry")

    local FL = Feature("Blatant", "Fly")
    FL:Slider({ Name = "Speed", Opt = "Speed", Min = 1, Max = 150, Default = 50, Suffix = "m" })
    FL:Slider({ Name = "Vertical Speed", Opt = "VerticalSpeed", Min = 1, Max = 150, Default = 50, Suffix = "m" })

    local HJ = Feature("Blatant", "HighJump")
    HJ:Slider({ Name = "Velocity", Opt = "Velocity", Min = 1, Max = 150, Default = 50 })

    local LJ = Feature("Blatant", "LongJump")
    LJ:Slider({ Name = "Speed", Opt = "Speed", Min = 1, Max = 150, Default = 50, Suffix = "m" })
    LJ:Toggle({ Name = "Auto Disable", Opt = "AutoDisable", Default = true })

    local SP = Feature("Blatant", "Speed")
    SP:Slider({ Name = "Speed", Opt = "Speed", Min = 1, Max = 150, Default = 100, Suffix = "m" })
    SP:Toggle({ Name = "AutoJump", Opt = "AutoJump", Default = false })
    SP:Toggle({ Name = "Custom Jump", Opt = "CustomJump", Default = false })
    SP:Slider({ Name = "Jump Power", Opt = "JumpPower", Min = 1, Max = 50, Default = 30 })

    local TS = Feature("Blatant", "TargetStrafe")
    TS:Targets({ Players = true, Walls = true })
    local v2elems = {}
    local function setV2Visible(show)
        for _, e in pairs(v2elems) do
            if e and e.SetVisibility then pcall(function() e:SetVisibility(show) end) end
        end
    end
    TS:Dropdown({ Name = "Version", Opt = "Version", Items = { "v1", "v2" }, Default = "v1",
        OnChange = function(val) setV2Visible(val == "v2") end })
    TS:Slider({ Name = "Search Range", Opt = "SearchRange", Min = 1, Max = 100, Default = 24, Suffix = "m" })
    TS:Slider({ Name = "Strafe Range", Opt = "StrafeRange", Min = 1, Max = 30, Default = 18, Suffix = "m" })
    TS:Slider({ Name = "Y Factor", Opt = "YFactor", Min = 0, Max = 100, Default = 100, Suffix = "%" })
    -- v2-only options (shown only when Version == v2)
    v2elems.priority = TS:Dropdown({ Name = "Priority (v2)", Opt = "Priority", Items = { "Closest Distance", "Lowest HP", "First Target" }, Default = "Closest Distance" })
    v2elems.sticky = TS:Toggle({ Name = "Sticky (v2)", Opt = "Sticky", Default = false })
    v2elems.orbit  = TS:Slider({ Name = "Orbit Speed (v2)", Opt = "Speed", Min = 1, Max = 250, Default = 60, Suffix = "m" })
    v2elems.rot    = TS:Slider({ Name = "Rotation Speed (v2)", Opt = "RotationSpeed", Min = 1, Max = 40, Default = 12 })
    v2elems.pred   = TS:Slider({ Name = "Prediction (v2)", Opt = "Prediction", Min = 0, Max = 1, Decimal = 100, Default = 0 })
    setV2Visible(false) -- hidden by default (v1 selected)
end
-- Utility
do
    local AQ = Feature("Utility", "AutoQueue")
    local queueList = { "Duels1v1", "Ranked1v1", "FFA", "Duels2v2" }
    AQ:Dropdown({ Name = "Mode", Opt = "Mode", Items = queueList, Default = "Duels1v1" })

    local AL = Feature("Utility", "AutoLeave", function(self, on)
        if not on then return end
        local fired = false
        self:Clean(RunService.Heartbeat:Connect(function()
            if fired then return end
            local pg = lplr:FindFirstChild("PlayerGui")
            if not pg then return end
            for _, d in pg:GetDescendants() do
                if (d:IsA("TextButton") or d:IsA("ImageButton")) and d.Name:lower():find("return") and d.Visible then
                    fired = true
                    task.wait(bridge:GetAttribute("AutoLeave_Delay") or 1)
                    pcall(function() firesignal(d.MouseButton1Click) end)
                    break
                end
            end
        end))
    end)
    AL:Slider({ Name = "Delay", Opt = "Delay", Min = 0, Max = 5, Default = 1, Decimal = 10, Suffix = "s" })

    Feature("Utility", "Phase")

    -- Timer (native, main thread): live stopwatch in the section title
    Feature("Utility", "Timer", function(self, on)
        if on then
            local start = os.clock()
            self:Clean(RunService.Heartbeat:Connect(function()
                local t = os.clock() - start
                pcall(function() self.Section:SetText(("Timer  %02d:%02d"):format(math.floor(t / 60), math.floor(t % 60))) end)
            end))
        else
            pcall(function() self.Section:SetText("Timer") end)
        end
    end)

    -- StaffDetector (native, main thread): flag REDLINER group staff in server
    do
        local SD = Feature("Utility", "StaffDetector", function(self, on)
            if not on then return end
            local GROUP = 35646671
            local function check(plr)
                if plr == lplr then return end
                task.spawn(function()
                    local ok, rank = pcall(function() return plr:GetRankInGroup(GROUP) end)
                    if ok and type(rank) == "number" and rank >= 50 then
                        notify("Staff in server: " .. plr.Name .. " (rank " .. rank .. ")")
                    end
                end)
            end
            for _, p in Players:GetPlayers() do check(p) end
            self:Clean(Players.PlayerAdded:Connect(check))
        end)
    end
end

pcall(function() window:Init() end)

-- $$ banknote $$: clean first run. Library:Init auto-applies autoload.json, and
-- our per-run flags are randomized so a stale config maps onto the wrong toggles.
-- Force every feature OFF after the UI is built so nothing comes pre-enabled.
task.defer(function()
    for _, m in pairs(features) do
        if type(m) == "table" and m.setEnabled then
            pcall(function() m.setEnabled(false) end)
            if m.toggle and m.toggle.Set then pcall(function() m.toggle:Set(false) end) end
        end
        if type(m) == "table" then pcall(function() bridge:SetAttribute(m.Name, false) end) end
    end
end)

--======================================================================
-- spawn the actor runtime (where REDLINER's controllers actually live)
--======================================================================
local function runOnActor(src)
    -- dispatch to ALL actors; the payload self-gates so only the actor that
    -- actually holds REDLINER's live controllers claims the bridge & runs.
    local dispatched = false
    if getactorthreads and run_on_thread then
        for _, v in getactorthreads() do pcall(function() run_on_thread(v, src) dispatched = true end) end
    end
    if getactorstates then
        for _, v in getactorstates() do
            if type(v) ~= "thread" then pcall(function() v:Execute(src) dispatched = true end) end
        end
    end
    if not dispatched then
        local getter = getactors or getdeletedactors
        if getter and run_on_actor then
            for _, v in getter() do pcall(function() run_on_actor(v, src) dispatched = true end) end
        end
    end
    return dispatched
end

task.spawn(function()
    if not (run_on_actor or run_on_thread or getactorstates) then
        notify("REDLINER: executor lacks actor support; features need it")
        return
    end
    local okE, entitySrc = pcall(function() return game:HttpGet(BASE .. "redliner/entity.lua") end)
    local okA, actorSrc = pcall(function() return game:HttpGet(BASE .. "redliner/actor.lua") end)
    if not (okE and okA) then
        notify("REDLINER: failed to fetch actor runtime")
        return
    end
    local payload = ("local __RL_BRIDGE = %q\nlocal __RL_ENTITY_SRC = %q\n%s"):format(BRIDGE_NAME, entitySrc, actorSrc)
    if runOnActor(payload) then
        log("actor runtime dispatched")
    else
        notify("REDLINER: no usable actor found")
    end
end)

-- surface the actor's discovery result on screen
do
    local last
    bridge:GetAttributeChangedSignal("__status"):Connect(function()
        local s = bridge:GetAttribute("__status")
        if s and s ~= last then last = s log("actor:", s) if tostring(s):find("ready") or tostring(s):find("fail") then notify("REDLINER " .. tostring(s)) end end
    end)
end

--======================================================================
-- cleanup
--======================================================================
local function unloadAll()
    for _, m in pairs(features) do
        if type(m) == "table" and m.Enabled and m.setEnabled then pcall(function() m.setEnabled(false) end) end
    end
    -- stop every actor feature, then tear down the bridge
    pcall(function()
        for _, name in ipairs({ "KillAura","SilentAim","RageBot","AlwaysStun","GrapplerCooldown","AntiParry","AutoParry","Fly","HighJump","LongJump","Speed","TargetStrafe","AutoQueue","Phase" }) do
            bridge:SetAttribute(name, false)
        end
    end)
    task.delay(0.5, function() pcall(function() bridge:Destroy() end) end)
    getgenv()._RedlinerLoaded = nil
end

do
    local realExit = BN.Exit
    if realExit then
        BN.Exit = function(self, ...) unloadAll() return realExit(self, ...) end
    end
    BN.OnUnload = unloadAll
end

notify("REDLINER loaded into banknote")
