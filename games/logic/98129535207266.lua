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
-- NOTE: the server enforces the gun's Range on the REAL target position (a hit
-- reported past Range is rejected; faking a closer hit position does NOT work),
-- so Ragebot/Kill All only land on enemies within range (350 on the rifle).
--
-- Weapon mods read the live GunLocal fire frame. Different guns are different
-- scripts with different upvalue/stack layouts, so we FIND the frame level
-- dynamically and SCAN its upvalues for the settings table (by its keys) and
-- the ammo counter (integer upvalue <= MaxAmmo) - never hardcoded indices.
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
    SilentAim     = false,
    HitPart       = "Head",
    HitChance     = 100,
    FOVEnabled    = false,
    FOVRadius     = 150,
    ShowFOVCircle = false,
    FOVColor      = Color3.fromRGB(255, 255, 255),
    TeamCheck     = true,
    WallCheck     = false,
    -- ragebot
    Ragebot       = false,
    RageHitPart   = "Head",
    RagebotDelay  = 0.06,
    KillAll       = false,
    KillAllDelay  = 0.25,
    -- weapon mods
    NoSpread      = false,
    InfAmmo       = false,
    RapidFire     = false,
    RapidRPM      = 1200,
}

local target = nil  -- current target Character (Model) for silent/rage

local cache = {
    targetPart = nil,   -- Instance: current target's hit part
    settings   = nil,   -- table: equipped gun's live settings table (for pinning)
}

local pinGunSettings  -- forward declaration (used by the Heartbeat below)

--======================================================================
-- helpers
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

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
local function losClear(fromPos, part)
    losParams.FilterDescendantsInstances = { lplr.Character, part.Parent }
    return workspace:Raycast(fromPos, part.Position - fromPos, losParams) == nil
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
-- FOV circle visual (MVSD-style: ScreenGui + Frame + UICorner + UIStroke)
--======================================================================
do
    local guiParent = (gethui and gethui()) or lplr:WaitForChild("PlayerGui")
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "BanknoteDIGFOV"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.DisplayOrder = 999999
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
    screenGui.Parent = guiParent

    local circle = Instance.new("Frame")
    circle.Size = UDim2.fromOffset(300, 300)
    circle.AnchorPoint = Vector2.new(0.5, 0.5)
    circle.BackgroundTransparency = 1
    circle.BorderSizePixel = 0
    circle.Visible = false
    circle.Parent = screenGui

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = circle

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(255, 255, 255)
    stroke.Thickness = 2
    stroke.Parent = circle

    RunService.RenderStepped:Connect(function()
        if FEAT.ShowFOVCircle then
            local r = FEAT.FOVRadius or 150
            circle.Size = UDim2.fromOffset(r * 2, r * 2)
            stroke.Color = FEAT.FOVColor or Color3.fromRGB(255, 255, 255)
            local mp = UserInputService:GetMouseLocation()
            circle.Position = UDim2.fromOffset(mp.X, mp.Y)
            circle.Visible = true
        else
            circle.Visible = false
        end
    end)
end

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

    -- continuously pin weapon-mod settings on the cached gun table so the mods
    -- apply immediately (not only on the next shot).
    if cache.settings then pcall(pinGunSettings, cache.settings) end
end)

--======================================================================
-- weapon-setting mods. RapidFire/NoSpread mutate the live settings table;
-- InfAmmo refills the ammo upvalue (needs the live frame -> done in the hook).
--======================================================================
local origCache = setmetatable({}, { __mode = "k" })
pinGunSettings = function(gun)
    if type(gun) ~= "table" then return end
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
end

local function findGunUpvalues(lvl)
    local settings, ammoIdx
    for i = 1, 30 do
        local ok, v = pcall(getupvalue, lvl, i)
        if not ok then break end
        if not settings and type(v) == "table"
            and rawget(v, "Period") ~= nil and rawget(v, "Spread") ~= nil
            and rawget(v, "BulletSpeed") ~= nil and rawget(v, "MaxAmmo") ~= nil then
            settings = v
        end
    end
    if not settings then return nil end
    for i = 1, 30 do
        local ok, v = pcall(getupvalue, lvl, i)
        if not ok then break end
        if type(v) == "number" and v == math.floor(v) and v >= 0 and v <= settings.MaxAmmo then
            ammoIdx = i
            break
        end
    end
    return settings, ammoIdx
end

--======================================================================
-- (1) task.spawn hook: caches the live settings table, pins the mods, refills
--     ammo. GunLocal fire frame level found dynamically.
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
    if lvl then
        local gun, ammoIdx = findGunUpvalues(lvl)
        if gun then
            cache.settings = gun
            pcall(pinGunSettings, gun)
            if FEAT.InfAmmo and ammoIdx and type(gun.MaxAmmo) == "number" then
                pcall(setupvalue, lvl, ammoIdx, gun.MaxAmmo)
            end
        end
    end

    return oldspawn(a0, ...)
end))

--======================================================================
-- (2) __namecall hook: take over the reported hit (through walls). METHOD-CALL
--     FREE - only reads properties + mutates arg tables.
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
-- (Server enforces gun Range on the real target position, so out-of-range
-- enemies can't be hit - a D.I.G map limitation, not a bug.)
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

-- feature toggle WITH a keybind (main features)
local function addFeature(section, label, key)
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

-- plain config toggle, NO keybind
local function addToggle(section, label, key, default)
    return section:Toggle({ Name = label, Flag = uflag(), Default = default and true or false,
        Callback = function(v) FEAT[key] = v and true or false end })
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
addFeature(silentS, "Silent Aim", "SilentAim")
addHitPart(silentS, "Hit Part", "HitPart")
addSlider(silentS, "Hit Chance", "HitChance", 0, 100, 100, 1, "%")
addToggle(silentS, "FOV", "FOVEnabled", false)
addSlider(silentS, "FOV Radius", "FOVRadius", 30, 1000, 150, 1, "px")
addToggle(silentS, "Show FOV Circle", "ShowFOVCircle", false)
pcall(function()
    silentS:Label({ Name = "FOV Color" }):Colorpicker({
        Name = "FOV Color", Flag = uflag(), Default = FEAT.FOVColor,
        Callback = function(color) FEAT.FOVColor = color end })
end)
addToggle(silentS, "Team Check", "TeamCheck", true)
addToggle(silentS, "Wall Check", "WallCheck", false)

-- Ragebot section
addFeature(rageS, "Ragebot", "Ragebot")
addHitPart(rageS, "Ragebot Hit Part", "RageHitPart")
addSlider(rageS, "Ragebot Delay", "RagebotDelay", 0.03, 1, 0.06, 0.01, "s")
addFeature(rageS, "Kill All", "KillAll")
addSlider(rageS, "Kill All Delay", "KillAllDelay", 0.1, 2, 0.25, 0.01, "s")

-- Weapon Mods section
addFeature(weaponS, "No Spread", "NoSpread")
addFeature(weaponS, "Infinite Ammo", "InfAmmo")
addFeature(weaponS, "Rapid Fire", "RapidFire")
addSlider(weaponS, "Fire Rate", "RapidRPM", 60, 3000, 1200, 1, "rpm")

-- finalize: adds the default Settings tab (Theming/Profiles/Autoload/Menu)
pcall(function() window:Init() end)

log("loaded")
