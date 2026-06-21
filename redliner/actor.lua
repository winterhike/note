--======================================================================
-- $$ banknote $$  -  REDLINER actor runtime
--
-- This runs INSIDE a REDLINER game actor (a separate Luau VM). REDLINER's
-- client controllers live in the actor VMs, so require(ClientRoot).Classes
-- is only populated here -- on the main thread it is empty (which is why
-- every controller-based feature was dead).
--
-- The banknote UI lives on the main thread; it can't share Lua tables with
-- this VM, so feature state is bridged through Attributes on a shared
-- DataModel instance (__RL_BRIDGE). This script reads those attributes and
-- drives the game internals.
--
-- Expects two values prepended by the main thread:
--   __RL_ENTITY_SRC : source of redliner/entity.lua (string)
--   __RL_BRIDGE     : name of the bridge instance under ReplicatedStorage
--======================================================================
local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local UserInputService   = game:GetService("UserInputService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")
local CollectionService  = game:GetService("CollectionService")

local lplr   = Players.LocalPlayer
local camera = workspace.CurrentCamera

--------------------------------------------------------------- bridge
local bridge = ReplicatedStorage:FindFirstChild(__RL_BRIDGE)
do
    local deadline = tick() + 15
    while not bridge and tick() < deadline do
        task.wait()
        bridge = ReplicatedStorage:FindFirstChild(__RL_BRIDGE)
    end
end
if not bridge then return end

local function On(feat) return bridge:GetAttribute(feat) == true end
local function Opt(feat, opt, default)
    local v = bridge:GetAttribute(feat .. "_" .. opt)
    if v == nil then return default end
    return v
end
local function report(msg) pcall(function() bridge:SetAttribute("__status", tostring(msg)) end) end

--------------------------------------------------------------- entity lib
local entitylib
do
    local ok, lib = pcall(function() return loadstring(__RL_ENTITY_SRC)() end)
    if ok and type(lib) == "table" then entitylib = lib else report("entity fail: " .. tostring(lib)) return end
end

--------------------------------------------------------------- discovery
local redline = { Teams = {} }
local starttime = os.clock()
local TargetStrafeVector
local strafeDriving = false  -- true while TargetStrafe v2 is directly driving velocity

local function searchForPacket(func, unreliable)
    for _, v in debug.getconstants(func) do
        if rawget(unreliable and redline.Packets.unreliablePackets or redline.Packets, v) then return v end
    end
end
local function getIndicators()
    return redline[redline.IndicatorController] and redline[redline.IndicatorController][redline.IndicatorTable] or {}
end

