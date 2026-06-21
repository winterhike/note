--======================================================================
-- $$ banknote $$  -  D.I.G  (PlaceId 98129535207266, universe 7304084567)
--
-- D.I.G is a sandbox shooter. Each gun is a Tool with a client-side GunLocal
-- LocalScript. The hit system is CLIENT-AUTHORITATIVE and works in two steps
-- (confirmed via remote spy):
--   1. GunServer.Fire:FireServer({ {Hash=str, Orgin=CFrame}, ... })
--        -> registers each bullet (origin + a unique hash) with the server.
--   2. GunServer.Damage:FireServer({Instance=part, CFrame=CFrame.new(pos),
--        Size=part.Size}, hash)
--        -> the CLIENT raycasts the bullet's flight and, on hit, reports the
--           hit instance for that hash. The server trusts it.
--
-- Because step 2 uses the client's own raycast, a wall between you and the
-- target makes the bullet report the WALL. The fix (like Vape/PF ragebots) is
-- to take over the reported hit:
--   * rewrite the Fire Orgin to point at the target, and
--   * override the Damage Instance/CFrame/Size to the target's body part,
--     so the hit lands on them THROUGH walls.
-- Kill All appends one bullet per enemy to each Fire and emits a matching
-- Damage, tagging everyone in range per trigger pull.
--
-- IMPORTANT: the __namecall hook must NOT call any methods (:FindFirstChild,
-- :GetPlayers, ...). A method call inside a __namecall hook overwrites the
-- engine's "current namecall method", so the subsequent oldNamecall(self,...)
-- would dispatch the WRONG method (that was the "argument #1 expects a string"
-- / "cast string to bool" spam). So everything the hook needs (target part,
-- enemy parts, the Damage remote) is precomputed in the Heartbeat loop, and
-- the hook only reads properties + mutates the argument tables.
--
-- GunLocal internals (decompiled) used for the gun-stat mods:
--   u66 frame: upvalue 1 = current ammo, upvalue 12 = settings table u4
--   (BulletSpeed, Step, Period=60/RPM, Spread, MinSpread, MaxSpread, MaxAmmo);
--   stack slot 12 = bullet origin CFrame (read), slot 17 = the CFrame handed
--   to the bullet sim (write). Auto guns loop `while u7 do u66() wait(Period)`.
--
-- Marker for the loader: BanknoteLibrary
--======================================================================
if getgenv()._DIGLoaded then return end
getgenv()._DIGLoaded = true

local BN = getgenv().BanknoteLibrary
assert(BN, "[banknote] BanknoteLibrary not set by loader")

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local lplr   = Players.LocalPlayer
local camera = workspace.CurrentCamera

-- exploit / math globals (localized + guarded)
local info           = debug.info
local getstack       = getstack
local setstack       = setstack
local getupvalue     = getupvalue or debug.getupvalue
local setupvalue     = setupvalue or debug.setupvalue
local hookfunction   = hookfunction or replaceclosure
local hookmetamethod = hookmetamethod
local getnamecall    = getnamecallmethod or get_namecall_method
local newcclosure    = newcclosure or function(f) return f end
local checkcaller    = checkcaller or function() return false end
local lookAt         = CFrame.lookAt
local cnew           = CFrame.new
local v3             = Vector3.new
local v2             = Vector2.new

local function log(...) print("[banknote/D.I.G]", ...) end

--======================================================================
-- feature state
--======================================================================
local FEAT = {
    SilentAim   = false,
    Ragebot     = false,
    KillAll     = false,
    NoSpread    = false,
    InfAmmo     = false,
    RapidFire   = false,

    TeamCheck   = true,
    FOVEnabled  = false,
    FOVRadius   = 150,
    HitPart     = "Head",
    HitChance   = 100,
    RapidRPM    = 1200,
    RagebotDelay= 0.06,
    Snapline    = false,
}

local target = nil  -- current target Character (Model) for silent/rage

-- precomputed each Heartbeat so the __namecall hook never calls a method
local cache = {
    targetPart = nil,  -- Instance: current target's hit part
    enemyParts = {},   -- Instance[]: hit parts of every enemy in range (Kill All)
    dmgRemote  = nil,   -- the equipped gun's GunServer.Damage RemoteEvent
}

--======================================================================
-- target selection helpers (only called OUTSIDE the __namecall hook)
--======================================================================
local function isEnemy(plr)
    if plr == lplr then return false end
    if FEAT.TeamCheck and lplr.Team and plr.Team == lplr.Team then return false end
    return true
