--======================================================================
-- $$ banknote $$  -  REDLINER (universe 7265339759)  [NATIVE]
--
-- Native banknote integration of the REDLINER combat/movement features.
-- This does NOT run Vape's framework or a shared.vape shim: the game-side
-- logic (controller discovery, hitbox hook, packet/velocity manipulation)
-- is ported directly, and every feature is wired straight into banknote's
-- own UI library. The only reused Vape file is the self-contained entity
-- tracking library (redliner/entity.lua), used purely as a target source.
--
-- Feature mechanism reference: VapeV4ForRoblox (fork-friendly).
-- Marker for the loader: BanknoteLibrary
--======================================================================
if getgenv()._RedlinerLoaded then return end
getgenv()._RedlinerLoaded = true

local BN = getgenv().BanknoteLibrary
assert(BN, "[banknote] BanknoteLibrary not set by loader")

local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local CollectionService  = game:GetService("CollectionService")
local TextChatService    = game:GetService("TextChatService")
local TeleportService    = game:GetService("TeleportService")

local lplr   = Players.LocalPlayer
local camera = workspace.CurrentCamera

local function log(...) print("[banknote/REDLINER]", ...) end
local function notify(msg) pcall(function() BN:Notification(tostring(msg), 5) end) end

-- pin asset fetches to the latest commit (CDN ignores ?_= on master)
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
-- entity/target library (self-contained Vape lib, no shim dependency)
--======================================================================
local entitylib
do
    local ok, lib = pcall(function()
        return loadstring(game:HttpGet(BASE .. "redliner/entity.lua"))()
    end)
    if ok and type(lib) == "table" then
        entitylib = lib
        log("entity library loaded")
    else
        warn("[banknote/REDLINER] entity library failed:", lib)
        notify("REDLINER: entity library failed to load")
        return
    end
end

--======================================================================
-- REDLINER internals discovery (ported)
--======================================================================
local redline = { Teams = {} }
local starttime = os.clock()
local TargetStrafeVector

local function searchForPacket(func, unreliable)
    for _, v in debug.getconstants(func) do
        if rawget(unreliable and redline.Packets.unreliablePackets or redline.Packets, v) then
            return v
        end
    end
end

local function getIndicators()
    return redline[redline.IndicatorController] and redline[redline.IndicatorController][redline.IndicatorTable] or {}
end

local discovered = false

