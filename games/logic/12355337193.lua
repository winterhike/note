--[[
    $$ banknote $$ - MVSD Logic (PlaceId: 12355337193)
    Silent Aim (original logic, unchanged) + GUI FOV circle.
    Reads from getgenv().BanknoteFlags (set by the UI config callbacks).
]]

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local GetMouse = UserInputService.GetMouseLocation
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local OldNamecall

local function flags()
    if not getgenv().BanknoteFlags then
        getgenv().BanknoteFlags = {}
    end
    return getgenv().BanknoteFlags
end

------------------------------------------------------------------
-- FOV CIRCLE (GUI Frame + UICorner + UIStroke) -- visual only
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

RunService.RenderStepped:Connect(function()
    local f = flags()
    if f["ShowFOVCircle"] == true then
        local radius = f["SilentFOV"] or 200
        circle.Size = UDim2.fromOffset(radius * 2, radius * 2)
        stroke.Color = f["FOVCircleColor"] or Color3.fromRGB(255, 255, 255)
        local mp = GetMouse(UserInputService)
        circle.Position = UDim2.fromOffset(mp.X, mp.Y)
        circle.Visible = true
    else
        circle.Visible = false
    end
end)

------------------------------------------------------------------
-- SILENT AIM (your original logic, verbatim)
------------------------------------------------------------------
local function TargetPoint()
    local Enabled = flags()["SilentAim"]
    local HitPart = flags()["SilentHitPart"] or "Head"
    local FOV = flags()["SilentFOV"] or 200

    local ClosestDistance = FOV
    local Closest

    for _, Player in Players:GetPlayers() do
        if Player == LocalPlayer then
            continue
        end

        local Character = Player.Character
        if not Character then
            continue
        end

        local TargetPart = Character:FindFirstChild(HitPart)
        local RootPart = Character:FindFirstChild("HumanoidRootPart")
        local Humanoid = Character:FindFirstChild("Humanoid")
        if not TargetPart or not RootPart or not Humanoid or Humanoid.Health <= 0 then
            continue
        end

        local ScreenPosition, OnScreen = Camera:WorldToViewportPoint(TargetPart.Position)
        if not OnScreen then
            continue
        end

        ScreenPosition = Vector2.new(ScreenPosition.X, ScreenPosition.Y)
        local Distance = (ScreenPosition - GetMouse(UserInputService)).Magnitude
        if Distance < ClosestDistance then
            ClosestDistance = Distance
            Closest = ScreenPosition
        end
    end

    return Closest
end

OldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    local Method = getnamecallmethod()
    local Enabled = flags()["SilentAim"]
    local HitChance = flags()["SilentHitChance"] or 100

    if self == UserInputService and Method == "GetMouseLocation" and Enabled and math.random(0, 100) <= HitChance then
        if checkcaller() then
            return OldNamecall(self, ...)
        end

        local target = TargetPoint()
        if target then
            return target
        end
    end

    return OldNamecall(self, ...)
end))

print("[$$ banknote $$] MVSD loaded")