end

local function getHitPart(char)
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return nil end
    local hp = type(FEAT.HitPart) == "string" and FEAT.HitPart or "Head"
    return char:FindFirstChild(hp)
        or char:FindFirstChild("Head")
        or char:FindFirstChild("HumanoidRootPart")
        or char:FindFirstChild("Torso")
end

local function nearestToCrosshair()
    local mouse = UserInputService:GetMouseLocation()
    local best, bestd
    for _, plr in ipairs(Players:GetPlayers()) do
        if isEnemy(plr) and plr.Character then
            local part = getHitPart(plr.Character)
            if part then
                local sp, on = camera:WorldToViewportPoint(part.Position)
                if on then
                    local d = (v2(sp.X, sp.Y) - mouse).Magnitude
                    if (not FEAT.FOVEnabled or d <= FEAT.FOVRadius) and (not bestd or d < bestd) then
                        best, bestd = plr.Character, d
                    end
                end
            end
        end
    end
    return best
end

local function nearestByDistance()
    local root = lplr.Character and (lplr.Character:FindFirstChild("HumanoidRootPart") or lplr.Character:FindFirstChild("Torso"))
    if not root then return nil end
    local best, bestd
    for _, plr in ipairs(Players:GetPlayers()) do
        if isEnemy(plr) and plr.Character then
            local part = getHitPart(plr.Character)
            if part then
                local d = (part.Position - root.Position).Magnitude
                if not bestd or d < bestd then best, bestd = plr.Character, d end
            end
        end
    end
    return best
end

local function equippedTool()
    local char = lplr.Character
    return char and char:FindFirstChildOfClass("Tool")
end

-- the equipped gun's Range setting (server rejects hits past it); fallback 350
local function equippedRange(tool)
    local s = tool and tool:FindFirstChild("Settings")
    local r = s and s:FindFirstChild("Range")
    return (r and r.Value) or 350
end

