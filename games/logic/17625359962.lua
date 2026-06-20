--[[
    $$ banknote $$ - Rivals Logic (PlaceId: 17625359962)
    Core game logic extracted from Instance.lua, wired to banknote UI flags.
    Library.Flags["FlagName"] is used to read toggle/slider/dropdown states.
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Camera = workspace.CurrentCamera
local LocalPlayer = Players.LocalPlayer

-- Wait for game to load
repeat task.wait(0.1) until game:IsLoaded()
repeat task.wait(0.1) until LocalPlayer.Parent
repeat task.wait(0.1) until LocalPlayer:FindFirstChild("PlayerScripts")
task.wait(0.8)

-- Safe require utility
local function safeRequire(moduleRef, timeout)
    local deadline = timeout and (os.clock() + timeout) or (os.clock() + 10)
    while os.clock() < deadline do
        if typeof(moduleRef) == "Instance" and not moduleRef.Parent then
            task.wait(0.1)
        else
            local ok, result = pcall(require, moduleRef)
            if ok then return result end
            task.wait(0.1)
        end
    end
    return nil
end

-- Load Rivals modules
local Utility = safeRequire(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("Utility", 8))
local EnumLibrary = safeRequire(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("EnumLibrary", 8))

local localFighter = nil
local camController = nil

pcall(function()
    local ctrl = LocalPlayer.PlayerScripts:WaitForChild("Controllers", 10)
    local cm = ctrl:FindFirstChild("CameraController")
    if cm and cm:IsA("ModuleScript") then camController = require(cm) end
    local fm = ctrl:FindFirstChild("FighterController")
    if fm and fm:IsA("ModuleScript") then
        local fc = require(fm)
        localFighter = fc.LocalFighter
    end
end)

-- Uncap FPS
pcall(function() if setfpscap then setfpscap(0) end end)


---------------------------------------------------------------
-- UTILITY FUNCTIONS
---------------------------------------------------------------

local function worldToScreen(worldPos, cam)
    cam = cam or workspace.CurrentCamera
    if not cam or not worldPos then return nil, false end
    local v, onScreen = cam:WorldToViewportPoint(worldPos)
    if not onScreen or v.Z <= 0 then return v, false end
    return v, true
end

local function screenCenter(cam)
    cam = cam or workspace.CurrentCamera
    if not cam then return Vector2.zero end
    local vs = cam.ViewportSize
    return Vector2.new(vs.X * 0.5, vs.Y * 0.5)
end

local function curweap()
    local vm = Workspace:FindFirstChild("ViewModels")
    if not vm then return nil end
    local fp = vm:FindFirstChild("FirstPerson")
    if not fp then return nil end
    for _, child in ipairs(fp:GetChildren()) do
        local parts = {}
        for p in child.Name:gmatch("[^-]+") do
            table.insert(parts, p:match("^%s*(.-)%s*$"))
        end
        if #parts >= 2 then return parts[2] end
    end
    return nil
end

local restricteditems = {
    "Flamethrower","Fists","Battle Axe","Chainsaw","Katana","Knife",
    "Riot Shield","Scythe","Maul","Trowel","Grenade","Flashbang",
    "Jump Pad","Molotov","Satchel","Smoke Grenade","War Horn",
    "Medkit","Subspace Tripmine","Warpstone"
}

local function weaponRestricted(weaponName)
    if not weaponName then return false end
    for _, w in ipairs(restricteditems) do
        if weaponName == w then return true end
    end
    return false
end

local function muzzlePos()
    local vm = Workspace:FindFirstChild("ViewModels")
    if not vm then return nil end
    local fp = vm:FindFirstChild("FirstPerson")
    if not fp then return nil end
    for _, model in pairs(fp:GetChildren()) do
        if model:IsA("Model") and model.Name:find("^" .. LocalPlayer.Name) then
            local iv = model:FindFirstChild("ItemVisual")
            if iv then
                local b = iv:FindFirstChild("Body")
                if b then
                    local bp = b:FindFirstChild("BodyPrimary")
                    if bp then
                        local muzzle = bp:FindFirstChild("_muzzle")
                        if muzzle and muzzle:IsA("Attachment") then
                            return muzzle.WorldPosition
                        end
                    end
                end
            end
        end
    end
    return nil
end

local function hitpartFromName(target, partName)
    local fc = function(n) return target:FindFirstChild(n) end
    if partName == "Head" then return fc("Head")
    elseif partName == "HumanoidRootPart" then return fc("HumanoidRootPart")
    elseif partName == "Torso" then return fc("Torso") or fc("UpperTorso")
    elseif partName == "UpperTorso" then return fc("UpperTorso")
    elseif partName == "LowerTorso" then return fc("LowerTorso")
    elseif partName == "Left Arm" then return fc("Left Arm") or fc("LeftUpperArm")
    elseif partName == "Right Arm" then return fc("Right Arm") or fc("RightUpperArm")
    elseif partName == "Left Leg" then return fc("Left Leg") or fc("LeftUpperLeg")
    elseif partName == "Right Leg" then return fc("Right Leg") or fc("RightUpperLeg")
    elseif partName == "Closest" then
        local camPos = Camera.CFrame.Position
        local camLook = Camera.CFrame.LookVector
        local best, bestD = nil, math.huge
        for _, part in pairs(target:GetChildren()) do
            if part:IsA("BasePart") then
                local d = 1 - camLook:Dot((part.Position - camPos).Unit)
                if d < bestD then bestD = d; best = part end
            end
        end
        return best or fc("HumanoidRootPart")
    elseif partName == "Random" then
        local list = {}
        for _, part in pairs(target:GetChildren()) do
            if part:IsA("BasePart") then table.insert(list, part) end
        end
        if #list > 0 then return list[math.random(1, #list)] end
    end
    return target:FindFirstChild("HumanoidRootPart")
end


---------------------------------------------------------------
-- ANTI KATANA
---------------------------------------------------------------

local katanausers = {}

local function detectKatana()
    task.spawn(function()
        local katana, attempts = nil, 0
        while attempts < 10 do
            pcall(function()
                for _, m in pairs(LocalPlayer.PlayerScripts:GetDescendants()) do
                    if m.Name == "Katana" and m:IsA("ModuleScript") then
                        local ok, res = pcall(require, m)
                        if ok then katana = res end
                    end
                end
            end)
            if katana and type(katana) == "table" and katana.StartAiming then break end
            attempts += 1
            task.wait(1)
        end
        if katana and type(katana) == "table" and katana.StartAiming then
            local old = katana.StartAiming
            katana.StartAiming = function(self, force)
                local fighter = self.ClientFighter
                local player = fighter and fighter.Player
                if player then
                    katanausers[player] = true
                    local dur = self.Info.DeflectDuration or 0.6
                    task.delay(dur, function() katanausers[player] = nil end)
                end
                return old(self, force)
            end
        end
    end)
end
detectKatana()

---------------------------------------------------------------
-- SILENT AIM
---------------------------------------------------------------

local lastFireTime = 0
local fireCooldown = 0.05
local curtarget = nil

local function getFlags()
    return getgenv().BanknoteFlags or {}
end

local function closestInFOV(radius, center)
    local closest, closestDist = nil, math.huge
    local cam = workspace.CurrentCamera
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local char = player.Character
            if char then
                local hum = char:FindFirstChildOfClass("Humanoid")
                if hum and hum.Health > 0 and not char:FindFirstChildOfClass("ForceField") then
                    local root = char:FindFirstChild("HumanoidRootPart")
                    if root then
                        local pos, onScreen = worldToScreen(root.Position, cam)
                        if onScreen then
                            local dx = pos.X - center.X
                            local dy = pos.Y - center.Y
                            local dist = math.sqrt(dx * dx + dy * dy)
                            if dist <= radius and dist < closestDist then
                                closest = char
                                closestDist = dist
                            end
                        end
                    end
                end
            end
        end
    end
    return closest
end

local function fireSilent()
    local flags = getFlags()
    if not flags["SilentAim"] then return end
    local cw = curweap()
    if cw and weaponRestricted(cw) then return end
    local now = tick()
    if now - lastFireTime < fireCooldown then return end

    local hitChance = flags["HitChance"] or 100
    if hitChance < 100 and math.random(1, 100) > hitChance then return end

    local fovRadius = flags["FOVRadius"] or 100
    local center = screenCenter(workspace.CurrentCamera)
    local closest = closestInFOV(fovRadius, center)
    curtarget = closest
    if not closest then return end

    -- Anti Katana check
    if flags["AntiKatana"] then
        local tp = Players:GetPlayerFromCharacter(closest)
        if tp and katanausers[tp] then return end
    end

    local hitPart = flags["HitPartDropdown"] or "Head"
    local part = hitpartFromName(closest, hitPart)
    if not part then return end

    local myChar = LocalPlayer.Character
    local root = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not root then return end

    local equipped = localFighter and localFighter.EquippedItem
    if not equipped then return end
    local objId = equipped:Get("ObjectID")
    if not objId then return end

    lastFireTime = now
    local shootPos = root.Position
    local targetPos = part.Position
    local data = {
        [utf8.char(1)] = {
            [utf8.char(0)] = Utility:EncodeCFrame(CFrame.new(shootPos, targetPos)),
            [utf8.char(1)] = Utility:EncodeCFrame(CFrame.new(shootPos, targetPos)),
            [utf8.char(2)] = part,
            [utf8.char(3)] = Utility:EncodeCFrame(CFrame.new(0.43, 0.25, 0.42)),
        },
    }
    pcall(function()
        ReplicatedStorage.Remotes.Replication.Fighter.UseItem:FireServer(
            objId,
            EnumLibrary:ToEnum("StartShooting"),
            data,
            nil
        )
    end)
end

RunService.Heartbeat:Connect(function()
    local flags = getFlags()
    if flags["SilentAim"] then
        if flags["SilentAutoShoot"] or UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
            fireSilent()
        end
    end
end)


---------------------------------------------------------------
-- AIMBOT
---------------------------------------------------------------

local aimbotLocked = nil
local aimbotSmoothCF = nil

local function clearAimbotLock()
    aimbotLocked = nil
    aimbotSmoothCF = nil
end

local function closestToCursor(fovRadius)
    local best, bestDist = nil, fovRadius
    local mp = UserInputService:GetMouseLocation()
    local cam = workspace.CurrentCamera
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local flags = getFlags()
            local partName = flags["AimbotHitPart"] or "Head"
            local part = p.Character:FindFirstChild(partName)
            if part and part:IsDescendantOf(workspace) then
                local scr, on = worldToScreen(part.Position, cam)
                if on then
                    local dx = scr.X - mp.X
                    local dy = scr.Y - mp.Y
                    local dist = math.sqrt(dx * dx + dy * dy)
                    if dist < bestDist then
                        bestDist = dist
                        best = part
                    end
                end
            end
        end
    end
    return best
end

local function getAimbotAlpha(dt, smoothness, curve)
    local speed = 6 / math.clamp(smoothness, 0.1, 10)
    if curve == "Instant" then return 1
    elseif curve == "Expo" then return 1 - math.exp(-(4 / smoothness) * dt)
    elseif curve == "EaseIn" then local t = math.clamp(speed * dt, 0, 1); return t * t
    elseif curve == "EaseOut" then local t = math.clamp(speed * dt, 0, 1); return 1 - (1 - t) * (1 - t)
    elseif curve == "EaseInOut" then
        local t = math.clamp(speed * dt, 0, 1)
        if t < 0.5 then return 2 * t * t end
        return 1 - ((-2 * t + 2) ^ 2) / 2
    elseif curve == "Cubic" then local t = math.clamp(speed * dt, 0, 1); return t * t * t
    end
    return math.clamp(speed * dt, 0, 1)
end

local function stepAimbot(dt)
    local flags = getFlags()
    if not flags["AimbotToggle"] then
        clearAimbotLock()
        return
    end

    local cam = workspace.CurrentCamera
    if not cam then return end
    Camera = cam

    local fovRadius = flags["AimbotFOV"] or 500
    if not aimbotLocked then
        aimbotLocked = closestToCursor(fovRadius)
        aimbotSmoothCF = cam.CFrame
        if not aimbotLocked then return end
    end

    if not aimbotLocked.Parent or not aimbotLocked:IsDescendantOf(workspace) then
        clearAimbotLock()
        return
    end

    if not LocalPlayer.Character or not LocalPlayer.Character:FindFirstChild("Head") then
        clearAimbotLock()
        return
    end

    if not camController then return end
    if not aimbotSmoothCF then aimbotSmoothCF = cam.CFrame end

    local lookCF = CFrame.lookAt(cam.CFrame.Position, aimbotLocked.Position)
    local smoothness = flags["AimbotSmoothness"] or 2
    local curve = flags["AimbotCurve"] or "Linear"
    local alpha = getAimbotAlpha(dt, smoothness, curve)
    aimbotSmoothCF = aimbotSmoothCF:Lerp(lookCF, alpha)

    if camController.MimicRotation then
        pcall(function()
            camController:MimicRotation(aimbotSmoothCF)
        end)
    end
end

RunService:BindToRenderStep("BanknoteAimbot", Enum.RenderPriority.Camera.Value + 1, stepAimbot)


---------------------------------------------------------------
-- BACKSHOOT
---------------------------------------------------------------

local backshootConn = nil
local backshootTarget = nil
local backshootOrigCFrame = nil

local function startBackshoot()
    if backshootConn then backshootConn:Disconnect() end
    backshootConn = RunService.Heartbeat:Connect(function()
        local flags = getFlags()
        if not flags["BackshootToggle"] then
            if backshootConn then backshootConn:Disconnect(); backshootConn = nil end
            return
        end
        local myChar = LocalPlayer.Character
        if not myChar or not myChar:FindFirstChild("HumanoidRootPart") then return end
        if not backshootTarget then
            -- Find closest player
            local best, bestD = nil, math.huge
            local sc = screenCenter(workspace.CurrentCamera)
            for _, player in ipairs(Players:GetPlayers()) do
                if player ~= LocalPlayer and player.Character then
                    local root = player.Character:FindFirstChild("HumanoidRootPart")
                    if root then
                        local pos, on = worldToScreen(root.Position, workspace.CurrentCamera)
                        if on then
                            local d = (sc - Vector2.new(pos.X, pos.Y)).Magnitude
                            if d < bestD then best = player.Character; bestD = d end
                        end
                    end
                end
            end
            if best then
                backshootTarget = best
                backshootOrigCFrame = myChar.HumanoidRootPart.CFrame
            end
            return
        end
        local tr = backshootTarget:FindFirstChild("HumanoidRootPart")
        if not tr then backshootTarget = nil; return end
        local hum = backshootTarget:FindFirstChild("Humanoid")
        if not hum or hum.Health <= 0 then
            if backshootOrigCFrame then
                myChar.HumanoidRootPart.CFrame = backshootOrigCFrame
            end
            backshootTarget = nil
            return
        end
        local behind = tr.Position + (-tr.CFrame.LookVector * 5)
        myChar.HumanoidRootPart.CFrame = CFrame.new(behind, tr.Position)
    end)
end

task.defer(startBackshoot)

---------------------------------------------------------------
-- HIT SOUNDS
---------------------------------------------------------------

local soundAssets = {
    ["Rust HS"] = "rbxassetid://5043539486",
    ["Neverlose"] = "rbxassetid://97643101798871",
    ["Minecraft Bow"] = "rbxassetid://3442683707",
    ["CSGO"] = "rbxassetid://5764885315",
    ["Bubble"] = "rbxassetid://6534947588",
    ["Pop"] = "rbxassetid://198598793",
    ["Sans"] = "rbxassetid://3188795283",
    ["Skeet"] = "rbxassetid://5633695679",
    ["Fatality"] = "rbxassetid://6534947869",
    ["Bonk"] = "rbxassetid://5766898159",
    ["Osu"] = "rbxassetid://7149255551",
    ["TF2 Critical"] = "rbxassetid://296102734",
    ["Saber"] = "rbxassetid://8415678813",
}

local targetLastHP = setmetatable({}, {__mode = "k"})
local lastHitTime = 0

local function playHitSound()
    local flags = getFlags()
    local id = soundAssets[flags["HitSoundStyle"] or "Rust HS"]
    if not id then return end
    local snd = Instance.new("Sound")
    snd.SoundId = id
    snd.Volume = flags["HitSoundVolume"] or 1
    snd.Pitch = flags["HitSoundPitch"] or 1
    local cam = workspace.CurrentCamera
    if cam then
        local att = Instance.new("Attachment")
        att.Parent = cam
        snd.Parent = att
    else
        snd.Parent = workspace
    end
    snd:Play()
    game:GetService("Debris"):AddItem(snd, 5)
    if snd.Parent and snd.Parent:IsA("Attachment") then
        game:GetService("Debris"):AddItem(snd.Parent, 5)
    end
end

RunService.Heartbeat:Connect(function()
    local flags = getFlags()
    if not flags["HitSoundEnabled"] then return end
    if not curtarget then return end
    local char = curtarget
    if not char or not char.Parent then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local tp = Players:GetPlayerFromCharacter(char)
    if not tp then return end
    local lastHp = targetLastHP[tp] or hum.Health
    if hum.Health < lastHp then
        if tick() - lastHitTime > 0.05 then
            lastHitTime = tick()
            task.spawn(playHitSound)
        end
    end
    targetLastHP[tp] = hum.Health
end)

Players.PlayerRemoving:Connect(function(player)
    targetLastHP[player] = nil
end)


---------------------------------------------------------------
-- BULLET TRACERS
---------------------------------------------------------------

local textureAssets = {
    ["Line"] = "", ["Beam"] = "rbxassetid://12781852245",
    ["Lightning"] = "rbxassetid://446111271", ["Heartrate"] = "rbxassetid://5830549480",
    ["Chain"] = "rbxassetid://9632168658", ["Glitch"] = "rbxassetid://8089467613",
    ["Swirl"] = "rbxassetid://5638168605", ["Neon"] = "rbxassetid://6361963422",
    ["Plasma"] = "rbxassetid://8993645509", ["Laser"] = "rbxassetid://14549123968",
}

local function makeBulletTracer(startPos, endPos)
    local flags = getFlags()
    if not flags["BulletTracers"] then return end
    local style = flags["TracerStyle"] or "Line"
    local size = flags["TracerSize"] or 1
    local duration = flags["TracerDuration"] or 3
    local glow = flags["TracerGlow"] or 0
    local color = flags["TracerColor"] or Color3.new(1, 1, 1)

    local a0 = Instance.new("Attachment"); a0.Parent = workspace.Terrain
    local a1 = Instance.new("Attachment"); a1.Parent = workspace.Terrain
    local beam = Instance.new("Beam")
    beam.Attachment0 = a0
    beam.Attachment1 = a1
    beam.Color = ColorSequence.new(color)
    local bw = style == "Laser" and 0.02 or (style == "Line" and 0.05 or 0.15)
    beam.Width0 = bw * size
    beam.Width1 = bw * size
    beam.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0),
        NumberSequenceKeypoint.new(0.8, 0.1),
        NumberSequenceKeypoint.new(1, 0.5),
    })
    beam.FaceCamera = false
    beam.LightEmission = glow
    if style == "Line" then
        beam.Texture = ""
    elseif textureAssets[style] then
        beam.Texture = textureAssets[style]
        beam.TextureLength = 4
        beam.TextureSpeed = 1
    end
    beam.Parent = workspace.Terrain
    a0.WorldPosition = startPos
    a1.WorldPosition = endPos

    task.delay(duration, function()
        pcall(function() beam:Destroy() end)
        pcall(function() a0:Destroy() end)
        pcall(function() a1:Destroy() end)
    end)
