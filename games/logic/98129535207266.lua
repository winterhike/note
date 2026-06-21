--======================================================================
-- $$ banknote $$  -  D.I.G  (PlaceId 98129535207266, universe 7304084567)
--
-- D.I.G is a sandbox shooter. Each gun is a Tool with a client-side GunLocal
-- LocalScript. The hit system is CLIENT-AUTHORITATIVE (confirmed by spy + live
-- test - a fabricated Fire+Damage pair deals exactly HeadDamage):
--   1. GunServer.Fire:FireServer({ {Hash=str, Orgin=CFrame}, ... })
--   2. GunServer.Damage:FireServer({Instance=part, CFrame=CFrame.new(pos),
--        Size=part.Size}, hash)   -- client reports what it hit; server trusts.
-- The client's own raycast picks the hit, so a wall makes the bullet report
-- the WALL. We take over the report: aim the Fire Orgin at the target and
-- override the Damage Instance to the target's body part -> hits THROUGH walls.
-- Kill All fires self-contained Fire+Damage shots at every enemy in range.
--
-- GunLocal internals (decompiled + verified live). The fire frame (u66) sits
-- at a stack level that depends on the executor's hook depth, so we FIND it
-- dynamically (scan for "GunLocal") instead of hardcoding. In that frame:
--   upvalue 1  = current ammo (number)
--   upvalue 12 = settings table (Period=60/RPM, Spread, MinSpread, MaxSpread,
--                BulletSpeed, MaxAmmo, ...)
--   stack 12   = bullet origin CFrame (read)
--   stack 17   = CFrame handed to the bullet sim (write to redirect)
-- (The old code hardcoded level 3 -> wrong frame -> weapon mods silently did
-- nothing. The real level is 4 under this executor.)
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
    -- silent aim
    SilentAim   = false,
    HitPart     = "Head",
    HitChance   = 100,
    FOVEnabled  = false,
    FOVRadius   = 150,
    TeamCheck   = true,
    WallCheck   = false,
    -- ragebot
    Ragebot     = false,
    RageHitPart = "Head",
    RagebotDelay= 0.06,
    KillAll     = false,
    KillAllDelay= 0.25,
    -- weapon mods
    NoSpread    = false,
    InfAmmo     = false,
    RapidFire   = false,
    RapidRPM    = 1200,
    -- misc
    Snapline    = false,
}

local target = nil  -- current target Character (Model) for silent/rage

-- precomputed each Heartbeat so the __namecall hook never calls a method
local cache = {
    targetPart = nil,  -- Instance: current target's hit part
}

--======================================================================
-- helpers (only called OUTSIDE the __namecall hook)
--======================================================================
local function isEnemy(plr)
    if plr == lplr then return false end
    if FEAT.TeamCheck and lplr.Team and plr.Team == lplr.Team then return false end
    return true
end

local function getHitPart(char, partName)
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return nil end
    local hp = type(partName) == "string" and partName or "Head"
    return char:FindFirstChild(hp)
        or char:FindFirstChild("Head")
        or char:FindFirstChild("HumanoidRootPart")
        or char:FindFirstChild("Torso")
end