local function runDiscovery()
    local root
    for _, v in getloadedmodules() do
        if v:GetFullName() == 'Start.Client.ClientRoot' then
            root = require(v)
            local deadline = tick() + 20
            while not rawget(root, 'loaded') and tick() < deadline do task.wait() end
        end
    end
    if not root then report("no ClientRoot") return false end

    local classList = rawget(root, 'Classes') or {}
    redline = setmetatable({
        AttackBox = require(ReplicatedStorage.Assets.ModuleScripts.Attack),
        AttackCast = require(ReplicatedStorage.Assets.ModuleScripts.Attack.Hitbox),
        CEnum = require(ReplicatedStorage.Assets.ModuleScripts.CEnum),
        Packets = require(ReplicatedStorage.Assets.ModuleScripts.Packets),
        Packet = debug.getupvalue(getrawmetatable(require(ReplicatedStorage.Assets.ModuleScripts.Packets.Packet)).__call, 2),
        Util = require(ReplicatedStorage.Assets.SharedClasses.Util),
        Teams = redline.Teams
    }, {
        __index = function(self, ind) return rawget(classList, ind) end
    })

    local dumplist = {
        Constants = {
            ShootFunction = function(c, func, inst)
                for _, k in c do if k == 'ViewportPointToRay' then redline.ShootFunction = require(inst)[debug.info(func, 'n')] break end end
            end,
            ActionController = function(c, func, inst)
                for _, k in c do if k == 'getAction FAILED FOR : ' then redline.ActionController = inst.Name redline.ActionFunction = require(inst)[debug.info(func, 'n')] break end end
            end,
            IndicatorController = function(c, func, inst)
                for _, k in c do if k == 'INVALID crosshair_name : ' then redline.IndicatorController = inst.Name break end end
            end,
            ReplicateFunction = function(c, func, inst)
                for _, k in c do if k == 'Message cannot be empty' then redline.ReplicateFunction = require(inst)[debug.info(func, 'n')] break end end
            end,
            MoveController = function(c, func, inst)
                for _, k in c do
                    if k == 'getMoveDirection' then
                        local found = {}
                        for _, k2 in c do if tostring(k2):find('_') then table.insert(found, k2) end end
                        redline.MoveController = found[1]
                        redline.VelocityName = found[2]
                        break
                    end
                end
            end,
            ActionEventPacket = function(c, func, inst)
                local found
                for _, k in c do
                    if k == 'OnClientEvent' then found = true
                    elseif k == 'onKill' and found then
                        redline.ActionEventPacket = searchForPacket(func, true)
                        if redline.ActionEventPacket then redline.ActionEventPacket = redline.Packets.unreliablePackets[redline.ActionEventPacket] end
                        break
                    end
                end
            end
        },
        Protos = {
            AttackPacket = function(p, func, inst)
                for _, proto in p do
                    if debug.info(proto, 'n') == 'redlinerMelee' then
                        redline.AttackPacket = searchForPacket(debug.getproto(debug.getproto(proto, 1), 1))
                        if redline.AttackPacket then redline.AttackPacket = redline.Packets[redline.AttackPacket].Name end
                        break
                    end
                end
            end,
            IndicatorTable = function(p, func, inst)
                for _, proto in p do
                    if debug.info(proto, 'n') == 'removeShotIndicator' then
                        for _, k in debug.getconstants(proto) do if tostring(k):find('_') then redline.IndicatorTable = k break end end
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
            if protos[1] and debug.info(protos[1], 'l') == 3 and #debug.info(protos[1], 'n') <= 2 then continue end
            for _, func in debug.getprotos(closure) do
                for name, cb in dumplist.Constants do if not redline[name] then pcall(cb, debug.getconstants(func), func, v) end end
                for name, cb in dumplist.Protos do if not redline[name] then pcall(cb, debug.getprotos(func), func, v) end end
            end
        end
    end

    -- validate velocity field
    local mc = redline.MoveController and redline[redline.MoveController]
    if type(mc) == 'table' then
        local cur = redline.VelocityName and rawget(mc, redline.VelocityName)
        if typeof(cur) ~= 'Vector3' then
            for k, val in pairs(mc) do if typeof(val) == 'Vector3' then redline.VelocityName = k break end end
        end
    end

    local liveAction = redline.ActionController and redline[redline.ActionController]
    local liveMove   = redline.MoveController and redline[redline.MoveController]
    -- only the actor that actually holds the live controllers should proceed
    return liveAction ~= nil or liveMove ~= nil
end

-- This payload is dispatched to every actor; bail unless THIS actor has the
-- live controllers, and claim the bridge so only one actor sets up features.
if not runDiscovery() then return end
if bridge:GetAttribute("__claimed") == true then return end
bridge:SetAttribute("__claimed", true)
report("ready (controllers resolved on actor)")
entitylib.start()

--------------------------------------------------------------- HitboxHook
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
        for i, v in self.Hooks do if v[1] == key then table.remove(self.Hooks, i) break end end
        if oldscan and not next(self.Hooks) then
            if restorefunction then restorefunction(redline.AttackBox.castOnce) else hookfunction(redline.AttackBox.castOnce, oldscan) end
            oldscan = nil
        end
    end
end

local function restoreHook(target, old)
    if not old then return end
    if restorefunction then restorefunction(target) else hookfunction(target, old) end
end

--------------------------------------------------------------- feature binder
local function bindFeature(name, onEnable, onDisable)
    local cleans = {}
    local self = { Name = name, Enabled = false }
    local function clean()
        for _, c in ipairs(cleans) do
            pcall(function()
                if typeof(c) == 'RBXScriptConnection' then c:Disconnect()
                elseif type(c) == 'table' and c.Disconnect then c:Disconnect() end
            end)
        end
        cleans = {}
    end
    function self:Clean(c) table.insert(cleans, c) return c end
    function self:Off() pcall(function() bridge:SetAttribute(name, false) end) end
    local function apply()
        local want = On(name)
        if want == self.Enabled then return end
        self.Enabled = want
        if want then task.spawn(function() pcall(onEnable, self) end)
        else pcall(function() if onDisable then onDisable(self) end end) clean() end
    end
    bridge:GetAttributeChangedSignal(name):Connect(apply)
    task.defer(apply)
    return self
end

local function fireAction(name)
    local ctrl = redline[redline.ActionController]
    if ctrl and redline.ActionFunction then
        local ok, act = pcall(redline.ActionFunction, ctrl, name)
        if ok and type(act) == 'table' and act.Pressed then act.Pressed:Fire() end
    end
end

--======================================================================
-- features
--======================================================================
-- KillAura -------------------------------------------------------------
do
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
            Range = Opt('KillAura', 'AttackRange', 40), Part = 'RootPart',
            Players = Opt('KillAura', 'Players', true), NPCs = Opt('KillAura', 'NPCs', false)
        })
        if ent then
            local delta = ent.RootPart.Position - selfpos
            local angle = math.acos(localfacing:Dot((delta * Vector3.new(1, 0, 1)).Unit))
            if angle > (math.rad(Opt('KillAura', 'MaxAngle', 360)) / 2) then return end
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
    bindFeature('KillAura', function(self)
        HitboxHook:Add('KillAura', function(results)
            if type(results[1]) == 'table' then
                local ent = getTarget()
                if ent then
                    Overlay.FilterDescendantsInstances = CollectionService:GetTagged('Hurtbox')
                    for _, v in workspace:GetPartBoundsInRadius(ent.RootPart.Position, 6, Overlay) do
                        table.insert(results[1], v)
                    end
                end
            end
        end, 1)
        while self.Enabled do
            local ent = getTarget()
            if ent and shouldAttack(ent) and Opt('KillAura', 'AutoSwing', true) then
                task.spawn(fireAction, 'MELEE')
            end
            task.wait(0.05)
        end
    end, function() HitboxHook:Remove('KillAura') end)
