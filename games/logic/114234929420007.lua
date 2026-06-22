--======================================================================
-- $$ banknote $$  -  BloxStrike  (PlaceId 114234929420007, universe 7633926880)
--
-- BloxStrike is a CS-style shooter whose matches run on per-match sub-places
-- (all resolved to this id via the loader's universe map). The gun internals
-- (fire/damage remotes) were NOT reverse-engineered yet (no live capture was
-- available when this was authored), so this ships GENERIC features that work
-- via standard Roblox APIs on the game's standard Humanoid characters:
--   * Camera Aimbot (FOV target select, smoothing, team/wall check, FOV circle)
--   * ESP (boxes, names, health bars, tracers, distance) via the Drawing API
--   * Movement (walk speed, jump power, infinite jump, fly, noclip)
--   * World (fullbright, field of view, no fog)
-- When a live client is available these can be upgraded to a true silent aim
-- by hooking the gun's fire remote.
--
-- Marker for the loader: BanknoteLibrary
--======================================================================
if getgenv()._BloxStrikeLoaded then return end
getgenv()._BloxStrikeLoaded = true

local BN = getgenv().BanknoteLibrary
assert(BN, "[banknote] BanknoteLibrary not set by loader")

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting         = game:GetService("Lighting")

local lplr   = Players.LocalPlayer
local camera = workspace.CurrentCamera
local mouse  = lplr:GetMouse()

local v2     = Vector2.new
local v3     = Vector3.new
local cnew   = CFrame.new
local lookAt = CFrame.lookAt

local function log(...) print("[banknote/BloxStrike]", ...) end

--======================================================================
-- feature state
--======================================================================
local FEAT = {
    -- aimbot
    Aimbot        = false,
    AimPart       = "Head",
    Smoothness    = 0.5,
    FOVEnabled    = true,
    FOVRadius     = 150,
    ShowFOVCircle = false,
    FOVColor      = Color3.fromRGB(255, 255, 255),
    TeamCheck     = true,
    WallCheck     = true,
    AimKeyEnabled = false,   -- if true, only aim while AimKey is held
    AimKey        = Enum.UserInputType.MouseButton2,
    -- esp
    ESP           = false,
    BoxESP        = true,
    NameESP       = true,
    HealthESP     = true,
    TracerESP     = false,
    DistanceESP   = false,
    ESPTeamCheck  = true,
    ESPColor      = Color3.fromRGB(255, 60, 60),
    TracerOrigin  = "Bottom",
    -- movement
    WalkSpeed     = false,
    WalkSpeedVal  = 32,
    JumpPower     = false,
    JumpPowerVal  = 75,
    InfJump       = false,
    Fly           = false,
    FlySpeed      = 60,
    NoClip        = false,
    -- world
    Fullbright    = false,
    FOV           = 70,
    NoFog         = false,
}

--======================================================================
-- helpers
--======================================================================
local function getChar() return lplr.Character end
local function getHum()
    local c = getChar()
    return c and c:FindFirstChildOfClass("Humanoid")
end
local function getRoot()
    local c = getChar()
    return c and (c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart)
end

local function isEnemy(plr, teamCheckOn)
    if plr == lplr then return false end
    if teamCheckOn and lplr.Team and plr.Team and plr.Team == lplr.Team then
        return false
    end
    return true
end

local function getPartByName(char, partName)
    if not char then return nil end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum or hum.Health <= 0 then return nil end
    return char:FindFirstChild(partName)
        or char:FindFirstChild("Head")
        or char:FindFirstChild("HumanoidRootPart")
        or char:FindFirstChild("UpperTorso")
        or char:FindFirstChild("Torso")
end

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
local function losClear(fromPos, part)
    losParams.FilterDescendantsInstances = { getChar(), part.Parent }
    local dir = part.Position - fromPos
    local res = workspace:Raycast(fromPos, dir, losParams)
    return res == nil
end

--======================================================================
-- AIMBOT (camera based)
--======================================================================
local function nearestToCrosshair()
    local mloc = UserInputService:GetMouseLocation()
    local camPos = camera.CFrame.Position
    local best, bestPart, bestd
    for _, plr in ipairs(Players:GetPlayers()) do
        if isEnemy(plr, FEAT.TeamCheck) and plr.Character then
            local part = getPartByName(plr.Character, FEAT.AimPart)
            if part then
                local sp, on = camera:WorldToViewportPoint(part.Position)
                if on then
                    local d = (v2(sp.X, sp.Y) - mloc).Magnitude
                    if (not FEAT.FOVEnabled or d <= FEAT.FOVRadius)
                        and (not FEAT.WallCheck or losClear(camPos, part)) then
                        if not bestd or d < bestd then
                            best, bestPart, bestd = plr, part, d
                        end
                    end
                end
            end
        end
    end
    return best, bestPart
end

local function aimKeyHeld()
    if not FEAT.AimKeyEnabled then return true end
    local k = FEAT.AimKey
    if typeof(k) == "EnumItem" and k.EnumType == Enum.UserInputType then
        return UserInputService:IsMouseButtonPressed(k)
    elseif typeof(k) == "EnumItem" then
        return UserInputService:IsKeyDown(k)
    end
    return false
end

RunService.RenderStepped:Connect(function(dt)
    if not FEAT.Aimbot then return end
    if not aimKeyHeld() then return end
    local _, part = nearestToCrosshair()
    if not part then return end
    local goal = lookAt(camera.CFrame.Position, part.Position)
    local alpha = 1 - math.clamp(FEAT.Smoothness, 0, 0.97)
    camera.CFrame = camera.CFrame:Lerp(goal, alpha)
end)

--======================================================================
-- FOV CIRCLE
--======================================================================
local fovCircle = Drawing.new("Circle")
fovCircle.Thickness = 1.5
fovCircle.NumSides = 64
fovCircle.Filled = false
fovCircle.Visible = false
RunService.RenderStepped:Connect(function()
    if FEAT.ShowFOVCircle and FEAT.Aimbot then
        local m = UserInputService:GetMouseLocation()
        fovCircle.Position = v2(m.X, m.Y)
        fovCircle.Radius = FEAT.FOVRadius
        fovCircle.Color = FEAT.FOVColor
        fovCircle.Visible = true
    else
        fovCircle.Visible = false
    end
end)

--======================================================================
-- ESP (Drawing API)
--======================================================================
local espObjects = {}  -- [player] = { box, name, healthBg, healthBar, tracer, distance }

local function newText()
    local t = Drawing.new("Text")
    t.Size = 13
    t.Center = true
    t.Outline = true
    t.Font = 2
    t.Visible = false
    return t
end

local function createESP(plr)
    espObjects[plr] = {
        box       = Drawing.new("Square"),
        name      = newText(),
        healthBg  = Drawing.new("Line"),
        healthBar = Drawing.new("Line"),
        tracer    = Drawing.new("Line"),
        distance  = newText(),
    }
    local o = espObjects[plr]
    o.box.Thickness = 1
    o.box.Filled = false
    o.box.Visible = false
    o.healthBg.Thickness = 3
    o.healthBg.Color = Color3.fromRGB(0, 0, 0)
    o.healthBg.Visible = false
    o.healthBar.Thickness = 1
    o.healthBar.Visible = false
    o.tracer.Thickness = 1
    o.tracer.Visible = false
end

local function destroyESP(plr)
    local o = espObjects[plr]
    if not o then return end
    for _, d in pairs(o) do pcall(function() d:Remove() end) end
    espObjects[plr] = nil
end

for _, plr in ipairs(Players:GetPlayers()) do
    if plr ~= lplr then createESP(plr) end
end
Players.PlayerAdded:Connect(function(plr) if plr ~= lplr then createESP(plr) end end)
Players.PlayerRemoving:Connect(destroyESP)

local function hideESP(o)
    o.box.Visible = false
    o.name.Visible = false
    o.healthBg.Visible = false
    o.healthBar.Visible = false
    o.tracer.Visible = false
    o.distance.Visible = false
end

RunService.RenderStepped:Connect(function()
    for plr, o in pairs(espObjects) do
        if not FEAT.ESP or not plr.Character or not isEnemy(plr, FEAT.ESPTeamCheck) then
            hideESP(o)
        else
            local char = plr.Character
            local hum = char:FindFirstChildOfClass("Humanoid")
            local root = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
            local head = char:FindFirstChild("Head")
            if not hum or not root or hum.Health <= 0 then
                hideESP(o)
            else
                local topPos = (head and head.Position or root.Position) + v3(0, 0.5, 0)
                local botPos = root.Position - v3(0, 3, 0)
                local topSp, topOn = camera:WorldToViewportPoint(topPos)
                local botSp = camera:WorldToViewportPoint(botPos)
                if not topOn then
                    hideESP(o)
                else
                    local h = math.abs(topSp.Y - botSp.Y)
                    local w = h * 0.5
                    local x = topSp.X - w / 2
                    local y = topSp.Y
                    local col = FEAT.ESPColor

                    -- box
                    if FEAT.BoxESP then
                        o.box.Size = v2(w, h)
                        o.box.Position = v2(x, y)
                        o.box.Color = col
                        o.box.Visible = true
                    else o.box.Visible = false end

                    -- name
                    if FEAT.NameESP then
                        o.name.Text = plr.Name
                        o.name.Position = v2(topSp.X, y - 16)
                        o.name.Color = col
                        o.name.Visible = true
                    else o.name.Visible = false end

                    -- health bar (left side)
                    if FEAT.HealthESP then
                        local hp = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
                        local bx = x - 5
                        o.healthBg.From = v2(bx, y)
                        o.healthBg.To = v2(bx, y + h)
                        o.healthBg.Visible = true
                        o.healthBar.From = v2(bx, y + h)
                        o.healthBar.To = v2(bx, y + h - h * hp)
                        o.healthBar.Color = Color3.fromRGB(255 - math.floor(255 * hp), math.floor(255 * hp), 0)
                        o.healthBar.Visible = true
                    else
                        o.healthBg.Visible = false
                        o.healthBar.Visible = false
                    end

                    -- distance
                    if FEAT.DistanceESP then
                        local dist = (camera.CFrame.Position - root.Position).Magnitude
                        o.distance.Text = string.format("%dm", math.floor(dist))
                        o.distance.Position = v2(topSp.X, y + h + 2)
                        o.distance.Color = col
                        o.distance.Visible = true
                    else o.distance.Visible = false end

                    -- tracer
                    if FEAT.TracerESP then
                        local vp = camera.ViewportSize
                        local origin
                        if FEAT.TracerOrigin == "Center" then
                            origin = v2(vp.X / 2, vp.Y / 2)
                        elseif FEAT.TracerOrigin == "Mouse" then
                            local m = UserInputService:GetMouseLocation()
                            origin = v2(m.X, m.Y)
                        else
                            origin = v2(vp.X / 2, vp.Y)
                        end
                        o.tracer.From = origin
                        o.tracer.To = v2(topSp.X, y + h)
                        o.tracer.Color = col
                        o.tracer.Visible = true
                    else o.tracer.Visible = false end
                end
            end
        end
    end
end)

--======================================================================
-- MOVEMENT
--======================================================================
-- walk speed / jump power applied each frame so the game can't reset them
RunService.Heartbeat:Connect(function()
    local hum = getHum()
    if not hum then return end
    if FEAT.WalkSpeed then hum.WalkSpeed = FEAT.WalkSpeedVal end
    if FEAT.JumpPower then
        pcall(function() hum.UseJumpPower = true end)
        hum.JumpPower = FEAT.JumpPowerVal
        pcall(function() hum.JumpHeight = FEAT.JumpPowerVal / 10 end)
    end
end)

-- infinite jump
UserInputService.JumpRequest:Connect(function()
    if FEAT.InfJump then
        local hum = getHum()
        if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end
end)

-- noclip
RunService.Stepped:Connect(function()
    if not FEAT.NoClip then return end
    local char = getChar()
    if not char then return end
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") and p.CanCollide then
            p.CanCollide = false
        end
    end
end)

-- fly
local flying = false
local flyBV, flyBG
local function startFly()
    local root = getRoot()
    if not root then return end
    flying = true
    flyBV = Instance.new("BodyVelocity")
    flyBV.MaxForce = v3(1, 1, 1) * 9e9
    flyBV.Velocity = v3(0, 0, 0)
    flyBV.Parent = root
    flyBG = Instance.new("BodyGyro")
    flyBG.MaxForce = v3(1, 1, 1) * 9e9
    flyBG.P = 1000
    flyBG.CFrame = root.CFrame
    flyBG.Parent = root
end
local function stopFly()
    flying = false
    if flyBV then flyBV:Destroy(); flyBV = nil end
    if flyBG then flyBG:Destroy(); flyBG = nil end
end

RunService.RenderStepped:Connect(function()
    if FEAT.Fly then
        if not flying then startFly() end
        local root = getRoot()
        if not root or not flyBV then return end
        flyBG.CFrame = camera.CFrame
        local dir = v3(0, 0, 0)
        local cf = camera.CFrame
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + cf.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - cf.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - cf.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + cf.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + v3(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir = dir - v3(0, 1, 0) end
        if dir.Magnitude > 0 then dir = dir.Unit * FEAT.FlySpeed end
        flyBV.Velocity = dir
    else
        if flying then stopFly() end
    end
end)

--======================================================================
-- WORLD
--======================================================================
local savedLighting
RunService.Heartbeat:Connect(function()
    if FEAT.Fullbright then
        Lighting.Brightness = 2
        Lighting.ClockTime = 14
        Lighting.GlobalShadows = false
        Lighting.Ambient = Color3.fromRGB(178, 178, 178)
        Lighting.OutdoorAmbient = Color3.fromRGB(178, 178, 178)
    end
    if FEAT.NoFog then
        Lighting.FogEnd = 1e9
        Lighting.FogStart = 1e9
    end
    camera.FieldOfView = FEAT.FOV
end)

--======================================================================
-- UI
--======================================================================
local window = BN:Window({ Name = "$$ banknote: BloxStrike $$" })
pcall(function() window:Watermark({ Name = "$$ banknote $$" }) end)
pcall(function() window:KeybindList() end)

local combat   = window:Page({ Name = "Combat" })
local aimS     = combat:Section({ Name = "Aimbot", Side = 1 })
local fovS     = combat:Section({ Name = "FOV", Side = 2 })

local visuals  = window:Page({ Name = "Visuals" })
local espS     = visuals:Section({ Name = "ESP", Side = 1 })

local misc     = window:Page({ Name = "Misc" })
local moveS    = misc:Section({ Name = "Movement", Side = 1 })
local worldS   = misc:Section({ Name = "World", Side = 2 })

local flagN = 0
local function uflag() flagN = flagN + 1 return "bs_" .. flagN end

local function addFeature(section, label, key)
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

local function addToggle(section, label, key, default)
    FEAT[key] = default and true or false
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

local function addPartDropdown(section, label, key)
    pcall(function()
        section:Dropdown({ Name = label, Flag = uflag(),
            Items = { "Head", "UpperTorso", "Torso", "HumanoidRootPart" },
            Default = FEAT[key], Multi = false,
            Callback = function(v)
                if type(v) == "table" then v = v[1] end
                FEAT[key] = (type(v) == "string" and v) or "Head"
            end })
    end)
end

local function addColor(section, label, key)
    pcall(function()
        section:Label({ Name = label }):Colorpicker({
            Name = label, Flag = uflag(), Default = FEAT[key],
            Callback = function(color) FEAT[key] = color end })
    end)
end

-- Aimbot section
addFeature(aimS, "Aimbot", "Aimbot")
addPartDropdown(aimS, "Aim Part", "AimPart")
addSlider(aimS, "Smoothness", "Smoothness", 0, 0.95, 0.5, 0.05, "")
addToggle(aimS, "Aim Key Only", "AimKeyEnabled", false)
addToggle(aimS, "Team Check", "TeamCheck", true)
addToggle(aimS, "Wall Check", "WallCheck", true)

-- FOV section
addToggle(fovS, "FOV Limit", "FOVEnabled", true)
addSlider(fovS, "FOV Radius", "FOVRadius", 30, 1000, 150, 1, "px")
addToggle(fovS, "Show FOV Circle", "ShowFOVCircle", false)
addColor(fovS, "FOV Color", "FOVColor")

-- ESP section
addFeature(espS, "ESP", "ESP")
addToggle(espS, "Boxes", "BoxESP", true)
addToggle(espS, "Names", "NameESP", true)
addToggle(espS, "Health Bars", "HealthESP", true)
addToggle(espS, "Tracers", "TracerESP", false)
pcall(function()
    espS:Dropdown({ Name = "Tracer Origin", Flag = uflag(),
        Items = { "Bottom", "Center", "Mouse" }, Default = "Bottom", Multi = false,
        Callback = function(v)
            if type(v) == "table" then v = v[1] end
            FEAT.TracerOrigin = (type(v) == "string" and v) or "Bottom"
        end })
end)
addToggle(espS, "Distance", "DistanceESP", false)
addToggle(espS, "Team Check", "ESPTeamCheck", true)
addColor(espS, "ESP Color", "ESPColor")

-- Movement section
addFeature(moveS, "Walk Speed", "WalkSpeed")
addSlider(moveS, "Walk Speed Value", "WalkSpeedVal", 16, 200, 32, 1, "")
addFeature(moveS, "Jump Power", "JumpPower")
addSlider(moveS, "Jump Power Value", "JumpPowerVal", 50, 400, 75, 1, "")
addFeature(moveS, "Infinite Jump", "InfJump")
addFeature(moveS, "Fly", "Fly")
addSlider(moveS, "Fly Speed", "FlySpeed", 10, 300, 60, 1, "")
addFeature(moveS, "No Clip", "NoClip")

-- World section
addToggle(worldS, "Fullbright", "Fullbright", false)
addToggle(worldS, "No Fog", "NoFog", false)
addSlider(worldS, "Field of View", "FOV", 30, 120, 70, 1, "")

-- finalize: adds the default Settings tab (Theming/Profiles/Autoload/Menu)
pcall(function() window:Init() end)

log("loaded")