local function runDiscovery()
    local root
    for _, v in getloadedmodules() do
        if v:GetFullName() == 'Start.Client.ClientRoot' then
            root = require(v)
            -- wait (capped) for the game to init this instance
            local deadline = tick() + 8
            while not rawget(root, 'loaded') and tick() < deadline do
                task.wait()
            end
        end
    end
    if not root then
        warn("[banknote/REDLINER] ClientRoot not found")
        return false
    end

    -- Resolve the live Classes table. require usually returns the populated
    -- instance; if it didn't (empty), scan getgc for the real populated one.
    local function count(t) local n=0 if type(t)=='table' then for _ in pairs(t) do n+=1 end end return n end
    local liveClasses = rawget(root, 'Classes')
    if count(liveClasses) == 0 and type(getgc) == 'function' then
        for _, o in getgc(true) do
            if type(o) == 'table' and o ~= root then
                local ok = pcall(function()
                    return type(rawget(o,'Classes'))=='table' and rawget(o,'Init')~=nil and rawget(o,'Context')~=nil
                end)
                if ok and type(rawget(o,'Classes'))=='table' and count(rawget(o,'Classes')) > 0 then
                    liveClasses = rawget(o, 'Classes')
                    if rawget(o,'loaded') == true then break end
                end
            end
        end
    end
    redline = setmetatable({
        AttackBox = require(ReplicatedStorage.Assets.ModuleScripts.Attack),
        AttackCast = require(ReplicatedStorage.Assets.ModuleScripts.Attack.Hitbox),
        CEnum = require(ReplicatedStorage.Assets.ModuleScripts.CEnum),
        Packets = require(ReplicatedStorage.Assets.ModuleScripts.Packets),
        Packet = debug.getupvalue(getrawmetatable(require(ReplicatedStorage.Assets.ModuleScripts.Packets.Packet)).__call, 2),
        Util = require(ReplicatedStorage.Assets.SharedClasses.Util),
        Teams = redline.Teams
    }, {
        __index = function(self, ind)
            return rawget(liveClasses, ind)
        end
    })

    local dumplist = {
        Constants = {
            ShootFunction = function(constants, func, inst)
                for _, const in constants do
                    if const == 'ViewportPointToRay' then
                        redline.ShootFunction = require(inst)[debug.info(func, 'n')]
                        break
                    end
                end
            end,
            ActionController = function(constants, func, inst)
                for _, const in constants do
                    if const == 'getAction FAILED FOR : ' then
                        redline.ActionController = inst.Name
                        redline.ActionFunction = require(inst)[debug.info(func, 'n')]
                        break
                    end
                end
            end,
            IndicatorController = function(constants, func, inst)
                for _, const in constants do
                    if const == 'INVALID crosshair_name : ' then
                        redline.IndicatorController = inst.Name
                        break
                    end
                end
            end,
            ReplicateFunction = function(constants, func, inst)
                for _, const in constants do
                    if const == 'Message cannot be empty' then
                        redline.ReplicateFunction = require(inst)[debug.info(func, 'n')]
                        break
                    end
                end
            end,
            MoveController = function(constants, func, inst)
                for _, const in constants do
                    if const == 'getMoveDirection' then
                        local found = {}
                        for _, const2 in constants do
                            if tostring(const2):find('_') then
                                table.insert(found, const2)
                            end
                        end
                        redline.MoveController = found[1]
                        redline.VelocityName = found[2]
                        break
                    end
                end
            end,
            ActionEventPacket = function(constants, func, inst)
                local found
                for _, const in constants do
                    if const == 'OnClientEvent' then
                        found = true
                    elseif const == 'onKill' and found then
                        redline.ActionEventPacket = searchForPacket(func, true)
                        if redline.ActionEventPacket then
                            redline.ActionEventPacket = redline.Packets.unreliablePackets[redline.ActionEventPacket]
                        end
                        break
                    end
                end
            end
        },
        Protos = {
            AttackPacket = function(protos, func, inst)
                for _, proto in protos do
                    if debug.info(proto, 'n') == 'redlinerMelee' then
                        redline.AttackPacket = searchForPacket(debug.getproto(debug.getproto(proto, 1), 1))
                        if redline.AttackPacket then
                            redline.AttackPacket = redline.Packets[redline.AttackPacket].Name
                        end
                        break
                    end
                end
            end,
            IndicatorTable = function(protos, func, inst)
                for _, proto in protos do
                    if debug.info(proto, 'n') == 'removeShotIndicator' then
                        for _, const in debug.getconstants(proto) do
                            if tostring(const):find('_') then
                                redline.IndicatorTable = const
                                break
                            end
                        end
                        break
                    end
                end
            end
        }
    }

    for _, v in getscripts() do
        if v:GetFullName():sub(1, 5) == 'Start' and v:IsA('ModuleScript') then
            local closure = getscriptclosure(v)
            local protos = debug.getprotos(closure)
            if protos[1] then
                if debug.info(protos[1], 'l') == 3 and #debug.info(protos[1], 'n') <= 2 then
                    continue
                end
            end
            for _, func in debug.getprotos(closure) do
                for name, callback in dumplist.Constants do
                    if not redline[name] then
                        pcall(callback, debug.getconstants(func), func, v)
                    end
                end
                for name, callback in dumplist.Protos do
                    if not redline[name] then
                        pcall(callback, debug.getprotos(func), func, v)
                    end
                end
            end
        end
    end

    -- validate / auto-detect the velocity field on the live move controller:
    -- the heuristic above can pick the wrong constant, which silently kills
    -- every movement feature (their Vector3 gate fails). If the named field
    -- isn't a Vector3, find the controller's actual Vector3 field.
    do
        local mc = redline.MoveController and redline[redline.MoveController]
        if type(mc) == 'table' then
            local cur = redline.VelocityName and rawget(mc, redline.VelocityName)
            if typeof(cur) ~= 'Vector3' then
                for k, val in pairs(mc) do
                    if typeof(val) == 'Vector3' then
                        redline.VelocityName = k
                        break
                    end
                end
            end
        end
    end

    discovered = true
    if getgenv then getgenv().__redline = redline end

    local liveAction = redline.ActionController and redline[redline.ActionController]
    local liveMove   = redline.MoveController and redline[redline.MoveController]
    local velType = 'n/a'
    if type(liveMove) == 'table' then
        local ok, v = pcall(function() return liveMove[redline.VelocityName] end)
        velType = ok and typeof(v) or 'err'
    end
    log(("ready: Action=%s Move=%s Vel=%s Shoot=%s AttackPacket=%s")
        :format(tostring(liveAction ~= nil), tostring(liveMove ~= nil), velType,
                tostring(redline.ShootFunction ~= nil), tostring(redline.AttackPacket ~= nil)))
    return true
