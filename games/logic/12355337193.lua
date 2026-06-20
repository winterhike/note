--[[
    $$ banknote $$ - MVSD Logic (PlaceId: 12355337193)
    Silent Aim with FOV circle, keybind, hit chance, hit part selection.
    Reads from getgenv().BanknoteFlags (set by the UI config callbacks).
]]

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local GetMouse = UserInputService.GetMouseLocation
local LocalPlayer = Players.LocalPlayer
local Camera = workspace.CurrentCamera

local flags = function()
    if not getgenv().BanknoteFlags then
        getgenv().BanknoteFlags = {}
    end
    return getgenv().BanknoteFlags
end

-- FOV Circle (Drawing API)
local Circle = Drawing.new("Circle")
Circle.Color = Color3.new(1, 1, 1)
Circle.NumSides = 360
Circle.Thickness = 1.5
Circle.Filled = false
Circle.Visible = false

local function UpdateCircle()
    local f = flags()
    local visible = f["ShowFOVCircle"] == true
    Circle.Visible = visible

    if visible then
        Circle.Radius = f["SilentFOV"] or 200
        Circle.Position = GetMouse(UserInputService)
        Circle.Color = f["FOVCircleColor"] or Color3.new(1, 1, 1)
    end
end

local function TargetPoint()
    local f = flags()
    local fov = f["SilentFOV"] or 200
    local hitPart = f["SilentHitPart"] or "Head"

    local ClosestDistance = fov
    local Closest

    for _, Player in Players:GetPlayers() do
        if Player == LocalPlayer then continue end

        local Character = Player.Character
        if not Character then continue end

        local TargetPart = Character:FindFirstChild(hitPart)
        local RootPart = Character:FindFirstChild("HumanoidRootPart")
        local Humanoid = Character:FindFirstChild("Humanoid")
        if not TargetPart or not RootPart or not Humanoid or Humanoid.Health <= 0 then
            continue
        end

        local ScreenPosition, OnScreen = Camera:WorldToViewportPoint(TargetPart.Position)
        if not OnScreen then continue end

        local SP = Vector2.new(ScreenPosition.X, ScreenPosition.Y)
        local Distance = (SP - GetMouse(UserInputService)).Magnitude
        if Distance < ClosestDistance then
            ClosestDistance = Distance
            Closest = SP
        end
    end

    return Closest
end

-- Hook GetMouseLocation to redirect aim
local OldNamecall
OldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    local Method = getnamecallmethod()
    local f = flags()

    if self == UserInputService and Method == "GetMouseLocation" and f["SilentAim"] then
        local hitChance = f["SilentHitChance"] or 100
        if math.random(0, 100) <= hitChance then
            if checkcaller() then
                return OldNamecall(self, ...)
            end
            local target = TargetPoint()
            if target then
                return target
            end
        end
    end

    return OldNamecall(self, ...)
end))

-- Update circle every frame
RunService.PreRender:Connect(UpdateCircle)

print("[$$ banknote $$] MVSD silent aim loaded")