--======================================================================
-- snapline (from the user's silent aim; optional)
--======================================================================
local snapline
pcall(function()
    snapline = Drawing.new("Line")
    snapline.Thickness = 1
    snapline.Transparency = 0.5
    snapline.Color = Color3.new(1, 0, 1)
    snapline.Visible = false
end)

--======================================================================
-- target + cache update loop (all the method calls live here, NOT in the hook)
--======================================================================
RunService.Heartbeat:Connect(function()
    if FEAT.Ragebot then
        target = nearestByDistance()
    elseif FEAT.SilentAim then
        target = nearestToCrosshair()
    else
        target = nil
    end

    -- refresh cache for the namecall hook
    cache.targetPart = target and getHitPart(target) or nil

    local tool = equippedTool()
    local gs = tool and tool:FindFirstChild("GunServer")
    cache.dmgRemote = gs and gs:FindFirstChild("Damage") or nil

    if FEAT.KillAll and FEAT.Ragebot then
        local root = lplr.Character and (lplr.Character:FindFirstChild("HumanoidRootPart") or lplr.Character:FindFirstChild("Torso"))
        local range = equippedRange(tool)
        local parts = {}
        if root then
            for _, plr in ipairs(Players:GetPlayers()) do
                if isEnemy(plr) and plr.Character then
                    local part = getHitPart(plr.Character)
                    if part and (part.Position - root.Position).Magnitude <= range then
                        parts[#parts + 1] = part
                    end
                end
            end
        end
        cache.enemyParts = parts
    else
        cache.enemyParts = {}
    end

    if snapline then
        if FEAT.Snapline and cache.targetPart then
            local sp, on = camera:WorldToViewportPoint(cache.targetPart.Position)
            if on then
                snapline.From = UserInputService:GetMouseLocation()
                snapline.To = v2(sp.X, sp.Y)
                snapline.Visible = true
            else
                snapline.Visible = false
            end
        else
            snapline.Visible = false
        end
    end
end)

--======================================================================
-- weapon-setting mods (RapidFire / NoSpread) + InfAmmo, applied from inside
-- the fire hook where u66's frame is level 3.
--======================================================================
local origCache = setmetatable({}, { __mode = "k" })
local function applyGunMods(gun)
    local o = origCache[gun]
    if not o then
        o = { Period = gun.Period, Spread = gun.Spread, MinSpread = gun.MinSpread, MaxSpread = gun.MaxSpread }
        origCache[gun] = o
    end

    if FEAT.RapidFire then
        gun.Period = math.clamp(60 / FEAT.RapidRPM, 0.005, math.max(o.Period, 0.005))
    else
        gun.Period = o.Period
    end

    if FEAT.NoSpread then
        gun.Spread, gun.MinSpread, gun.MaxSpread = 0, 0, 0
    else
        gun.Spread, gun.MinSpread, gun.MaxSpread = o.Spread, o.MinSpread, o.MaxSpread
    end

    if FEAT.InfAmmo then
        local ok, cur = pcall(getupvalue, 3, 1)
        if ok and type(cur) == "number" and type(gun.MaxAmmo) == "number" then
            pcall(setupvalue, 3, 1, gun.MaxAmmo)
        end
    end
end

--======================================================================
-- (1) task.spawn hook: gun-stat mods + aim the bullet path at the target so
--     a Damage event always fires (bullet hits the target or a wall in line).
--======================================================================
local oldspawn
oldspawn = hookfunction(task.spawn, newcclosure(function(a0, ...)
    if checkcaller() or type(a0) ~= "function" then return oldspawn(a0, ...) end
    if not info(3, "s"):find("GunLocal") then return oldspawn(a0, ...) end
    if typeof((...)) ~= "CFrame" then return oldspawn(a0, ...) end

    local ok, gun = pcall(getupvalue, 3, 12)
    if ok and type(gun) == "table" then
        pcall(applyGunMods, gun)

        if (FEAT.SilentAim or FEAT.Ragebot) and cache.targetPart then
            if math.random(1, 100) <= FEAT.HitChance then
                local origin = getstack(3, 12)
                if typeof(origin) == "CFrame" then
                    -- aim straight at the target part; the Damage override
                    -- below reports the real hit, so no drop/lead is needed.
                    setstack(3, 17, lookAt(origin.Position, cache.targetPart.Position))
                end
            end
        end
    end

    return oldspawn(a0, ...)
end))

--======================================================================
-- (2) __namecall hook on the Fire/Damage remotes. METHOD-CALL FREE: it only
--     reads properties and mutates the argument tables, using the Heartbeat
--     cache. Through-walls hit override + Kill All.
--======================================================================
local hashTarget = {}   -- bullet hash -> target part Instance (per shot)

if hookmetamethod and getnamecall then
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        -- read the method FIRST and make no method calls before oldNamecall
        if checkcaller() then return oldNamecall(self, ...) end
        local method = getnamecall()
        if method ~= "FireServer" then return oldNamecall(self, ...) end
        if typeof(self) ~= "Instance" then return oldNamecall(self, ...) end

        local par = self.Parent                 -- __index, safe
        if not par or par.Name ~= "GunServer" then return oldNamecall(self, ...) end
        if not (FEAT.SilentAim or FEAT.Ragebot) then return oldNamecall(self, ...) end

        local rname = self.Name                 -- __index, safe

        -- Fire: rewrite each bullet Orgin to aim at the target; append a
        -- bullet per enemy for Kill All.
        if rname == "Fire" then
            local tp = cache.targetPart
            if not tp then return oldNamecall(self, ...) end
            local list = (...)
            if type(list) ~= "table" or type(list[1]) ~= "table" or typeof(list[1].Orgin) ~= "CFrame" then
                return oldNamecall(self, ...)
            end
            local muzzle = list[1].Orgin.Position   -- property read, safe
            local tpPos = tp.Position
            for _, b in ipairs(list) do
                if typeof(b.Orgin) == "CFrame" and b.Hash then
                    b.Orgin = lookAt(muzzle, tpPos)
                    hashTarget[b.Hash] = tp
                end
            end

            if FEAT.KillAll then
                local dmgRemote = cache.dmgRemote
                local n = #list
                for _, ep in ipairs(cache.enemyParts) do
                    if ep ~= tp then
                        n = n + 1
                        local h = tostring(lplr.UserId) .. "/" .. tostring(os.clock()) .. "/X" .. n
                        local epPos = ep.Position
                        list[n] = { Hash = h, Orgin = lookAt(muzzle, epPos) }
                        hashTarget[h] = ep
                        -- appended bullets have no client sim, so emit their
                        -- Damage ourselves (deferred -> bypasses this hook).
                        if dmgRemote then
                            task.delay(0.04, function()
                                if ep.Parent then
                                    pcall(function()
                                        dmgRemote:FireServer({ Instance = ep, CFrame = cnew(ep.Position), Size = ep.Size }, h)
                                    end)
                                end
                            end)
                        end
                    end
                end
            end

            return oldNamecall(self, list)
        end

        -- Damage: override the reported hit with the bullet's intended target.
        if rname == "Damage" then
            local hit, hash = ...
            if type(hit) == "table" then
                local tp = (hash and hashTarget[hash]) or cache.targetPart
                if tp and tp.Parent then
                    hit.Instance = tp
                    hit.CFrame   = cnew(tp.Position)
                    hit.Size     = tp.Size
                    if hash then hashTarget[hash] = nil end
                    return oldNamecall(self, hit, hash)
                end
            end
            return oldNamecall(self, ...)
        end

        return oldNamecall(self, ...)
    end))