end

-- Detect shots for bullet tracers
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    local flags = getFlags()
    if not flags["BulletTracers"] then return end
    local mp = muzzlePos()
    if not mp then
        local cam = workspace.CurrentCamera
        if cam then mp = cam.CFrame.Position + cam.CFrame.LookVector * 4 end
    end
    if not mp then return end
    local cam = workspace.CurrentCamera
    local endP = cam.CFrame.Position + cam.CFrame.LookVector * 1000
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {LocalPlayer.Character}
    params.FilterType = Enum.RaycastFilterType.Exclude
    local res = workspace:Raycast(mp, (endP - mp).Unit * 1000, params)
    if res then endP = res.Position end
    makeBulletTracer(mp, endP)
end)

---------------------------------------------------------------
-- MOVEMENT
---------------------------------------------------------------

local flyConn = nil
local flyBodyVel = nil
local flyBodyGyro = nil

RunService.Heartbeat:Connect(function()
    local flags = getFlags()
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end

    -- Speed
    if flags["SpeedHack"] then
        hum.WalkSpeed = flags["SpeedValue"] or 50
    end

    -- Infinite Jump
    if flags["InfJump"] then
        hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
    end

    -- No Clip
    if flags["NoClip"] then
        for _, part in pairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end
end)

-- Fly system
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    local flags = getFlags()
    if not flags["FlyEnabled"] then return end
    -- Fly is handled in heartbeat below