end

-- SilentAim ------------------------------------------------------------
do
    local old
    local function Hook(...)
        if debug.info(4, 's'):find('Gun') then
            if math.random(1, 100) <= Opt('SilentAim', 'HitChance', 85) then
                local ent = entitylib.EntityMouse({
                    Range = Opt('SilentAim', 'Range', 150), Part = 'RootPart',
                    Players = Opt('SilentAim', 'Players', true), NPCs = Opt('SilentAim', 'NPCs', false)
                })
                if ent then return CFrame.lookAt(camera.CFrame.Position, ent.Head.Position).LookVector end
            end
        end
        return old(...)
    end
    bindFeature('SilentAim', function()
        if redline.ShootFunction then old = hookfunction(redline.ShootFunction, function(...) return Hook(...) end) end
    end, function()
        if old then restoreHook(redline.ShootFunction, old) old = nil end
    end)
end

-- AlwaysStun -----------------------------------------------------------
do
    local oldsend, oldrepl, oldbuf
    local function AddHook()
        if not redline.ReplicateFunction then return end
        local spoof = function() return Opt('AlwaysStun', 'Spoof', 800) end
        oldsend = hookfunction(redline.Packet.Fire, function(...)
            local s = ...
            if s and rawget(s, 'Name') == redline.AttackPacket then
                local args = table.pack(...)
                if type(args[7]) == 'number' then args[7] = spoof() end
                return oldsend(unpack(args, 1, args.n))
            end
            return oldsend(...)
        end)
        local dumped, dumpcaller
        oldrepl = hookfunction(redline.ReplicateFunction, function(...)
            local msg = ...
            if dumped and (debug.info(2, 's') == dumpcaller or debug.info(3, 's') == dumpcaller) then
                buffer.writef32(msg, dumped, spoof())
            end
            return oldrepl(...)
        end)
        oldbuf = hookfunction(buffer.writef32, function(...)
            local _, ind, data = ...
            if data == -2.25 then
                dumped = ind
                dumpcaller = debug.info(3, 's')
                task.defer(function() if oldbuf then restoreHook(buffer.writef32, oldbuf) oldbuf = nil end end)
            end
            return oldbuf(...)
        end)
    end
    bindFeature('AlwaysStun', function()
        if (os.clock() - starttime) < 2 then task.delay(2, AddHook) else AddHook() end
    end, function()
        if oldsend then restoreHook(redline.Packet.Fire, oldsend) oldsend = nil end
        if oldrepl then restoreHook(redline.ReplicateFunction, oldrepl) oldrepl = nil end
        if oldbuf then restoreHook(buffer.writef32, oldbuf) oldbuf = nil end
    end)