else
    log("WARNING: hookmetamethod/getnamecallmethod unavailable - through-walls disabled")
end

--======================================================================
-- Ragebot autofire: pulse the equipped tool. For automatic guns a single
-- Activate() sprays; for semi-auto each Activate() is one shot.
--======================================================================
local firing = false
task.spawn(function()
    while true do
        local tool = equippedTool()
        if FEAT.Ragebot and target and tool then
            pcall(function() tool:Activate() end)
            firing = true
            task.wait(FEAT.RagebotDelay)
        else
            if firing and tool then pcall(function() tool:Deactivate() end) end
            firing = false
            task.wait(0.05)
        end
    end
end)

--======================================================================
-- UI
--======================================================================
local window = BN:Window({ Name = "$$ banknote: D.I.G $$" })
pcall(function() window:Watermark({ Name = "$$ banknote $$" }) end)
pcall(function() window:KeybindList() end)

local combat = window:Page({ Name = "Combat" })
local aimSec = combat:Section({ Name = "Aimbot", Side = 1 })
local gunSec = combat:Section({ Name = "Weapon", Side = 2 })

local flagN = 0
local function uflag() flagN = flagN + 1 return "dig_" .. flagN end

local function addToggle(section, label, key)
    local t = section:Toggle({ Name = label, Flag = uflag(), Default = false,
        Callback = function(v) FEAT[key] = v and true or false end })
    if t and t.Keybind then
        pcall(function()
            t:Keybind({ Name = label, Flag = uflag(), Mode = "Toggle",
                Callback = function(toggled)
                    FEAT[key] = toggled and true or false
                    if t.Set then pcall(function() t:Set(FEAT[key]) end) end
                end })
        end)
    end
    return t
end

local function addSlider(section, label, key, min, max, default, step, suffix)
    FEAT[key] = default
    pcall(function()
        section:Slider({ Name = label, Flag = uflag(), Min = min, Max = max, Default = default,
            Decimals = step or 1, Suffix = suffix or "",
            Callback = function(v) FEAT[key] = v end })
    end)
end

-- Aimbot section
addToggle(aimSec, "Silent Aim", "SilentAim")
addToggle(aimSec, "Ragebot", "Ragebot")
addToggle(aimSec, "Kill All (Ragebot)", "KillAll")
pcall(function()
    aimSec:Dropdown({ Name = "Hit Part", Flag = uflag(),
        Items = { "Head", "Torso", "HumanoidRootPart" }, Default = "Head", Multi = false,
        Callback = function(v)
            if type(v) == "table" then v = v[1] end
            FEAT.HitPart = (type(v) == "string" and v) or "Head"
        end })
end)
addSlider(aimSec, "Hit Chance", "HitChance", 0, 100, 100, 1, "%")
aimSec:Toggle({ Name = "Team Check", Flag = uflag(), Default = true,
    Callback = function(v) FEAT.TeamCheck = v and true or false end })
addToggle(aimSec, "FOV", "FOVEnabled")
addSlider(aimSec, "FOV Radius", "FOVRadius", 30, 1000, 150, 1, "px")
addSlider(aimSec, "Ragebot Delay", "RagebotDelay", 0.03, 1, 0.06, 0.01, "s")
addToggle(aimSec, "Snapline", "Snapline")

-- Weapon section
addToggle(gunSec, "No Spread", "NoSpread")
addToggle(gunSec, "Infinite Ammo", "InfAmmo")
addToggle(gunSec, "Rapid Fire", "RapidFire")
addSlider(gunSec, "Fire Rate", "RapidRPM", 60, 3000, 1200, 1, "rpm")

log("loaded")