end

--======================================================================
-- HitboxHook: intercept the melee hitbox scan so KillAura/AntiParry can
-- add/remove hit targets. redline.AttackBox is the shared Attack module,
-- so castOnce here is the real function the game calls.
--======================================================================
local HitboxHook = { Hooks = {} }
do
    local oldscan
    local function Hook(...)
        local results = table.pack(oldscan(...))
        for _, v in HitboxHook.Hooks do
            local ok, ret = pcall(v[2], results)
            if ok and ret then return {} end
        end
        return unpack(results, 1, results.n)
    end
    function HitboxHook:Add(key, val, priority)
        table.insert(self.Hooks, { key, val, priority or 0 })
        table.sort(self.Hooks, function(a, b) return a[3] < b[3] end)
        if not oldscan then
            oldscan = hookfunction(redline.AttackBox.castOnce, function(...) return Hook(...) end)
        end
    end
    function HitboxHook:Remove(key)
        for i, v in self.Hooks do
            if v[1] == key then table.remove(self.Hooks, i) break end
        end
        if oldscan and not next(self.Hooks) then
            if restorefunction then restorefunction(redline.AttackBox.castOnce)
            else hookfunction(redline.AttackBox.castOnce, oldscan) end
            oldscan = nil
        end
    end
end

--======================================================================
-- banknote window + native feature framework
--======================================================================
local window = BN:Window({ Name = "$$ banknote: REDLINER $$" })
pcall(function() window:Watermark({ Name = "$$ banknote $$" }) end)
pcall(function() window:KeybindList() end)

local pages, sideCounter = {}, {}
local function getPage(name)
    if not pages[name] then
        pages[name] = window:Page({ Name = name })
        sideCounter[name] = 0
    end
    return pages[name]
end
local function nextSide(name)
    sideCounter[name] = (sideCounter[name] or 0) + 1
    return ((sideCounter[name] % 2) == 1) and 1 or 2
end

local flagN = 0
local function uflag() flagN = flagN + 1 return "rl_" .. flagN end

local allFeatures = {}

-- Feature object: owns a banknote section, an Enabled toggle (+keybind), a
-- cleanup list, and forwards the enabled state to the supplied onToggle.
local function Feature(category, name, onToggle, tooltip)
    local page = getPage(category)
    local section = page:Section({ Name = name, Side = nextSide(category) })
    local self = { Name = name, Enabled = false, Section = section, cleans = {} }

    function self:Clean(c) table.insert(self.cleans, c) return c end
    local function disconnectCleans()
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
        if v then
            task.spawn(function() pcall(onToggle, self, true) end)
        else
            pcall(onToggle, self, false)
            disconnectCleans()
        end
    end
    self.setEnabled = setEnabled

    self.toggle = section:Toggle({
        Name = "Enabled", Flag = uflag(), Default = false,
        Callback = function(v) setEnabled(v) end,
    })
    -- native banknote keybind (Toggle / Hold / Always selectable in its UI)
    if self.toggle and self.toggle.Keybind then
        pcall(function()
            self.toggle:Keybind({
                Name = name, Flag = uflag(), Mode = "Toggle",
                Callback = function(active)
                    setEnabled(active and true or false)
                    if self.toggle.Set then pcall(function() self.toggle:Set(self.Enabled) end) end
                end,
            })
        end)
    end

    function self:Slider(d)
        local obj = { Value = d.Default or d.Min or 0 }
        pcall(function()
            section:Slider({
                Name = d.Name, Flag = uflag(), Min = d.Min or 0, Max = d.Max or 100,
                Default = obj.Value, Decimals = (d.Decimal and d.Decimal > 0) and (1 / d.Decimal) or 1,
                Suffix = type(d.Suffix) == "string" and d.Suffix or "",
                Callback = function(val) obj.Value = val if d.Callback then pcall(d.Callback, val) end end,
            })
        end)
        return obj
    end
    function self:Toggle(d)
        local obj = { Enabled = d.Default or false }
        pcall(function()
            section:Toggle({
                Name = d.Name, Flag = uflag(), Default = obj.Enabled,
                Callback = function(v) obj.Enabled = v if d.Callback then pcall(d.Callback, v) end end,
            })
        end)
        return obj
    end
    function self:Dropdown(d)
        local obj = { Value = d.Default }
        pcall(function()
            section:Dropdown({
                Name = d.Name, Flag = uflag(), Items = d.Items or {}, Default = obj.Value, Multi = false,
                Callback = function(v) obj.Value = v if d.Callback then pcall(d.Callback, v) end end,
            })
        end)
        return obj
    end
    function self:Targets(d)
        d = d or {}
        local t = { Players = { Enabled = d.Players and true or false }, NPCs = { Enabled = false }, Walls = { Enabled = false } }
        self:Toggle({ Name = "Target Players", Default = t.Players.Enabled, Callback = function(v) t.Players.Enabled = v end })
        self:Toggle({ Name = "Target NPCs", Default = false, Callback = function(v) t.NPCs.Enabled = v end })
        if d.Walls then
            self:Toggle({ Name = "Wall Check", Default = false, Callback = function(v) t.Walls.Enabled = v end })
        end
        return t
    end

    allFeatures[name] = self
    return self