end

-- AntiParry ------------------------------------------------------------
do
    local anims = {}
    local pa = ReplicatedStorage.Assets.Animations:FindFirstChild('3P_Parry', true)
    if pa then anims[pa.AnimationId] = true end
    bindFeature('AntiParry', function()
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
    end, function() HitboxHook:Remove('AntiParry') end)
end

-- AutoParry ------------------------------------------------------------
do
    bindFeature('AutoParry', function(self)
        local cooldown = os.clock()
        while self.Enabled do
            if cooldown < os.clock() then
                local doParry
                for i, v in next, getIndicators() do
                    if v.indicator_type == 'surefire_bullet' then
                        local localPos = camera.CFrame.Position
                        local tp = (((i:FindFirstChild('Head') and i.Head.Position or i.PrimaryPart and i.PrimaryPart.Position or i:GetPivot().Position) - localPos) * Vector3.new(1, 0, 1)).Unit
                        local diff = 1 - (camera.CFrame.LookVector * Vector3.new(1, 0, 1)).Unit:Dot(tp)
                        local td = v.expected_shot_time - os.clock()
                        if math.abs(diff) <= v.parry_range and td < 0.2 and td > 0 and v.indicator_ui.Visible then doParry = true end
                    elseif v.indicator_type == 'timing_only' and Players.NumPlayers <= 2 then
                        local td = v.expected_shot_time - os.clock()
                        if td < 0 and td > -0.2 and v.indicator_ui.Visible then doParry = true end
                    end
                end
                if doParry then cooldown = os.clock() + 0.2 task.spawn(fireAction, 'PARRY') end
            end
            task.wait(0.05)
        end
    end)
end

