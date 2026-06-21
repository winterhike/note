--======================================================================
-- $$ banknote $$  -  D.I.G  (PlaceId 98129535207266, universe 7304084567)
--
-- D.I.G is a sandbox shooter. Each gun is a Tool with a client-side GunLocal
-- LocalScript that drives firing. The hit system is CLIENT-AUTHORITATIVE:
-- GunLocal raycasts each bullet's flight path and, on hit, reports the hit
-- instance to the server (GunServer.Damage:FireServer). So redirecting the
-- bullet's origin CFrame (the value passed to the bullet-sim task.spawn)
-- makes the client's own raycast strike whoever we want -> the server trusts
-- it. This is exactly how the user's existing silent aim works.
--
-- GunLocal internals (decompiled):
--   * u66 (fire fn) builds, per bullet, v62 = CFrame.lookAt(origin, origin+dir)
--     where dir = applySpread(aimUnit, currentSpread), then
--     task.spawn(u48 --[bullet sim]--, v62, muzzle, hash).
--   * In u66's frame: upvalue 1  = current ammo (l__MaxAmmo__18)
--                     upvalue 12 = settings table u4 (BulletSpeed, Step,
--                                  Period=60/RPM, Spread, MinSpread, MaxSpread,
--                                  MaxAmmo, ...)
--                     stack slot 12 = the bullet origin CFrame (read)
--                     stack slot 17 = the CFrame arg handed to the sim (write)
--     (these magic indices are the ones the user's working silent aim uses.)
--   * Auto guns: u69 loops `while u7 do u66() task.wait(u4.Period) end`, so
--     lowering u4.Period = faster fire, and a single Tool:Activate() sprays.
--
-- All combat features funnel through ONE task.spawn hook:
--   SilentAim / Ragebot -> rewrite the bullet CFrame to the target.
--   NoSpread            -> zero the settings spread fields.
--   RapidFire           -> shrink u4.Period.
--   InfAmmo             -> refill the ammo upvalue every shot.
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
local info        = debug.info
local getstack    = getstack
local setstack    = setstack
local getupvalue  = getupvalue or debug.getupvalue
local setupvalue  = setupvalue or debug.setupvalue
local hookfunction= hookfunction or replaceclosure
local newcclosure = newcclosure or function(f) return f end
local checkcaller = checkcaller or function() return false end
local lookAt      = CFrame.lookAt
local v3          = Vector3.new
local v2          = Vector2.new

local function log(...) print("[banknote/D.I.G]", ...) end

--======================================================================
-- feature state
--======================================================================
local FEAT = {
    SilentAim   = false,
    Ragebot     = false,
    NoSpread    = false,
    InfAmmo     = false,
    RapidFire   = false,

    TeamCheck   = true,
    FOVEnabled  = false,
    FOVRadius   = 150,
    HitPart     = "Head",
    HitChance   = 100,
    RapidRPM    = 1200,
    RagebotDelay= 0.08,
    Snapline    = false,
}

local target = nil  -- current target Character (Model) for silent/rage

--======================================================================
-- target selection
--======================================================================
local function isEnemy(plr)
    if plr == lplr then return false end
    if FEAT.TeamCheck and lplr.Team and plr.Team == lplr.Team then return false end
    return true
end

-- a live, hittable part on the character (preferred hit part, else fallbacks)
local function getHitPart(char)
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return nil end
    return char:FindFirstChild(FEAT.HitPart)
        or char:FindFirstChild("Head")
        or char:FindFirstChild("HumanoidRootPart")
        or char:FindFirstChild("Torso")
end

-- nearest enemy to the crosshair (optionally inside FOV) -- used by SilentAim
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

-- nearest enemy by world distance -- used by Ragebot (aims regardless of view)
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
-- weapon-setting mods (RapidFire / NoSpread) + InfAmmo
-- applied from inside the fire hook, where u66's frame is level 3.
--======================================================================
local origCache = setmetatable({}, { __mode = "k" })
local function applyGunMods(gun)
    local o = origCache[gun]
    if not o then
        o = { Period = gun.Period, Spread = gun.Spread, MinSpread = gun.MinSpread, MaxSpread = gun.MaxSpread }
        origCache[gun] = o
    end

    -- RapidFire: shrink the auto-loop wait (can't exceed the real rate upward)
    if FEAT.RapidFire then
        gun.Period = math.clamp(60 / FEAT.RapidRPM, 0.005, math.max(o.Period, 0.005))
    else
        gun.Period = o.Period
    end

    -- NoSpread: zero every spread field the spread solver reads
    if FEAT.NoSpread then
        gun.Spread, gun.MinSpread, gun.MaxSpread = 0, 0, 0
    else
        gun.Spread, gun.MinSpread, gun.MaxSpread = o.Spread, o.MinSpread, o.MaxSpread
    end

    -- InfAmmo: top the ammo counter (upvalue 1 of u66) back up each shot so it
    -- never reaches 0 and never triggers a reload.
    if FEAT.InfAmmo then
        local ok, cur = pcall(getupvalue, 3, 1)
        if ok and type(cur) == "number" and type(gun.MaxAmmo) == "number" then
            pcall(setupvalue, 3, 1, gun.MaxAmmo)
        end
    end
end

--======================================================================
-- master fire hook (silent aim / ragebot / nospread / rapidfire / infammo)
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
                    local bs   = rawget(gun, "BulletSpeed") or gun.BulletSpeed
                    local step = rawget(gun, "Step") or gun.Step
                    if type(bs) == "number" and bs > 0 then
                        local travelTime = (part.Position - origin.Position).Magnitude / bs
                        local drop = 0.5 * workspace.Gravity * travelTime * (travelTime - (step or 0))
                        local aim  = part.Position + (part.AssemblyLinearVelocity * travelTime) + v3(0, drop, 0)
                        setstack(3, 17, lookAt(origin.Position, aim))
                    end
                end
            end
        end
    end

    return oldspawn(a0, ...)
end))

--======================================================================
-- Ragebot autofire: pulse the equipped tool. For automatic guns a single
-- Activate() starts the spray; for semi-auto each Activate() is one shot.
-- The fire hook above redirects every bullet to `target`.
--======================================================================
local firing = false
task.spawn(function()
    while true do
        local char = lplr.Character
        local tool = char and char:FindFirstChildOfClass("Tool")
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
pcall(function()
    aimSec:Dropdown({ Name = "Hit Part", Flag = uflag(),
        Items = { "Head", "Torso", "HumanoidRootPart" }, Default = "Head", Multi = false,
        Callback = function(v) FEAT.HitPart = v end })
end)
addSlider(aimSec, "Hit Chance", "HitChance", 0, 100, 100, 1, "%")
local teamT = aimSec:Toggle({ Name = "Team Check", Flag = uflag(), Default = true,
    Callback = function(v) FEAT.TeamCheck = v and true or false end })
addToggle(aimSec, "FOV", "FOVEnabled")
addSlider(aimSec, "FOV Radius", "FOVRadius", 30, 1000, 150, 1, "px")
addSlider(aimSec, "Ragebot Delay", "RagebotDelay", 0.03, 1, 0.08, 0.01, "s")
addToggle(aimSec, "Snapline", "Snapline")

-- Weapon section
addToggle(gunSec, "No Spread", "NoSpread")
addToggle(gunSec, "Infinite Ammo", "InfAmmo")
addToggle(gunSec, "Rapid Fire", "RapidFire")
addSlider(gunSec, "Fire Rate", "RapidRPM", 60, 3000, 1200, 1, "rpm")

log("loaded")
