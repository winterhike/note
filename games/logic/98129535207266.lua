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
-- target makes the bullet report the WALL (the old ragebot's problem: it
-- "just shoots" and walls eat the bullets). The fix, like Vape/PF ragebots,
-- is to take over the reported hit:
--   * rewrite the Fire Orgin to point at the target (trajectory stays
--     consistent with the hit the server is told about), and
--   * override the Damage Instance/CFrame/Size to the target's body part,
--     so the hit lands on them THROUGH walls.
-- Kill All additionally appends one bullet per enemy to each Fire and emits a
-- matching Damage, so a single trigger pull tags everyone in range.
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

--======================================================================
-- target selection helpers
--======================================================================
local function isEnemy(plr)
    if plr == lplr then return false end
    if FEAT.TeamCheck and lplr.Team and plr.Team == lplr.Team then return false end
    return true
end

-- a live, hittable part on a character (preferred hit part, then fallbacks)
local function getHitPart(char)
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return nil end
    return char:FindFirstChild(FEAT.HitPart)
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

-- every alive enemy whose hit part is within `range` studs of origin
local function enemiesInRange(origin, range)
    local out = {}
    for _, plr in ipairs(Players:GetPlayers()) do
        if isEnemy(plr) and plr.Character then
            local part = getHitPart(plr.Character)
            if part and (part.Position - origin).Magnitude <= range then
                out[#out + 1] = plr.Character
            end
        end
    end
    return out
end

local function equippedTool()
    local char = lplr.Character
    return char and char:FindFirstChildOfClass("Tool")
end

-- the equipped gun's Range setting (server rejects hits past it); fallback 350
local function equippedRange()
    local tool = equippedTool()
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
-- target update loop
--======================================================================
RunService.Heartbeat:Connect(function()
    if FEAT.Ragebot then
        target = nearestByDistance()
    elseif FEAT.SilentAim then
        target = nearestToCrosshair()
    else
        target = nil
    end

    if snapline then
        if FEAT.Snapline and target then
            local part = getHitPart(target)
            local sp, on = part and camera:WorldToViewportPoint(part.Position)
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

        if (FEAT.SilentAim or FEAT.Ragebot) and target then
            if math.random(1, 100) <= FEAT.HitChance then
                local part = getHitPart(target)
                local origin = getstack(3, 12)
                if part and typeof(origin) == "CFrame" then
                    -- aim straight at the target part; the Damage override
                    -- below reports the real hit, so no drop/lead is needed.
                    setstack(3, 17, lookAt(origin.Position, part.Position))
                end
            end
        end
    end

    return oldspawn(a0, ...)
end))

--======================================================================
-- (2) __namecall hook on the Fire/Damage remotes: take over the reported hit
--     so shots land on the target THROUGH walls, and (Kill All) tag everyone.
--======================================================================
local hashTarget = {}   -- bullet hash -> target Character (per shot)

local function uniqueHash(i)
    return tostring(lplr.UserId) .. "/" .. tostring(os.clock()) .. "/X" .. tostring(i)
end

if hookmetamethod and getnamecall then
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        if checkcaller() or typeof(self) ~= "Instance" then
            return oldNamecall(self, ...)
        end
        local method = getnamecall()
        if method ~= "FireServer" then return oldNamecall(self, ...) end
        local par = self.Parent
        if not (par and par.Name == "GunServer") then return oldNamecall(self, ...) end
        if not (FEAT.SilentAim or FEAT.Ragebot) or not target then return oldNamecall(self, ...) end

        -- Fire: rewrite each bullet's Orgin to aim at the target; optionally
        -- append a bullet per enemy for Kill All.
        if self.Name == "Fire" then
            local args = { ... }
            local list = args[1]
            if type(list) == "table" and list[1] and typeof(list[1].Orgin) == "CFrame" then
                local muzzle = list[1].Orgin.Position
                local tp = getHitPart(target)
                if tp then
                    for _, b in ipairs(list) do
                        if typeof(b.Orgin) == "CFrame" and b.Hash then
                            b.Orgin = lookAt(muzzle, tp.Position)
                            hashTarget[b.Hash] = target
                        end
                    end

                    if FEAT.KillAll then
                        local dmgRemote = par:FindFirstChild("Damage")
                        local range = equippedRange()
                        for _, ec in ipairs(enemiesInRange(muzzle, range)) do
                            if ec ~= target then
                                local ep = getHitPart(ec)
                                if ep then
                                    local h = uniqueHash(#list)
                                    list[#list + 1] = { Hash = h, Orgin = lookAt(muzzle, ep.Position) }
                                    hashTarget[h] = ec
                                    -- the appended bullets have no client sim,
                                    -- so emit their Damage ourselves shortly after.
                                    if dmgRemote then
                                        task.delay(0.04, function()
                                            local p = getHitPart(ec)
                                            if p then
                                                pcall(function()
                                                    dmgRemote:FireServer({ Instance = p, CFrame = cnew(p.Position), Size = p.Size }, h)
                                                end)
                                            end
                                        end)
                                    end
                                end
                            end
                        end
                    end
                    return oldNamecall(self, list)
                end
            end
            return oldNamecall(self, ...)
        end

        -- Damage: override the reported hit with the bullet's intended target,
        -- so walls don't matter.
        if self.Name == "Damage" then
            local args = { ... }
            local hit, hash = args[1], args[2]
            local tgtChar = (hash and hashTarget[hash]) or target
            if type(hit) == "table" and tgtChar then
                local tp = getHitPart(tgtChar)
                if tp then
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
-- Activate() sprays; for semi-auto each Activate() is one shot. The hooks
-- above redirect every bullet onto the target(s).
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
        Callback = function(v) FEAT.HitPart = v end })
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
