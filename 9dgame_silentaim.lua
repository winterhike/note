--[[
    Silent Aim for 9D GAME CLUB FPS (PlaceId family: 119259569670784 / arcade subplaces)

    TRUE shot-data silent aim. No camera hooking.

    Verified live via the game's own modules:
      * Every shot funnels through CombatService.InvokeAction(weapon, "Shoot", params).
      * The Shoot serializer sends these exact fields from `params`:
            Start (Vector3), Direction (Vector3), Spread (uint),
            Target (entity instance), TargetHeadshot (bool)
      * We wrap CombatService.InvokeAction and, on the "Shoot" action, rewrite
        params.Direction to point from params.Start straight at the target, and
        set params.Target / TargetHeadshot so the server's hit-resolution agrees.

    Targeting uses the game's EntityService (Entity.GetAll + IsFriendly + GetHeadPart),
    so it locks onto BOTH players and bots, with team + wall + FOV checks.

    Standalone, client-side, live-config via getgenv().SilentAimConfig.
]]

-- ─────────────────────────────────────────────────────────────
-- CONFIG
-- ─────────────────────────────────────────────────────────────
local DEFAULTS = {
    Enabled    = true,
    HitPart    = "Head",   -- Head, Torso, Root  (Head uses entity:GetHeadPart)
    FOV        = 250,      -- pixels; set very high (e.g. 5000) for full-screen lock
    HitChance  = 100,      -- % of shots redirected
    WallCheck  = false,    -- raycast LoS check (off by default; many maps occlude)
    TeamCheck  = true,     -- skip friendly entities (uses game IsFriendly)
    NoSpread   = true,     -- zero spread for pinpoint accuracy
    ShowFOV    = true,
    FOVColor   = Color3.fromRGB(255, 255, 255),
    FOVThickness = 2,
}

getgenv().SilentAimConfig = getgenv().SilentAimConfig or {}
local cfg = getgenv().SilentAimConfig
for k, v in pairs(DEFAULTS) do if cfg[k] == nil then cfg[k] = v end end

local Players          = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService       = game:GetService("RunService")
local Workspace        = game:GetService("Workspace")
local RS               = game:GetService("ReplicatedStorage")
local LocalPlayer      = Players.LocalPlayer
local Camera           = Workspace.CurrentCamera

-- ─────────────────────────────────────────────────────────────
-- GAME MODULES (resolved safely)
-- ─────────────────────────────────────────────────────────────
local CombatService, EntityService, EntityClass
do
    local ok = pcall(function()
        CombatService = require(RS.Remote.CombatService)
        EntityService = require(RS.Remote.EntityService)
        EntityClass   = require(RS.Remote.EntityService.Entity)
    end)
    if not ok or not CombatService then
        warn("[SilentAim] could not require combat/entity modules - aborting")
        return
    end
end

-- ─────────────────────────────────────────────────────────────
-- FOV CIRCLE (GUI based)
-- ─────────────────────────────────────────────────────────────
local fovCircle, fovStroke
do
    local parent = (gethui and gethui()) or LocalPlayer:WaitForChild("PlayerGui")
    local existing = parent:FindFirstChild("BN_SilentAimFOV")
    if existing then existing:Destroy() end
    local gui = Instance.new("ScreenGui")
    gui.Name = "BN_SilentAimFOV"; gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true; gui.DisplayOrder = 1000000; gui.Parent = parent
    fovCircle = Instance.new("Frame")
    fovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
    fovCircle.BackgroundTransparency = 1
    fovCircle.BorderSizePixel = 0; fovCircle.Visible = false; fovCircle.Parent = gui
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(1, 0); c.Parent = fovCircle
    fovStroke = Instance.new("UIStroke"); fovStroke.Thickness = 2
    fovStroke.Color = Color3.fromRGB(255,255,255); fovStroke.Parent = fovCircle
end

-- ─────────────────────────────────────────────────────────────
-- TARGET SELECTION (once per frame, cached)  -- uses the entity system
-- ─────────────────────────────────────────────────────────────
local cachedTargetPos  = nil  -- Vector3 to aim at
local cachedTargetInst = nil  -- entity workspace instance (for Target field)
local cachedIsHead     = false

local function getEntities()
    local ok, all = pcall(function() return EntityClass.GetAll() end)
    if ok and type(all) == "table" then return all end
    return {}
end

local function entAimPart(ent)
    -- returns a Vector3 aim position and the workspace instance
    local root
    pcall(function() root = ent:GetWorkspaceRoot() end)
    if cfg.HitPart == "Head" then
        local headPos
        local ok = pcall(function() headPos = ent:GetHeadAt() end)
        if ok and typeof(headPos) == "Vector3" then
            return headPos, root, true
        end
        local hp
        pcall(function() hp = ent:GetHeadPart() end)
        if typeof(hp) == "Instance" then return hp.Position, root, true end
    end
    -- torso/root fallback
    local pivot
    pcall(function() pivot = ent:GetPivot() end)
    if typeof(pivot) == "CFrame" then return pivot.Position, root, false end
    if root and root.Position then return root.Position, root, false end
    return nil
end