end

local function restoreHook(target, old)
    if not old then return end
    if restorefunction then restorefunction(target) else hookfunction(target, old) end
end

--======================================================================
-- features (built after discovery so redline internals are available)
--======================================================================
local function buildFeatures()
    ------------------------------------------------------------------ KillAura
    do
        local Targets, AttackRange, AngleSlider, AutoSwing
        local Overlay = OverlapParams.new()
        Overlay.FilterType = Enum.RaycastFilterType.Include
        Overlay.RespectCanCollide = false
        local parryAnims = {}
        local pa = ReplicatedStorage.Assets.Animations:FindFirstChild('3P_Parry', true)
        if pa then parryAnims[pa.AnimationId] = true end

        local function getTarget()
            local selfpos = entitylib.isAlive and entitylib.character.RootPart.Position or Vector3.zero
            local localfacing = camera.CFrame.LookVector * Vector3.new(1, 0, 1)
            local ent = entitylib.EntityPosition({
                Range = AttackRange.Value, Part = 'RootPart',
                Players = Targets.Players.Enabled, NPCs = Targets.NPCs.Enabled
            })
            if ent then
                local delta = (ent.RootPart.Position - selfpos)
                local angle = math.acos(localfacing:Dot((delta * Vector3.new(1, 0, 1)).Unit))
                if angle > (math.rad(AngleSlider.Value) / 2) then return end
                return ent
            end
        end
        local function shouldAttack(ent)
            if Players.NumPlayers <= 2 then
                for _, v in next, getIndicators() do
                    if v.indicator_type == 'surefire_bullet' or v.indicator_type == 'timing_only' then
                        if (v.expected_shot_time - os.clock()) < 0.4 then return false end
                    end
                end
            end
            local animator = ent.Humanoid:FindFirstChildWhichIsA('Animator')
            if animator then
                for _, track in animator:GetPlayingAnimationTracks() do
                    if track.IsPlaying and parryAnims[track.Animation.AnimationId] then return false end
                end
            end
            return true
        end

        local KA = Feature("Combat", "KillAura", function(self, on)
            if not on then HitboxHook:Remove('KillAura') return end
            HitboxHook:Add('KillAura', function(results)
                if type(results[1]) == 'table' then
                    local ent = getTarget()
                    if ent then
                        Overlay.FilterDescendantsInstances = CollectionService:GetTagged('Hurtbox')
                        local parts = workspace:GetPartBoundsInRadius(ent.RootPart.Position, 6, Overlay)
                        for _, v in parts do table.insert(results[1], v) end
                    end
                end
            end, 1)
            while self.Enabled do
                local ent = getTarget()
                if ent and shouldAttack(ent) and AutoSwing.Enabled then
                    task.spawn(function()
                        local ctrl = redline[redline.ActionController]
                        if ctrl and redline.ActionFunction then
                            local ok, act = pcall(redline.ActionFunction, ctrl, 'MELEE')
                            if ok and type(act) == 'table' and act.Pressed then act.Pressed:Fire() end
                        end
                    end)
                end
                task.wait(0.05)
            end
        end)
        Targets = KA:Targets({ Players = true })
        AttackRange = KA:Slider({ Name = 'Attack range', Min = 1, Max = 40, Default = 40, Suffix = 'm' })
        AngleSlider = KA:Slider({ Name = 'Max angle', Min = 1, Max = 360, Default = 360 })
        AutoSwing = KA:Toggle({ Name = 'Auto Swing', Default = true })
    end

    ------------------------------------------------------------------ SilentAim
    do
        local Target, Range, old
        local function Hook(...)
            if debug.info(4, 's'):find('Gun') then
                local ent = entitylib.EntityMouse({
                    Range = Range.Value, Part = 'RootPart',
                    Players = Target.Players.Enabled, NPCs = Target.NPCs.Enabled
                })
                if ent then
                    return CFrame.lookAt(camera.CFrame.Position, ent.Head.Position).LookVector
                end
            end
            return old(...)
        end
        local SA = Feature("Combat", "SilentAim", function(self, on)
            if on then
                if redline.ShootFunction then
                    old = hookfunction(redline.ShootFunction, function(...) return Hook(...) end)
                end
            else
                if old then restoreHook(redline.ShootFunction, old) old = nil end
            end
        end)
        Target = SA:Targets({ Players = true })
        Range = SA:Slider({ Name = 'Range', Min = 1, Max = 1000, Default = 150, Suffix = 'm' })
    end

    ------------------------------------------------------------------ AlwaysStun
    do
        local Spoof, oldsend, oldrepl, oldbuf
        local AS
        local function AddHook()
            if not (AS.Enabled and redline.ReplicateFunction) then return end
            oldsend = hookfunction(redline.Packet.Fire, function(...)
                local s = ...
                if s and rawget(s, 'Name') == redline.AttackPacket then
                    local args = table.pack(...)
                    if type(args[7]) == 'number' then args[7] = Spoof.Value end
                    return oldsend(unpack(args, 1, args.n))
                end
                return oldsend(...)
            end)
            local dumped, dumpcaller
            oldrepl = hookfunction(redline.ReplicateFunction, function(...)
                local msg = ...
                if dumped and (debug.info(2, 's') == dumpcaller or debug.info(3, 's') == dumpcaller) then
                    buffer.writef32(msg, dumped, Spoof.Value)
                end
                return oldrepl(...)
            end)
            oldbuf = hookfunction(buffer.writef32, function(...)
                local _, ind, data = ...
                if data == -2.25 then
                    dumped = ind
                    dumpcaller = debug.info(3, 's')
                    task.defer(function()
                        if oldbuf then restoreHook(buffer.writef32, oldbuf) oldbuf = nil end
                    end)
                end
                return oldbuf(...)
            end)
        end
        AS = Feature("Blatant", "AlwaysStun", function(self, on)
            if on then
                if (os.clock() - starttime) < 2 then task.delay(2, AddHook) else AddHook() end
            else
                if oldsend then restoreHook(redline.Packet.Fire, oldsend) oldsend = nil end
                if oldrepl then restoreHook(redline.ReplicateFunction, oldrepl) oldrepl = nil end
                if oldbuf then restoreHook(buffer.writef32, oldbuf) oldbuf = nil end
            end
        end)
        Spoof = AS:Slider({ Name = 'Spoof value', Min = 300, Max = 800, Default = 800, Suffix = 'sps' })
    end

    ------------------------------------------------------------------ AntiParry
    do
        local anims = {}
        local pa = ReplicatedStorage.Assets.Animations:FindFirstChild('3P_Parry', true)
        if pa then anims[pa.AnimationId] = true end
        Feature("Blatant", "AntiParry", function(self, on)
            if not on then HitboxHook:Remove('AntiParry') return end
            HitboxHook:Add('AntiParry', function(results)
                if type(results[1]) == 'table' then
                    for _, hit in next, table.clone(results[1]) do
                        local char = hit:FindFirstAncestorWhichIsA('Model')
                        local animator = char and char:FindFirstChild('Animator', true)
                        if animator and animator:IsA('Animator') then
                            for _, track in animator:GetPlayingAnimationTracks() do
                                if track.IsPlaying and anims[track.Animation.AnimationId] then
                                    local index = table.find(results[1], hit)
                                    if index then table.remove(results[1], index) end
                                end
                            end
                        end
                    end
                end
            end, 2)
        end)
    end

    ------------------------------------------------------------------ AutoParry
    do
        Feature("Blatant", "AutoParry", function(self, on)
            if not on then return end
            local cooldown = os.clock()
            while self.Enabled do
                if cooldown < os.clock() then
                    local doParry
                    for i, v in next, getIndicators() do
                        if v.indicator_type == 'surefire_bullet' then
                            local localPos = camera.CFrame.Position
                            local tp = (((i:FindFirstChild('Head') and i.Head.Position or i.PrimaryPart and i.PrimaryPart.Position or i:GetPivot().Position) - localPos) * Vector3.new(1, 0, 1)).Unit
                            local diff = 1 - (camera.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit:Dot(tp)
                            local td = (v.expected_shot_time - os.clock())
                            if math.abs(diff) <= v.parry_range and td < 0.2 and td > 0 and v.indicator_ui.Visible then doParry = true end
                        elseif v.indicator_type == 'timing_only' and Players.NumPlayers <= 2 then
                            local td = (v.expected_shot_time - os.clock())
                            if td < 0 and td > -0.2 and v.indicator_ui.Visible then doParry = true end
                        end
                    end
                    if doParry then
                        cooldown = os.clock() + 0.2
                        task.spawn(function()
                            local ctrl = redline[redline.ActionController]
                            if ctrl and redline.ActionFunction then
                                local ok, act = pcall(redline.ActionFunction, ctrl, 'PARRY')
                                if ok and type(act) == 'table' and act.Pressed then act.Pressed:Fire() end
                            end
                        end)
                    end
                end
                task.wait(0.05)
            end
        end)
    end

    ------------------------------------------------------------------ Fly
    do
        local Value, VerticalValue
        local up, down = 0, 0
        local FL = Feature("Blatant", "Fly", function(self, on)
            if not on then return end
            up, down = 0, 0
            self:Clean(RunService.PreSimulation:Connect(function()
                local mc = redline[redline.MoveController]
                if mc and typeof(mc[redline.VelocityName]) == 'Vector3' then
                    local dir = ((TargetStrafeVector or mc:getMoveDirection()) * Value.Value) + Vector3.new(0, 3.5 + (up + down) * VerticalValue.Value, 0)
                    mc[redline.VelocityName] = dir
                end
            end))
            for _, ev in { 'InputBegan', 'InputEnded' } do
                self:Clean(UserInputService[ev]:Connect(function(input)
                    if not UserInputService:GetFocusedTextBox() then
                        if input.KeyCode == Enum.KeyCode.Space then up = ev == 'InputBegan' and 1 or 0
                        elseif input.KeyCode == Enum.KeyCode.LeftAlt then down = ev == 'InputBegan' and -1 or 0 end
                    end
                end))
            end
        end)
        Value = FL:Slider({ Name = 'Speed', Min = 1, Max = 150, Default = 50, Suffix = 'm' })
        VerticalValue = FL:Slider({ Name = 'Vertical Speed', Min = 1, Max = 150, Default = 50, Suffix = 'm' })
    end

    ------------------------------------------------------------------ HighJump
    do
        local Value
        local HJ = Feature("Blatant", "HighJump", function(self, on)
            if not on then return end
            local mc = redline[redline.MoveController]
            if mc and typeof(mc[redline.VelocityName]) == 'Vector3' then
                mc[redline.VelocityName] += Vector3.new(0, Value.Value, 0)
            end
            task.defer(function()
                self.setEnabled(false)
                if self.toggle and self.toggle.Set then pcall(function() self.toggle:Set(false) end) end
            end)
        end)
        Value = HJ:Slider({ Name = 'Velocity', Min = 1, Max = 150, Default = 50 })
    end

    ------------------------------------------------------------------ LongJump
    do
        local Value, AutoDisable
        local LJ = Feature("Blatant", "LongJump", function(self, on)
            if not on then return end
            local exempt = tick() + 0.1
            self:Clean(RunService.PreSimulation:Connect(function()
                local mc = redline[redline.MoveController]
                if mc and typeof(mc[redline.VelocityName]) == 'Vector3' and entitylib.isAlive then
                    local dir = mc:getMoveDirection() * Value.Value
                    local oldvel = mc[redline.VelocityName]
                    if entitylib.character.Humanoid.FloorMaterial ~= Enum.Material.Air then
                        if exempt < tick() and AutoDisable.Enabled then
                            if self.Enabled then
                                self.setEnabled(false)
                                if self.toggle and self.toggle.Set then pcall(function() self.toggle:Set(false) end) end
                            end
                        else
                            oldvel = Vector3.new(0, 40, 0)
                        end
                    end
                    mc[redline.VelocityName] = Vector3.new(dir.X, oldvel.Y, dir.Z)
                end
            end))
        end)
        Value = LJ:Slider({ Name = 'Speed', Min = 1, Max = 150, Default = 50, Suffix = 'm' })
        AutoDisable = LJ:Toggle({ Name = 'Auto Disable', Default = true })
    end

    ------------------------------------------------------------------ Speed
    do
        local Value, AutoJump
        local SP = Feature("Blatant", "Speed", function(self, on)
            if not on then return end
            self:Clean(RunService.PreSimulation:Connect(function()
                local fly, lj = allFeatures.Fly, allFeatures.LongJump
                if (fly and fly.Enabled) or (lj and lj.Enabled) then return end
                local mc = redline[redline.MoveController]
                if mc and typeof(mc[redline.VelocityName]) == 'Vector3' then
                    local dir = (TargetStrafeVector or mc:getMoveDirection()) * Value.Value
                    local oldvel = mc[redline.VelocityName]
                    if AutoJump.Enabled and entitylib.isAlive and entitylib.character.Humanoid.FloorMaterial ~= Enum.Material.Air and dir.Magnitude > 0.01 then
                        oldvel = Vector3.new(0, 40, 0)
                    end
                    mc[redline.VelocityName] = Vector3.new(dir.X, oldvel.Y, dir.Z)
                end
            end))
        end)
        Value = SP:Slider({ Name = 'Speed', Min = 1, Max = 150, Default = 100, Suffix = 'm' })
        AutoJump = SP:Toggle({ Name = 'AutoJump', Default = false })
    end

    ------------------------------------------------------------------ TargetStrafe
    do
        local Targets, SearchRange, StrafeRange, YFactor
        local rayCheck = RaycastParams.new()
        pcall(function() rayCheck.FilterDescendantsInstances = { workspace.Map } end)
        rayCheck.FilterType = Enum.RaycastFilterType.Include
        local TS = Feature("Blatant", "TargetStrafe", function(self, on)
            if not on then TargetStrafeVector = nil return end
            local ang, oldent
            self:Clean(RunService.PreSimulation:Connect(function()
                local fly = allFeatures.Fly
                local vec
                local wallcheck = Targets.Walls.Enabled
                local ent = not UserInputService:IsKeyDown(Enum.KeyCode.S) and entitylib.isAlive and entitylib.EntityPosition({
                    Range = SearchRange.Value, Wallcheck = wallcheck, Part = 'RootPart',
                    Players = Targets.Players.Enabled, NPCs = Targets.NPCs.Enabled
                })
                if ent then
                    local root, targetPos = entitylib.character.RootPart, ent.RootPart.Position
                    if (fly and fly.Enabled) or workspace:Raycast(targetPos, Vector3.new(0, -70, 0), rayCheck) then
                        local factor, localPosition = 0, root.Position
                        if ent ~= oldent then
                            ang = math.deg(select(2, CFrame.lookAt(targetPos, localPosition):ToEulerAnglesYXZ()))
                        end
                        local yFactor = math.abs(localPosition.Y - targetPos.Y) * (YFactor.Value / 100)
                        local entityPos = Vector3.new(targetPos.X, localPosition.Y, targetPos.Z)
                        local newPos = entityPos + (CFrame.Angles(0, math.rad(ang), 0).LookVector * (StrafeRange.Value - yFactor))
                        if not (fly and fly.Enabled) and not workspace:Raycast(newPos, Vector3.new(0, -70, 0), rayCheck) then
                            newPos = entityPos
                            factor = 40
                        end
                        ang += factor % 360
                        vec = ((newPos - localPosition) * Vector3.new(1, 0, 1)).Unit
                        vec = vec == vec and vec or Vector3.zero
                    else
                        ent = nil
                    end
                end
                TargetStrafeVector = ent and vec or nil
                oldent = ent
            end))
        end)
        Targets = TS:Targets({ Players = true, Walls = true })
        SearchRange = TS:Slider({ Name = 'Search Range', Min = 1, Max = 30, Default = 24, Suffix = 'm' })
        StrafeRange = TS:Slider({ Name = 'Strafe Range', Min = 1, Max = 30, Default = 18, Suffix = 'm' })
        YFactor = TS:Slider({ Name = 'Y Factor', Min = 0, Max = 100, Default = 100, Suffix = '%' })
    end

    ------------------------------------------------------------------ AutoQueue
    do
        local Mode
        local AQ = Feature("Utility", "AutoQueue", function(self, on)
            if on then
                while self.Enabled do
                    local mm = redline.MenuManager
                    if mm and mm.current_session then
                        local ok, client = pcall(function() return mm.current_session.midframe_renderer._client end)
                        if ok and client and client:canQueue() then
                            pcall(function() client:enqueue({ redline.CEnum.Queues[Mode.Value] or 1 }) end)
                        end
                    end
                    task.wait(0.2)
                end
            else
                local mm = redline.MenuManager
                if mm and mm.current_session then
                    pcall(function()
                        local client = mm.current_session.midframe_renderer._client
                        if client:getQueueState().is_queued then client:dequeue() end
                    end)
                end
            end
        end)
        local queueList = {}
        if redline.CEnum and redline.CEnum.Queues then
            for i in redline.CEnum.Queues do table.insert(queueList, i) end
        end
        Mode = AQ:Dropdown({ Name = 'Mode', Items = queueList, Default = queueList[1] or 'Duels1v1' })
    end

    ------------------------------------------------------------------ AutoLeave
    do
        local Delay
        local function findReturnButton()
            local pg = lplr:FindFirstChild('PlayerGui')
            if not pg then return end
            for _, d in pg:GetDescendants() do
                if (d:IsA('TextButton') or d:IsA('ImageButton')) and d.Name:lower():find('return') and d.Visible then
                    return d
                end
            end
        end
        local fired = false
        local AL = Feature("Utility", "AutoLeave", function(self, on)
            if not on then fired = false return end
            fired = false
            self:Clean(RunService.Heartbeat:Connect(function()
                if fired then return end
                local btn = findReturnButton()
                if btn then
                    fired = true
                    task.wait(Delay.Value)
                    pcall(function() firesignal(btn.MouseButton1Click) end)
                end
            end))
        end)
        Delay = AL:Slider({ Name = 'Delay', Min = 0, Max = 5, Default = 1, Decimal = 10, Suffix = 's' })
    end

    ------------------------------------------------------------------ Phase (noclip)
    do
        Feature("Utility", "Phase", function(self, on)
            if not on then return end
            self:Clean(RunService.Stepped:Connect(function()
                if entitylib.isAlive and entitylib.character.Character then
                    for _, p in entitylib.character.Character:GetDescendants() do
                        if p:IsA('BasePart') and p.CanCollide then p.CanCollide = false end
                    end
                end
            end))
        end)
    end

    ------------------------------------------------------------------ Timer
    do
        local TM = Feature("Utility", "Timer", function(self, on)
            if on then
                local start = os.clock()
                self:Clean(RunService.Heartbeat:Connect(function()
                    local t = os.clock() - start
                    pcall(function() self.Section:SetText(('Timer  %02d:%02d'):format(math.floor(t / 60), math.floor(t % 60))) end)
                end))
            else
                pcall(function() self.Section:SetText('Timer') end)
            end
        end)
    end

    ------------------------------------------------------------------ StaffDetector
    do
        local GROUP = 35646671 -- REDLINER creator group
        local SD = Feature("Utility", "StaffDetector", function(self, on)
            if not on then return end
            local function check(plr)
                if plr == lplr then return end
                task.spawn(function()
                    local ok, rank = pcall(function() return plr:GetRankInGroup(GROUP) end)
                    if ok and type(rank) == 'number' and rank >= 50 then
                        notify('Staff in server: ' .. plr.Name .. ' (rank ' .. rank .. ')')
                    end
                end)
            end
            for _, p in Players:GetPlayers() do check(p) end
            self:Clean(Players.PlayerAdded:Connect(check))
        end)
    end
end

--======================================================================
-- bootstrap: discover internals, build features, show window, set cleanup
--======================================================================
task.spawn(function()
    log("discovering REDLINER internals ...")
    local ok = pcall(runDiscovery)
    if not ok or not discovered then
        notify("REDLINER: discovery failed (are you in a match?)")
    end
    pcall(buildFeatures)
    pcall(function() window:Init() end)
    notify("REDLINER loaded into banknote")
end)

local function unloadAll()
    for _, m in pairs(allFeatures) do
        if type(m) == "table" and m.Enabled and m.setEnabled then
            pcall(function() m.setEnabled(false) end)
        end
    end
    pcall(function() if entitylib and entitylib.kill then entitylib.kill() end end)
    getgenv()._RedlinerLoaded = nil
end

do
    local realExit = BN.Exit
    if realExit then
        BN.Exit = function(self, ...)
            unloadAll()
            return realExit(self, ...)
        end
    end
    BN.OnUnload = unloadAll
end