end)

RunService.Heartbeat:Connect(function()
    local flags = getFlags()
    local char = LocalPlayer.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    local hum = char:FindFirstChildOfClass("Humanoid")

    if flags["FlyEnabled"] then
        if not flyBodyVel then
            flyBodyVel = Instance.new("BodyVelocity")
            flyBodyVel.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
            flyBodyVel.Velocity = Vector3.zero
            flyBodyVel.Parent = root
            flyBodyGyro = Instance.new("BodyGyro")
            flyBodyGyro.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
            flyBodyGyro.P = 9e4
            flyBodyGyro.Parent = root
            if hum then hum.PlatformStand = true end
        end
        local speed = flags["FlySpeed"] or 50
        local cam = workspace.CurrentCamera
        local dir = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - cam.CFrame.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + cam.CFrame.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir = dir - Vector3.new(0, 1, 0) end
        if dir.Magnitude > 0 then dir = dir.Unit end
        flyBodyVel.Velocity = dir * speed
        flyBodyGyro.CFrame = cam.CFrame
    else
        if flyBodyVel then
            flyBodyVel:Destroy(); flyBodyVel = nil
            flyBodyGyro:Destroy(); flyBodyGyro = nil
            local hum2 = char:FindFirstChildOfClass("Humanoid")
            if hum2 then hum2.PlatformStand = false end
        end
    end
end)

