--[[
    $$ banknote $$ - MVSD Logic (PlaceId: 12355337193)
    Silent Aim with FOV circle (GUI based), hit chance, hit part selection.
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
-- FOV CIRCLE (GUI Frame + UICorner + UIStroke)
------------------------------------------------------------------
local guiParent = (gethui and gethui()) or LocalPlayer:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BanknoteFOV"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 999999
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
screenGui.Parent = guiParent

local circle = Instance.new("Frame")
circle.Size = UDim2.fromOffset(400, 400)
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

local renderSignal = RunService.PreRender or RunService.RenderStepped
renderSignal:Connect(function()
    local f = flags()
    if f["ShowFOVCircle"] == true then
        local radius = f["SilentFOV"] or 200
        circle.Size = UDim2.fromOffset(radius * 2, radius * 2)
        stroke.Color = f["FOVCircleColor"] or Color3.fromRGB(255, 255, 255)
        local mp = getMouse()
        circle.Position = UDim2.fromOffset(mp.X, mp.Y)
        circle.Visible = true
    else
        circle.Visible = false
    end
end)

print("[$$ banknote $$] MVSD FOV circle ready")

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