local function visibleTo(originPos, aimPos, ignoreInst)
    if not cfg.WallCheck then return true end
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    local ignore = {}
    if LocalPlayer.Character then table.insert(ignore, LocalPlayer.Character) end
    if ignoreInst then table.insert(ignore, ignoreInst) end
    params.FilterDescendantsInstances = ignore
    params.IgnoreWater = true
    pcall(function() params.RespectCanCollide = true end)
    local hit = Workspace:Raycast(originPos, aimPos - originPos, params)
    if not hit then return true end
    if ignoreInst and hit.Instance:IsDescendantOf(ignoreInst) then return true end
    return false
end

local function updateTarget()
    Camera = Workspace.CurrentCamera
    cachedTargetPos, cachedTargetInst, cachedIsHead = nil, nil, false
    if not cfg.Enabled or not Camera then return end

    local localEnt = EntityService.GetLocalEntity()
    local mouse = UserInputService:GetMouseLocation()
    local camPos = Camera.CFrame.Position
    local bestDist = cfg.FOV
    local bestPos, bestInst, bestHead

    for _, ent in pairs(getEntities()) do
        if type(ent) == "table" and ent ~= localEnt then
            local alive = false
            pcall(function() alive = ent:IsAlive() end)
            local friendly = false
            if cfg.TeamCheck then
                pcall(function() friendly = localEnt and localEnt:IsFriendly(ent) end)
            end
            if alive and not friendly then
                local aimPos, inst, isHead = entAimPart(ent)
                if aimPos then
                    local sp, onScreen = Camera:WorldToViewportPoint(aimPos)
                    if onScreen then
                        local d = (Vector2.new(sp.X, sp.Y) - mouse).Magnitude
                        if d < bestDist and visibleTo(camPos, aimPos, inst) then
                            bestDist, bestPos, bestInst, bestHead = d, aimPos, inst, isHead
                        end
                    end
                end
            end
        end
    end

    if bestPos then
        cachedTargetPos, cachedTargetInst, cachedIsHead = bestPos, bestInst, bestHead
    end
end

-- ─────────────────────────────────────────────────────────────
-- FOV CIRCLE + TARGET LOOP
-- ─────────────────────────────────────────────────────────────
if getgenv()._9DSilentAimLoop then
    pcall(function() getgenv()._9DSilentAimLoop:Disconnect() end)
end
getgenv()._9DSilentAimLoop = RunService.RenderStepped:Connect(function()
    updateTarget()
    if cfg.ShowFOV and cfg.Enabled then
        local m = UserInputService:GetMouseLocation()
        fovCircle.Size = UDim2.fromOffset(cfg.FOV * 2, cfg.FOV * 2)
        fovCircle.Position = UDim2.fromOffset(m.X, m.Y)
        fovStroke.Color = cfg.FOVColor
        fovStroke.Thickness = cfg.FOVThickness or 2
        fovCircle.Visible = true
    else
        fovCircle.Visible = false
    end
end)

-- ─────────────────────────────────────────────────────────────
-- SHOT-DATA HOOK  (CombatService.InvokeAction chokepoint)
-- ─────────────────────────────────────────────────────────────
local function rewriteShot(params)
    if type(params) ~= "table" then return end
    local tgt = cachedTargetPos
    if not tgt then return end
    if cfg.HitChance < 100 and math.random(1, 100) > cfg.HitChance then return end

    local start = params.Start
    if typeof(start) ~= "Vector3" then
        start = Camera and Camera.CFrame.Position or nil
    end
    if typeof(start) ~= "Vector3" then return end
    if (tgt - start).Magnitude < 0.05 then return end

    local dir = (tgt - start).Unit
    params.Direction = dir

    if cfg.NoSpread and params.Spread ~= nil then
        local t = typeof(params.Spread)
        if t == "number" then params.Spread = 0
        elseif t == "Vector2" then params.Spread = Vector2.zero
        elseif t == "Vector3" then params.Spread = Vector3.zero end
    end

    if type(params.Bullets) == "table" then
        for _, b in ipairs(params.Bullets) do
            if type(b) == "table" and b.Direction ~= nil then b.Direction = dir end
        end
    end

    -- target hint the server uses for hit resolution
    if cachedTargetInst ~= nil then
        params.Target = cachedTargetInst
        params.TargetHeadshot = cachedIsHead and true or false
    end
end

if getgenv()._9DCSInvokeOriginal == nil then
    getgenv()._9DCSInvokeOriginal = CombatService.InvokeAction
end
local original = getgenv()._9DCSInvokeOriginal

local replacement = function(weapon, action, params, ...)
    if cfg.Enabled and tostring(action) == "Shoot" then
        pcall(rewriteShot, params)
    end
    return original(weapon, action, params, ...)
end

local assignOk = pcall(function() CombatService.InvokeAction = replacement end)
if not assignOk and setreadonly then
    pcall(function() setreadonly(CombatService, false) end)
    assignOk = pcall(function() CombatService.InvokeAction = replacement end)
end
if not assignOk then
    warn("[SilentAim] failed to install InvokeAction hook")
    return
end

print("[SilentAim] 9D Game Club silent aim loaded (CombatService shot-data hook)")
print(("[SilentAim] FOV=%d HitPart=%s TeamCheck=%s WallCheck=%s NoSpread=%s")
    :format(cfg.FOV, tostring(cfg.HitPart), tostring(cfg.TeamCheck),
            tostring(cfg.WallCheck), tostring(cfg.NoSpread)))