-- Infinite Jump handler
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode ~= Enum.KeyCode.Space then return end
    local flags = getFlags()
    if not flags["InfJump"] then return end
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
    end
end)


---------------------------------------------------------------
-- VISUALS - ESP
---------------------------------------------------------------

local espObjects = {}

local function removeESP(player)
    if espObjects[player] then
        for _, obj in pairs(espObjects[player]) do
            pcall(function() obj:Remove() end)
        end
        espObjects[player] = nil
    end
end

local function createESP(player)
    if player == LocalPlayer then return end
    removeESP(player)
    local char = player.Character
    if not char then return end

    local objects = {}

    -- Box
    local box = Drawing.new("Square")
    box.Thickness = 1
    box.Filled = false
    box.Visible = false
    objects.box = box

    -- Name
    local name = Drawing.new("Text")
    name.Size = 14
    name.Center = true
    name.Outline = true
    name.Visible = false
    name.Text = player.DisplayName
    objects.name = name

    -- Tracer
    local tracer = Drawing.new("Line")
    tracer.Thickness = 1
    tracer.Visible = false
    objects.tracer = tracer

    -- Health bar
    local hpBg = Drawing.new("Square")
    hpBg.Thickness = 1
    hpBg.Filled = true
    hpBg.Visible = false
    hpBg.Color = Color3.new(0, 0, 0)
    objects.hpBg = hpBg

    local hpBar = Drawing.new("Square")
    hpBar.Thickness = 0
    hpBar.Filled = true
    hpBar.Visible = false
    objects.hpBar = hpBar

    espObjects[player] = objects