-- line of sight from `fromPos` to a part (ignores us + the target's own model)
local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
local function losClear(fromPos, part)
    losParams.FilterDescendantsInstances = { lplr.Character, part.Parent }
    local res = workspace:Raycast(fromPos, part.Position - fromPos, losParams)
    return res == nil
end

local function nearestToCrosshair()
    local mouse = UserInputService:GetMouseLocation()
    local camPos = camera.CFrame.Position
    local best, bestd
    for _, plr in ipairs(Players:GetPlayers()) do
        if isEnemy(plr) and plr.Character then
            local part = getHitPart(plr.Character, FEAT.HitPart)
            if part then
                local sp, on = camera:WorldToViewportPoint(part.Position)
                if on and (not FEAT.WallCheck or losClear(camPos, part)) then
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

local function myOrigin()
    local c = lplr.Character
    local r = c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso"))
    return r and r.Position
end

local function nearestByDistance()
    local origin = myOrigin()
    if not origin then return nil end
    local best, bestd
    for _, plr in ipairs(Players:GetPlayers()) do
        if isEnemy(plr) and plr.Character then
            local part = getHitPart(plr.Character, FEAT.RageHitPart)
            if part then
                local d = (part.Position - origin).Magnitude
                if not bestd or d < bestd then best, bestd = plr.Character, d end
            end
        end
    end
    return best
end

local function equippedGun()
    local char = lplr.Character
    local tool = char and char:FindFirstChildOfClass("Tool")
    if tool and tool:FindFirstChild("GunServer") and tool:FindFirstChild("Settings") then
        return tool
    end
    return nil
end

--======================================================================
-- snapline (optional)
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
-- target + cache update loop
--======================================================================
RunService.Heartbeat:Connect(function()
    if FEAT.Ragebot then
        target = nearestByDistance()
        cache.targetPart = target and getHitPart(target, FEAT.RageHitPart) or nil
    elseif FEAT.SilentAim then
        target = nearestToCrosshair()
        cache.targetPart = target and getHitPart(target, FEAT.HitPart) or nil
    else
        target = nil
        cache.targetPart = nil
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
-- weapon-setting mods (RapidFire / NoSpread) + InfAmmo
--======================================================================
local origCache = setmetatable({}, { __mode = "k" })
local function applyGunMods(gun, lvl)
    local o = origCache[gun]
    if not o then
        o = { Period = gun.Period, Spread = gun.Spread, MinSpread = gun.MinSpread, MaxSpread = gun.MaxSpread }
        origCache[gun] = o
    end

    if FEAT.RapidFire then
        gun.Period = math.clamp(60 / FEAT.RapidRPM, 0.005, math.max(o.Period or 0.1, 0.005))
    elseif o.Period then
        gun.Period = o.Period
    end

    if FEAT.NoSpread then
        gun.Spread, gun.MinSpread, gun.MaxSpread = 0, 0, 0
    else
        gun.Spread, gun.MinSpread, gun.MaxSpread = o.Spread, o.MinSpread, o.MaxSpread
    end

    if FEAT.InfAmmo then
        local ok, cur = pcall(getupvalue, lvl, 1)
        if ok and type(cur) == "number" and type(gun.MaxAmmo) == "number" then
            pcall(setupvalue, lvl, 1, gun.MaxAmmo)
        end
    end
end

--======================================================================
-- (1) task.spawn hook: gun-stat mods + aim the bullet at the target. The
--     GunLocal fire frame level is found dynamically (it was NOT 3).
--======================================================================
local oldspawn
oldspawn = hookfunction(task.spawn, newcclosure(function(a0, ...)
    if checkcaller() or type(a0) ~= "function" then return oldspawn(a0, ...) end
    if typeof((...)) ~= "CFrame" then return oldspawn(a0, ...) end

    local lvl
    for L = 2, 8 do
        local ok, src = pcall(info, L, "s")
        if ok and type(src) == "string" and src:find("GunLocal") then lvl = L break end
    end
    if not lvl then return oldspawn(a0, ...) end

    local ok, gun = pcall(getupvalue, lvl, 12)
    if ok and type(gun) == "table" then
        pcall(applyGunMods, gun, lvl)

        if (FEAT.SilentAim or FEAT.Ragebot) and cache.targetPart then
            local origin = getstack(lvl, 12)
            if typeof(origin) == "CFrame" then
                setstack(lvl, 17, lookAt(origin.Position, cache.targetPart.Position))
            end
        end
    end

    return oldspawn(a0, ...)
end))

--======================================================================
-- (2) __namecall hook: take over the reported hit (through walls). METHOD-CALL
--     FREE - it only reads properties + mutates the arg tables (a method call
--     here would corrupt the namecall dispatch).
--======================================================================
if hookmetamethod and getnamecall then
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        if checkcaller() then return oldNamecall(self, ...) end
        local method = getnamecall()
        if method ~= "FireServer" then return oldNamecall(self, ...) end
        if typeof(self) ~= "Instance" then return oldNamecall(self, ...) end
        local par = self.Parent
        if not par or par.Name ~= "GunServer" then return oldNamecall(self, ...) end
        if not (FEAT.SilentAim or FEAT.Ragebot) then return oldNamecall(self, ...) end

        local tp = cache.targetPart
        if not tp then return oldNamecall(self, ...) end
        local rname = self.Name

        if rname == "Fire" then
            local list = (...)
            if type(list) == "table" and type(list[1]) == "table" and typeof(list[1].Orgin) == "CFrame" then
                local muzzle = list[1].Orgin.Position
                local tpPos = tp.Position
                for _, b in ipairs(list) do
                    if typeof(b.Orgin) == "CFrame" and b.Hash then
                        b.Orgin = lookAt(muzzle, tpPos)
                    end
                end
                return oldNamecall(self, list)
            end
            return oldNamecall(self, ...)
        end

        if rname == "Damage" then
            local hit = (...)
            if type(hit) == "table" and tp.Parent and math.random(1, 100) <= FEAT.HitChance then
                hit.Instance = tp
                hit.CFrame   = cnew(tp.Position)
                hit.Size     = tp.Size
            end
            return oldNamecall(self, ...)
        end

        return oldNamecall(self, ...)
    end))
else
    log("WARNING: hookmetamethod/getnamecallmethod unavailable - through-walls disabled")
end

