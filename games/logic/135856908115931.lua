--[[
    $$ banknote $$ - MVSD Logic (PlaceId: 12355337193)
    Silent Aim with FOV circle, hit chance, hit part selection.
    Reads from getgenv().BanknoteFlags (set by the UI config callbacks).
]]

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local function flags()
    if not getgenv().BanknoteFlags then
        getgenv().BanknoteFlags = {}
    end
    return getgenv().BanknoteFlags
end

local function getMouse()
    return UserInputService:GetMouseLocation()
end

------------------------------------------------------------------
-- FOV CIRCLE (set up first so it always works, even if the
-- aim hook fails on a given executor)
------------------------------------------------------------------
local Circle
local circleOk = pcall(function()
    Circle = Drawing.new("Circle")
    Circle.Color = Color3.new(1, 1, 1)
    Circle.NumSides = 360
    Circle.Thickness = 1.5
    Circle.Filled = false
    Circle.Transparency = 1
    Circle.Radius = 200
    Circle.Visible = false
end)

if circleOk and Circle then
    local renderSignal = RunService.PreRender or RunService.RenderStepped
    renderSignal:Connect(function()
        local f = flags()
        if f["ShowFOVCircle"] == true then
            Circle.Visible = true
            Circle.Radius = f["SilentFOV"] or 200
            Circle.Color = f["FOVCircleColor"] or Color3.new(1, 1, 1)
            local mp = getMouse()
            Circle.Position = Vector2.new(mp.X, mp.Y)
        else
            Circle.Visible = false
        end
    end)
    print("[$$ banknote $$] MVSD FOV circle ready")
else
    warn("[$$ banknote $$] Drawing.new('Circle') failed on this executor")
end

------------------------------------------------------------------
-- SILENT AIM (redirects GetMouseLocation to closest target in FOV)
------------------------------------------------------------------
local function TargetPoint()
    local f = flags()
    local fov = f["SilentFOV"] or 200
    local hitPart = f["SilentHitPart"] or "Head"
    local mouse = getMouse()

    local ClosestDistance = fov
    local Closest

    for _, Player in ipairs(Players:GetPlayers()) do
        if Player == LocalPlayer then continue end
        local Character = Player.Character
        if not Character then continue end

        local TargetPart = Character:FindFirstChild(hitPart)
        local RootPart = Character:FindFirstChild("HumanoidRootPart")
        local Humanoid = Character:FindFirstChildOfClass("Humanoid")
        if not TargetPart or not RootPart or not Humanoid or Humanoid.Health <= 0 then
            continue
        end

        local ScreenPosition, OnScreen = Camera:WorldToViewportPoint(TargetPart.Position)
        if not OnScreen then continue end

        local SP = Vector2.new(ScreenPosition.X, ScreenPosition.Y)
        local Distance = (SP - mouse).Magnitude
        if Distance < ClosestDistance then
            ClosestDistance = Distance
            Closest = SP
        end
    end

    return Closest
end

local hookOk, hookErr = pcall(function()
    local OldNamecall
    OldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        local Method = getnamecallmethod()
        local f = flags()

        if self == UserInputService and Method == "GetMouseLocation" and f["SilentAim"] then
            local hitChance = f["SilentHitChance"] or 100
            if (not checkcaller()) and math.random(0, 100) <= hitChance then
                local target = TargetPoint()
                if target then
                    return target
                end
            end
        end

        return OldNamecall(self, ...)
    end))
end)

if hookOk then
    print("[$$ banknote $$] MVSD silent aim hook ready")
else
    warn("[$$ banknote $$] MVSD silent aim hook failed: " .. tostring(hookErr))
end