end

Players.PlayerAdded:Connect(function(p)
    p.CharacterAdded:Connect(function() task.wait(0.5); createESP(p) end)
end)
Players.PlayerRemoving:Connect(removeESP)
for _, p in ipairs(Players:GetPlayers()) do
    if p ~= LocalPlayer and p.Character then createESP(p) end
    p.CharacterAdded:Connect(function() task.wait(0.5); createESP(p) end)
end

RunService.RenderStepped:Connect(function()
    local flags = getFlags()
    local cam = workspace.CurrentCamera
    if not cam then return end
    local espColor = flags["ESPColor"] or Color3.fromRGB(255, 0, 0)

    for player, objects in pairs(espObjects) do
        local char = player.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        local head = char and char:FindFirstChild("Head")
        local hum = char and char:FindFirstChildOfClass("Humanoid")

        if not root or not hum or hum.Health <= 0 then
            for _, obj in pairs(objects) do obj.Visible = false end
            continue
        end

        local rootPos, onScreen = worldToScreen(root.Position, cam)
        if not onScreen then
            for _, obj in pairs(objects) do obj.Visible = false end
            continue
        end

        local headPos = worldToScreen(root.Position + Vector3.new(0, 3, 0), cam)
        local footPos = worldToScreen(root.Position - Vector3.new(0, 3, 0), cam)
        local height = math.abs(footPos.Y - headPos.Y)
        local width = height * 0.6

        -- Box ESP
        if flags["BoxESP"] then
            objects.box.Size = Vector2.new(width, height)
            objects.box.Position = Vector2.new(rootPos.X - width / 2, headPos.Y)
            objects.box.Color = espColor
            objects.box.Visible = true
        else
            objects.box.Visible = false
        end

        -- Name ESP
        if flags["NameESP"] then
            objects.name.Position = Vector2.new(rootPos.X, headPos.Y - 16)
            objects.name.Color = espColor
            objects.name.Visible = true
        else
            objects.name.Visible = false
        end

        -- Tracers
        if flags["Tracers"] then
            objects.tracer.From = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y)
            objects.tracer.To = Vector2.new(rootPos.X, footPos.Y)
            objects.tracer.Color = espColor
            objects.tracer.Visible = true
        else
            objects.tracer.Visible = false
        end

        -- Health Bar
        if flags["HealthBar"] then
            local hpFrac = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
            local barX = rootPos.X - width / 2 - 5
            objects.hpBg.Position = Vector2.new(barX - 1, headPos.Y - 1)
            objects.hpBg.Size = Vector2.new(3, height + 2)
            objects.hpBg.Visible = true
            objects.hpBar.Position = Vector2.new(barX, headPos.Y + height * (1 - hpFrac))
            objects.hpBar.Size = Vector2.new(1, height * hpFrac)
            objects.hpBar.Color = Color3.fromRGB(255 * (1 - hpFrac), 255 * hpFrac, 0)
            objects.hpBar.Visible = true
        else
            objects.hpBg.Visible = false
            objects.hpBar.Visible = false
        end
    end
