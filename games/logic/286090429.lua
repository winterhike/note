--[[
    $$ banknote $$ - Arsenal Logic (PlaceId: 286090429)
    Silent Aim (camera CoordinateFrame hook, runs in an actor) with hit-part
    selection, FOV, and a raycast wall check. Config crosses the actor boundary
    via Camera attributes (actors have isolated globals but share instances).
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer

local function flags()
    if not getgenv().BanknoteFlags then getgenv().BanknoteFlags = {} end
    return getgenv().BanknoteFlags
end

------------------------------------------------------------------
-- Mirror UI flags onto Camera attributes so the actor can read them
------------------------------------------------------------------
local function syncAttrs()
    local cam = workspace.CurrentCamera
    if not cam then return end
    local f = flags()
    cam:SetAttribute("BN_SilentAim", f["SilentAim"] == true)
    cam:SetAttribute("BN_HitPart", f["SilentHitPart"] or "Head")
    cam:SetAttribute("BN_FOV", f["SilentFOV"] or 200)
    cam:SetAttribute("BN_WallCheck", f["WallCheck"] == true)
end
RunService.Heartbeat:Connect(syncAttrs)
syncAttrs()

------------------------------------------------------------------
-- FOV circle (GUI, main thread)
------------------------------------------------------------------
do
    local guiParent = (gethui and gethui()) or LocalPlayer:WaitForChild("PlayerGui")
    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "BanknoteFOV"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.DisplayOrder = 999999
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
            local mp = UserInputService:GetMouseLocation()
            circle.Position = UDim2.fromOffset(mp.X, mp.Y)
            circle.Visible = true
        else
            circle.Visible = false
        end
    end)
end

------------------------------------------------------------------
-- Silent aim hook (runs inside an actor)
------------------------------------------------------------------
local actorOk = pcall(function()
    if not (getactors and run_on_actor) then
        error("executor lacks actor support (getactors/run_on_actor)")
    end
    local actors = getactors()
    local actor = actors and actors[1]
    if not actor then
        error("no actors available")
    end

    run_on_actor(actor, [==[
        local players = game:GetService("Players")
        local input_service = game:GetService("UserInputService")
        local local_player = players.LocalPlayer
        local camera = workspace.CurrentCamera

        local function cfg(name, default)
            local v = camera:GetAttribute(name)
            if v == nil then return default end
            return v
        end

        local function get_closest_target()
            if not cfg("BN_SilentAim", false) then return nil end

            local fov = cfg("BN_FOV", 200)
            local hitpart = cfg("BN_HitPart", "Head")
            local wallcheck = cfg("BN_WallCheck", false)

            local closest_part = nil
            local closest_distance = fov
            local local_team = local_player.Team
            local mouse_location = input_service:GetMouseLocation()
            local cam_pos = camera.CFrame.Position

            for _, player in players:GetPlayers() do
                if player == local_player then continue end
                if local_team and player.Team == local_team then continue end

                local character = player.Character
                if not character then continue end

                local part = character:FindFirstChild(hitpart) or character:FindFirstChild("Head")
                if not part then continue end

                local nrpbs = player:FindFirstChild("NRPBS")
                if not nrpbs then continue end
                local health = nrpbs:FindFirstChild("Health")
                if not health or health.Value <= 0 then continue end

                local screen_pos, on_screen = camera:WorldToViewportPoint(part.Position)
                if not on_screen then continue end

                local distance = (Vector2.new(screen_pos.X, screen_pos.Y) - mouse_location).Magnitude
                if distance < closest_distance then
                    if wallcheck then
                        local params = RaycastParams.new()
                        params.FilterType = Enum.RaycastFilterType.Exclude
                        params.FilterDescendantsInstances = { character, local_player.Character }
                        params.IgnoreWater = true
                        pcall(function() params.RespectCanCollide = true end)
                        local dir = part.Position - cam_pos
                        local result = workspace:Raycast(cam_pos, dir, params)
                        if result then
                            -- a solid object sits between the camera and target -> blocked
                            continue
                        end
                    end
                    closest_distance = distance
                    closest_part = part
                end
            end

            return closest_part
        end

        local old_index
        old_index = hookmetamethod(game, "__index", newcclosure(function(self, index)
            if self == camera and index == "CoordinateFrame" then
                local source = debug.info(3, "s")
                local name = debug.info(3, "n")
                if source and string.find(source, "First") and name ~= "RotCamera" then
                    local info = debug.getinfo(3)
                    if info and info.nups == 35 then
                        local hit_part = get_closest_target()
                        if hit_part then
                            return CFrame.new(camera.CFrame.Position, hit_part.Position)
                        end
                    end
                end
            end
            return old_index(self, index)
        end))
    ]==])
end)

if actorOk then
    print("[$$ banknote $$] Arsenal silent aim loaded (actor)")
else
    warn("[$$ banknote $$] Arsenal silent aim needs an executor with actor support")
end