-- Fly ------------------------------------------------------------------
do
    local up, down = 0, 0
    bindFeature('Fly', function(self)
        up, down = 0, 0
        self:Clean(RunService.PreSimulation:Connect(function()
            local mc = redline[redline.MoveController]
            if mc and typeof(mc[redline.VelocityName]) == 'Vector3' then
                local dir = ((TargetStrafeVector or mc:getMoveDirection()) * Opt('Fly', 'Speed', 50)) + Vector3.new(0, 3.5 + (up + down) * Opt('Fly', 'VerticalSpeed', 50), 0)
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
end

-- HighJump (one-shot impulse) -----------------------------------------
do
    bindFeature('HighJump', function(self)
        local mc = redline[redline.MoveController]
        if mc and typeof(mc[redline.VelocityName]) == 'Vector3' then
            mc[redline.VelocityName] += Vector3.new(0, Opt('HighJump', 'Velocity', 50), 0)
        end
        self:Off() -- reset; main UI mirrors this attribute back to its toggle
    end)
end

-- LongJump -------------------------------------------------------------
do
    bindFeature('LongJump', function(self)
        local exempt = tick() + 0.1
        self:Clean(RunService.PreSimulation:Connect(function()
            local mc = redline[redline.MoveController]
            if mc and typeof(mc[redline.VelocityName]) == 'Vector3' and entitylib.isAlive then
                local dir = mc:getMoveDirection() * Opt('LongJump', 'Speed', 50)
                local oldvel = mc[redline.VelocityName]
                if entitylib.character.Humanoid.FloorMaterial ~= Enum.Material.Air then
                    if exempt < tick() and Opt('LongJump', 'AutoDisable', true) then
                        self:Off()
                    else
                        oldvel = Vector3.new(0, 40, 0)
                    end
                end
                mc[redline.VelocityName] = Vector3.new(dir.X, oldvel.Y, dir.Z)
            end
        end))
    end)
end

-- Speed ----------------------------------------------------------------
do
    bindFeature('Speed', function(self)
        self:Clean(RunService.PreSimulation:Connect(function()
            if On('Fly') or On('LongJump') then return end
            if strafeDriving then return end -- TargetStrafe v2 owns velocity
            local mc = redline[redline.MoveController]
            if mc and typeof(mc[redline.VelocityName]) == 'Vector3' then
                local dir = (TargetStrafeVector or mc:getMoveDirection()) * Opt('Speed', 'Speed', 100)
                local oldvel = mc[redline.VelocityName]
                if Opt('Speed', 'AutoJump', false) and entitylib.isAlive and entitylib.character.Humanoid.FloorMaterial ~= Enum.Material.Air and dir.Magnitude > 0.01 then
                    oldvel = Vector3.new(0, (Opt('Speed', 'CustomJump', false) and Opt('Speed', 'JumpPower', 30)) or 40, 0)
                end
                mc[redline.VelocityName] = Vector3.new(dir.X, oldvel.Y, dir.Z)
            end
        end))
    end)
end

-- TargetStrafe ---------------------------------------------------------
do
    local rayCheck = RaycastParams.new()
    pcall(function() rayCheck.FilterDescendantsInstances = { workspace.Map } end)
    rayCheck.FilterType = Enum.RaycastFilterType.Include

    local lockedTarget  -- for the "First Target" priority

    -- REDLINER keeps health at Players.<name>.ReadOnly.health (a value object),
    -- NOT on the Humanoid, so read it from there.
    local function getHealth(ent)
        local plr = ent and ent.Player
        if plr then
            local hv = plr:FindFirstChild('health', true)
            if hv and hv:IsA('ValueBase') then return hv.Value end
            local a = plr:GetAttribute('health')
            if type(a) == 'number' then return a end
        end
        return ent and ent.Health or 0
    end
    local function isAliveEnt(ent)
        return ent and table.find(entitylib.List, ent) ~= nil and ent.RootPart ~= nil and getHealth(ent) > 0
    end

    -- v2 target selection honouring the Priority dropdown
    local function pickTargetV2()
        local players = Opt('TargetStrafe', 'Players', true)
        local npcs    = Opt('TargetStrafe', 'NPCs', false)
        local range   = Opt('TargetStrafe', 'SearchRange', 24)
        local priority = Opt('TargetStrafe', 'Priority', 'Closest Distance')

        if priority == 'First Target' then
            -- keep the locked target until it dies / leaves, then re-acquire
            if isAliveEnt(lockedTarget) then return lockedTarget end
            lockedTarget = entitylib.EntityPosition({ Range = range, Part = 'RootPart', Players = players, NPCs = npcs })
            return lockedTarget
        elseif priority == 'Lowest HP' then
            local best, bestHp
            local myPos = entitylib.character.RootPart.Position
            for _, ent in entitylib.List do
                if ent.RootPart and ent.Targetable ~= false
                    and ((players and ent.Player) or (npcs and ent.NPC)) then
                    local hp = getHealth(ent)
                    if hp > 0 and (ent.RootPart.Position - myPos).Magnitude <= range then
                        if not bestHp or hp < bestHp then best, bestHp = ent, hp end
                    end
                end
            end
            return best
        else -- Closest Distance (default)
            return entitylib.EntityPosition({ Range = range, Part = 'RootPart', Players = players, NPCs = npcs })
        end
    end

    -- v1: original Vape behaviour. Sets the horizontal TargetStrafeVector; you
    -- still need Speed/Fly enabled to actually move.
    local function strafeV1(ang, oldent)
        local vec
        local wallcheck = Opt('TargetStrafe', 'Walls', false)
        local ent = not UserInputService:IsKeyDown(Enum.KeyCode.S) and entitylib.isAlive and entitylib.EntityPosition({
            Range = Opt('TargetStrafe', 'SearchRange', 24), Wallcheck = wallcheck, Part = 'RootPart',
            Players = Opt('TargetStrafe', 'Players', true), NPCs = Opt('TargetStrafe', 'NPCs', false)
        })
        if ent then
            local root, targetPos = entitylib.character.RootPart, ent.RootPart.Position
            if On('Fly') or workspace:Raycast(targetPos, Vector3.new(0, -70, 0), rayCheck) then
                local factor, localPosition = 0, root.Position
                if ent ~= oldent then ang = math.deg(select(2, CFrame.lookAt(targetPos, localPosition):ToEulerAnglesYXZ())) end
                local yFactor = math.abs(localPosition.Y - targetPos.Y) * (Opt('TargetStrafe', 'YFactor', 100) / 100)
                local entityPos = Vector3.new(targetPos.X, localPosition.Y, targetPos.Z)
                local newPos = entityPos + (CFrame.Angles(0, math.rad(ang), 0).LookVector * (Opt('TargetStrafe', 'StrafeRange', 18) - yFactor))
                if not On('Fly') and not workspace:Raycast(newPos, Vector3.new(0, -70, 0), rayCheck) then
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
        strafeDriving = false
        return ang, ent
    end

    -- v2: improved, self-driving orbit (works standalone, no Speed needed).
    -- "Sticky" chases the target's height, so you keep orbiting even as they
    -- fly straight up -- you climb with them until they die. Also supports
    -- prediction (lead the target's velocity) and an adjustable rotation speed.
    local function strafeV2(ang, oldent)
        local mc = redline[redline.MoveController]
        if not (mc and typeof(mc[redline.VelocityName]) == 'Vector3' and entitylib.isAlive) then
            TargetStrafeVector = nil strafeDriving = false return ang, nil
        end
        local ent = (not UserInputService:IsKeyDown(Enum.KeyCode.S)) and pickTargetV2()
        if not ent then TargetStrafeVector = nil strafeDriving = false return ang, nil end

        local root  = entitylib.character.RootPart
        local myPos = root.Position
        local tp    = ent.RootPart.Position

        local predict = Opt('TargetStrafe', 'Prediction', 0)
        if predict > 0 then
            local ok, vel = pcall(function() return ent.RootPart.AssemblyLinearVelocity end)
            if ok and typeof(vel) == 'Vector3' then tp = tp + (vel * predict) end
        end

        if ent ~= oldent then ang = math.deg(select(2, CFrame.lookAt(tp, myPos):ToEulerAnglesYXZ())) end
        ang = (ang + Opt('TargetStrafe', 'RotationSpeed', 12)) % 360

        local sticky  = Opt('TargetStrafe', 'Sticky', false)
        local range   = Opt('TargetStrafe', 'StrafeRange', 18)
        local speed   = Opt('TargetStrafe', 'Speed', 60)
        local centerY = sticky and tp.Y or myPos.Y
        local desired = Vector3.new(tp.X, centerY, tp.Z) + (CFrame.Angles(0, math.rad(ang), 0).LookVector * range)
        local delta   = desired - myPos

        local horiz = delta * Vector3.new(1, 0, 1)
        local hvel  = horiz.Magnitude > 0.01 and (horiz.Unit * speed) or Vector3.zero
        hvel = hvel == hvel and hvel or Vector3.zero

        TargetStrafeVector = horiz.Magnitude > 0.01 and horiz.Unit or Vector3.zero

        if On('Fly') then
            strafeDriving = false
        else
            local yvel
            if sticky then
                yvel = math.clamp(delta.Y * 10, -speed, speed)
            else
                yvel = mc[redline.VelocityName].Y
            end
            mc[redline.VelocityName] = Vector3.new(hvel.X, yvel, hvel.Z)
            strafeDriving = true
        end
        return ang, ent
    end

    bindFeature('TargetStrafe', function(self)
        local ang, oldent
        self:Clean(RunService.PreSimulation:Connect(function()
            if Opt('TargetStrafe', 'Version', 'v1') == 'v2' then
                ang, oldent = strafeV2(ang, oldent)
            else
                ang, oldent = strafeV1(ang, oldent)
            end
        end))
    end, function() TargetStrafeVector = nil strafeDriving = false lockedTarget = nil end)
end

-- AutoQueue ------------------------------------------------------------
do
    bindFeature('AutoQueue', function(self)
        while self.Enabled do
            local mm = redline.MenuManager
            if mm and mm.current_session then
                pcall(function()
                    local client = mm.current_session.midframe_renderer._client
                    if client:canQueue() then
                        client:enqueue({ redline.CEnum.Queues[Opt('AutoQueue', 'Mode', 'Duels1v1')] or 1 })
                    end
                end)
            end
            task.wait(0.2)
        end
    end, function()
        local mm = redline.MenuManager
        if mm and mm.current_session then
            pcall(function()
                local client = mm.current_session.midframe_renderer._client
                if client:getQueueState().is_queued then client:dequeue() end
            end)
        end
    end)
end

-- Phase (noclip) -------------------------------------------------------
do
    bindFeature('Phase', function(self)
        self:Clean(RunService.Stepped:Connect(function()
            if entitylib.isAlive and entitylib.character.Character then
                for _, p in entitylib.character.Character:GetDescendants() do
                    if p:IsA('BasePart') and p.CanCollide then p.CanCollide = false end
                end
            end
        end))
    end)
end

-- RageBot --------------------------------------------------------------
-- Auto-kills everyone: injects EVERY alive entity's hurtbox into each melee
-- scan (so one swing hits all targets in range) and swings continuously.
do
    local Overlay = OverlapParams.new()
    Overlay.FilterType = Enum.RaycastFilterType.Include
    Overlay.RespectCanCollide = false
    bindFeature('RageBot', function(self)
        HitboxHook:Add('RageBot', function(results)
            if type(results[1]) ~= 'table' then return end
            local range  = Opt('RageBot', 'Range', 200)
            local origin = entitylib.isAlive and entitylib.character.RootPart.Position or Vector3.zero
            Overlay.FilterDescendantsInstances = CollectionService:GetTagged('Hurtbox')
            for _, ent in entitylib.List do
                if ent.RootPart and (ent.Player or ent.NPC) and ent.Targetable ~= false then
                    if (ent.RootPart.Position - origin).Magnitude <= range then
                        for _, p in workspace:GetPartBoundsInRadius(ent.RootPart.Position, 6, Overlay) do
                            table.insert(results[1], p)
                        end
                    end
                end
            end
        end, 0)
        while self.Enabled do
            task.spawn(fireAction, 'MELEE')
            task.wait(Opt('RageBot', 'SwingDelay', 0.1))
        end
    end, function() HitboxHook:Remove('RageBot') end)
end

-- GrapplerCooldown -----------------------------------------------------
-- Customise the grapple (AUGMENT) cooldown. 0 = no cooldown (clears the gate
-- instantly), 1 = regular. In between scales the wait (value * cap seconds);
-- we only ever clear EARLY, never extend, so 1 leaves the real cooldown intact.
do
    local CAP = 5
    bindFeature('GrapplerCooldown', function(self)
        local blockStart
        self:Clean(RunService.Heartbeat:Connect(function()
            local ctrl = redline[redline.ActionController]
            if not ctrl or not redline.ActionFunction then return end
            local ok, act = pcall(redline.ActionFunction, ctrl, 'AUGMENT')
            if not ok or type(act) ~= 'table' then return end
            local value = Opt('GrapplerCooldown', 'Cooldown', 1)
            local blocked = (act.Enabled == false) or (next(act.Blockers) ~= nil)
            if blocked then
                blockStart = blockStart or tick()
                if (tick() - blockStart) >= (value * CAP) then
                    pcall(function() table.clear(act.Blockers) end)
                    act.Enabled = true
                end
            else
                blockStart = nil
            end
        end))
    end)
end

report("loaded")