--======================================================================
-- Ragebot autofire: pulse the equipped tool so the hooks redirect each shot.
--======================================================================
local firing = false
task.spawn(function()
    while true do
        local tool = lplr.Character and lplr.Character:FindFirstChildOfClass("Tool")
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
-- Kill All: fire self-contained Fire+Damage shots at EVERY enemy in range.
-- (Proven live: a fabricated Fire+Damage pair deals full damage.) Independent
-- of the gun trigger; rate-limited to avoid server kicks.
--======================================================================
task.spawn(function()
    while true do
        if FEAT.KillAll then
            local tool = equippedGun()
            local origin = myOrigin()
            if tool and origin then
                local gs = tool.GunServer
                local fireR, dmgR = gs:FindFirstChild("Fire"), gs:FindFirstChild("Damage")
                local sRange = tool.Settings:FindFirstChild("Range")
                local sSpeed = tool.Settings:FindFirstChild("BulletSpeed")
                local range  = (sRange and sRange.Value) or 350
                local speed  = (sSpeed and sSpeed.Value) or 1000
                local muzzle = origin + v3(0, 1.5, 0)
                if fireR and dmgR then
                    for _, plr in ipairs(Players:GetPlayers()) do
                        if isEnemy(plr) and plr.Character then
                            local part = getHitPart(plr.Character, FEAT.RageHitPart)
                            if part and (part.Position - muzzle).Magnitude <= range then
                                local hash = tostring(lplr.UserId) .. "/" .. tostring(tick()) .. "/" .. plr.Name
                                local pos = part.Position
                                pcall(function() fireR:FireServer({ { Orgin = lookAt(muzzle, pos), Hash = hash } }) end)
                                local delay = math.clamp((pos - muzzle).Magnitude / speed, 0.03, 0.35)
                                task.delay(delay, function()
                                    if part.Parent then
                                        pcall(function() dmgR:FireServer({ Instance = part, CFrame = cnew(part.Position), Size = part.Size }, hash) end)
                                    end
                                end)
                            end
                        end
                    end
                end
            end
            task.wait(FEAT.KillAllDelay)
        else
            task.wait(0.15)
        end
    end
end)

--======================================================================
-- UI
--======================================================================
local window = BN:Window({ Name = "$$ banknote: D.I.G $$" })
pcall(function() window:Watermark({ Name = "$$ banknote $$" }) end)
pcall(function() window:KeybindList() end)

local combat   = window:Page({ Name = "Combat" })
local silentS  = combat:Section({ Name = "Silent Aim", Side = 1 })
local rageS    = combat:Section({ Name = "Ragebot", Side = 2 })
local weaponS  = combat:Section({ Name = "Weapon Mods", Side = 1 })

local flagN = 0
local function uflag() flagN = flagN + 1 return "dig_" .. flagN end

local function addToggle(section, label, key)
    local t = section:Toggle({ Name = label, Flag = uflag(), Default = FEAT[key] and true or false,
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

local function addHitPart(section, label, key)
    pcall(function()
        section:Dropdown({ Name = label, Flag = uflag(),
            Items = { "Head", "Torso", "HumanoidRootPart", "Left Arm", "Right Arm", "Left Leg", "Right Leg" },
            Default = FEAT[key], Multi = false,
            Callback = function(v)
                if type(v) == "table" then v = v[1] end
                FEAT[key] = (type(v) == "string" and v) or "Head"
            end })
    end)
end

-- Silent Aim section
addToggle(silentS, "Silent Aim", "SilentAim")
addHitPart(silentS, "Hit Part", "HitPart")
addSlider(silentS, "Hit Chance", "HitChance", 0, 100, 100, 1, "%")
addToggle(silentS, "FOV", "FOVEnabled")
addSlider(silentS, "FOV Radius", "FOVRadius", 30, 1000, 150, 1, "px")
silentS:Toggle({ Name = "Team Check", Flag = uflag(), Default = true,
    Callback = function(v) FEAT.TeamCheck = v and true or false end })
addToggle(silentS, "Wall Check", "WallCheck")

-- Ragebot section
addToggle(rageS, "Ragebot", "Ragebot")
addHitPart(rageS, "Ragebot Hit Part", "RageHitPart")
addSlider(rageS, "Ragebot Delay", "RagebotDelay", 0.03, 1, 0.06, 0.01, "s")
addToggle(rageS, "Kill All", "KillAll")
addSlider(rageS, "Kill All Delay", "KillAllDelay", 0.1, 2, 0.25, 0.01, "s")

-- Weapon Mods section
addToggle(weaponS, "No Spread", "NoSpread")
addToggle(weaponS, "Infinite Ammo", "InfAmmo")
addToggle(weaponS, "Rapid Fire", "RapidFire")
addSlider(weaponS, "Fire Rate", "RapidRPM", 60, 3000, 1200, 1, "rpm")
addToggle(weaponS, "Snapline", "Snapline")

log("loaded")