end)

---------------------------------------------------------------
-- VISUALS - LIGHTING
---------------------------------------------------------------

RunService.Heartbeat:Connect(function()
    local flags = getFlags()
    local lighting = game:GetService("Lighting")

    if flags["Fullbright"] then
        lighting.Brightness = 2
        lighting.ClockTime = 14
        lighting.GlobalShadows = false
    end

    if flags["NoFog"] then
        lighting.FogEnd = 9e9
    end

    if flags["NoShadows"] then
        lighting.GlobalShadows = false
    end
end)

---------------------------------------------------------------
-- MISC
---------------------------------------------------------------

-- Anti AFK
pcall(function()
    local vu = game:GetService("VirtualUser")
    LocalPlayer.Idled:Connect(function()
        local flags = getFlags()
        if flags["AntiAFK"] then
            vu:CaptureController()
            vu:ClickButton2(Vector2.new())
        end
    end)
end)

-- Disable Gun Sounds
do
    local vm = Workspace:FindFirstChild("ViewModels") or Workspace:WaitForChild("ViewModels", 10)
    if vm then
        vm.DescendantAdded:Connect(function(d)
            if d:IsA("Sound") then
                local flags = getFlags()
                if flags["DisableGunSounds"] then
                    d.Volume = 0
                end
            end
        end)
    end
end

print("[$$ banknote $$] Rivals logic loaded successfully")
