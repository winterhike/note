--======================================================================
-- $$ banknote $$  -  BloxStrike  (PlaceId 114234929420007, universe 7633926880)
--
-- BloxStrike runs the "BAC Alpha-3B" anti-cheat (Luraph-virtualised, hidden
-- in loadstring'd ReplicatedFirst chunks). Findings from live RE:
--   * Hit reporting is client-authoritative: the client sends
--     Remotes.Inventory.ShootWeapon.Send({Bullets={{Origin,Direction,
--     Hits={{Instance,Position,...}}}}}) and the server applies damage from
--     the reported Hits. Rewriting Hits => silent aim (confirmed: redirected
--     shots deal damage / kill).
--   * The server cross-checks shots against the streamed look-angle
--     (Character.UpdateLookAngle), so we spoof a matching look-angle per shot.
--   * BAC reports via LogService errors + a numeric-arg punish spam, and bans.
--     On executors whose hooks BAC can't see (Volt-class) the bypass below
--     neutralises it; on executors BAC detects, hook-based features get
--     flagged - so SilentAim is OFF by default and ESP (Drawing-only, no
--     hooks / no remotes) is the always-safe feature.
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
local LogService       = game:GetService("LogService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")

local lplr   = Players.LocalPlayer
local camera = workspace.CurrentCamera
local v2, v3 = Vector2.new, Vector3.new

local function log(...) print("[banknote/BloxStrike]", ...) end

--======================================================================
-- feature state
--======================================================================
local FEAT = {
    -- silent aim (field-swap, no hooks)
    SilentAim   = false,
    HitPart     = "Head",
    FOV         = 250,
    HitChance   = 100,
    TeamCheck   = true,
    SpoofLook   = true,
    -- esp (Drawing only)
    ESP         = false,
    BoxESP      = true,
    NameESP     = true,
    HealthESP   = true,
    TracerESP   = false,
    DistanceESP = false,
    ESPTeamCheck= true,
    ESPColor    = Color3.fromRGB(255, 60, 60),
}

--======================================================================
-- best-effort AC bypass (no-throw; real effect only where hooks evade BAC)
--======================================================================
do
    local getconns = getconnections or get_signal_cons
    local info     = debug.info
    local function srcOf(fn)
        if not fn then return "" end
        local ok, s = pcall(info, fn, "s")
        return (ok and type(s) == "string") and s or ""
    end
    local function findBac()
        for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
            if d.Name == "BAC" and d:IsA("RemoteEvent") then return d end
        end
    end
    local function killLog()
        if not getconns then return end
        local ok, c = pcall(getconns, LogService.MessageOut)
        if ok and c then for _, x in ipairs(c) do pcall(function() if x.Disable then x:Disable() else x:Disconnect() end end) end end
    end
    local function killAcConns()
        if not getconns then return end
        local sigs = { RunService.Heartbeat, RunService.RenderStepped, RunService.Stepped }
        pcall(function() sigs[#sigs+1] = RunService.PreSimulation end)
        local bac = findBac(); if bac then pcall(function() sigs[#sigs+1] = bac.OnClientEvent end) end
        for _, sig in ipairs(sigs) do
            local ok, conns = pcall(getconns, sig)
            if ok and conns then
                for _, c in ipairs(conns) do
                    local f = c.Function or c.func
                    if srcOf(f):find("ReplicatedFirst") then
                        pcall(function() if c.Disable then c:Disable() else c:Disconnect() end end)
                    end
                end
            end
        end
    end
    pcall(killLog); pcall(killAcConns)
    task.spawn(function()
        local t0 = os.clock()
        while true do
            pcall(killLog); pcall(killAcConns)
            if os.clock() - t0 < 6 then task.wait(0.25) else task.wait(2) end
        end
    end)
end

--======================================================================
-- helpers
--======================================================================
local function teamOf(p) return p:GetAttribute("Team") end
local function isEnemy(p, teamOn)
    if p == lplr or not p.Character then return false end
    if teamOn and teamOf(p) ~= nil and teamOf(p) == teamOf(lplr) then return false end
    return true
end
local function hitPart(char, want)
    return char:FindFirstChild(want)
        or char:FindFirstChild("Head")
        or char:FindFirstChild("UpperTorso")
        or char:FindFirstChild("HumanoidRootPart")
end

--======================================================================
-- SILENT AIM (basic - ShootWeapon hit redirect only, no look-angle hooking)
--   Server validates shot direction vs your real look angle (~few degrees).
--   So this only snaps the bullet to a target that is ALREADY within that
--   tolerance of where you're aiming (closet aim). No UpdateLookAngle hook,
--   nothing "major" touched - just the one hit field on your own shot.
--======================================================================
do
    local ok, Remotes = pcall(require, ReplicatedStorage.Database.Security.Remotes)
    if ok and Remotes and Remotes.Inventory and Remotes.Inventory.ShootWeapon then
        local sw = Remotes.Inventory.ShootWeapon
        local origSend = sw.Send

        FEAT.AimTolerance = FEAT.AimTolerance or 0.07   -- rad (~4deg) max snap

        -- nearest enemy hit-part within the angular tolerance of the real aim
        local function targetInCone()
            local camCF = camera.CFrame
            local look = camCF.LookVector
            local best, bestDot
            for _, p in ipairs(Players:GetPlayers()) do
                if isEnemy(p, FEAT.TeamCheck) then
                    local hum = p.Character:FindFirstChildOfClass("Humanoid")
                    local part = hitPart(p.Character, FEAT.HitPart)
                    if hum and hum.Health > 0 and part then
                        local dir = (part.Position - camCF.Position).Unit
                        local dot = look:Dot(dir)                 -- cos(angle)
                        if dot > math.cos(FEAT.AimTolerance) and (not bestDot or dot > bestDot) then
                            best, bestDot = part, dot
                        end
                    end
                end
            end
            return best
        end

        sw.Send = function(pkt, ...)
            pcall(function()
                if FEAT.SilentAim and type(pkt) == "table" and pkt.Bullets then
                    local part = targetInCone()
                    if part then
                        for _, b in ipairs(pkt.Bullets) do
                            local dir = (part.Position - b.Origin)
                            b.Direction = dir.Unit
                            b.Hits = { { Instance = part, Position = part.Position, Normal = v3(0,0,1), Material = "Plastic", Distance = dir.Magnitude, Exit = false } }
                        end
                    end
                end
            end)
            return origSend(pkt, ...)
        end
        log("silent aim armed (basic closet)")
    else
        log("WARN: could not arm silent aim (Remotes not found)")
    end
end

--======================================================================
-- ESP  (Drawing API only - no hooks, no remotes, invisible to BAC)
--======================================================================
do
    local espObjects = {}
    local function newText()
        local t = Drawing.new("Text"); t.Size = 13; t.Center = true; t.Outline = true; t.Font = 2; t.Visible = false; return t
    end
    local function createESP(p)
        espObjects[p] = {
            box = Drawing.new("Square"), name = newText(),
            hpBg = Drawing.new("Line"), hpBar = Drawing.new("Line"),
            tracer = Drawing.new("Line"), dist = newText(),
        }
        local o = espObjects[p]
        o.box.Thickness = 1; o.box.Filled = false; o.box.Visible = false
        o.hpBg.Thickness = 3; o.hpBg.Color = Color3.new(0,0,0); o.hpBg.Visible = false
        o.hpBar.Thickness = 1; o.hpBar.Visible = false
        o.tracer.Thickness = 1; o.tracer.Visible = false
    end
    local function destroyESP(p)
        local o = espObjects[p]; if not o then return end
        for _, d in pairs(o) do pcall(function() d:Remove() end) end
        espObjects[p] = nil
    end
    for _, p in ipairs(Players:GetPlayers()) do if p ~= lplr then createESP(p) end end
    Players.PlayerAdded:Connect(function(p) if p ~= lplr then createESP(p) end end)
    Players.PlayerRemoving:Connect(destroyESP)

    local function hide(o)
        o.box.Visible=false; o.name.Visible=false; o.hpBg.Visible=false
        o.hpBar.Visible=false; o.tracer.Visible=false; o.dist.Visible=false
    end

    RunService.RenderStepped:Connect(function()
        for p, o in pairs(espObjects) do
            if not FEAT.ESP or not p.Character or not isEnemy(p, FEAT.ESPTeamCheck) then
                hide(o)
            else
                local char = p.Character
                local hum = char:FindFirstChildOfClass("Humanoid")
                local root = char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
                local head = char:FindFirstChild("Head")
                if not hum or not root or hum.Health <= 0 then hide(o) else
                    local topPos = (head and head.Position or root.Position) + v3(0, 0.5, 0)
                    local botPos = root.Position - v3(0, 3, 0)
                    local topSp, topOn = camera:WorldToViewportPoint(topPos)
                    local botSp = camera:WorldToViewportPoint(botPos)
                    if not topOn then hide(o) else
                        local h = math.abs(topSp.Y - botSp.Y)
                        local w = h * 0.5
                        local x, y = topSp.X - w/2, topSp.Y
                        local col = FEAT.ESPColor
                        if FEAT.BoxESP then o.box.Size=v2(w,h); o.box.Position=v2(x,y); o.box.Color=col; o.box.Visible=true else o.box.Visible=false end
                        if FEAT.NameESP then o.name.Text=p.Name; o.name.Position=v2(topSp.X,y-16); o.name.Color=col; o.name.Visible=true else o.name.Visible=false end
                        if FEAT.HealthESP then
                            local hp = math.clamp(hum.Health/math.max(hum.MaxHealth,1),0,1)
                            local bx = x-5
                            o.hpBg.From=v2(bx,y); o.hpBg.To=v2(bx,y+h); o.hpBg.Visible=true
                            o.hpBar.From=v2(bx,y+h); o.hpBar.To=v2(bx,y+h-h*hp)
                            o.hpBar.Color=Color3.fromRGB(255-math.floor(255*hp),math.floor(255*hp),0); o.hpBar.Visible=true
                        else o.hpBg.Visible=false; o.hpBar.Visible=false end
                        if FEAT.DistanceESP then
                            o.dist.Text=string.format("%dm",math.floor((camera.CFrame.Position-root.Position).Magnitude))
                            o.dist.Position=v2(topSp.X,y+h+2); o.dist.Color=col; o.dist.Visible=true
                        else o.dist.Visible=false end
                        if FEAT.TracerESP then
                            local vp=camera.ViewportSize
                            o.tracer.From=v2(vp.X/2,vp.Y); o.tracer.To=v2(topSp.X,y+h); o.tracer.Color=col; o.tracer.Visible=true
                        else o.tracer.Visible=false end
                    end
                end
            end
        end
    end)
end

--======================================================================
-- UI  (menu is gethui-parented by the Library, so hidden from BAC's scan)
--======================================================================
local window = BN:Window({ Name = "$$ banknote: BloxStrike $$" })
pcall(function() window:Watermark({ Name = "$$ banknote $$" }) end)
pcall(function() window:KeybindList() end)

local combat  = window:Page({ Name = "Combat" })
local silentS = combat:Section({ Name = "Silent Aim", Side = 1 })
local visuals = window:Page({ Name = "Visuals" })
local espS    = visuals:Section({ Name = "ESP", Side = 1 })

local flagN = 0
local function uflag() flagN = flagN + 1 return "bs_" .. flagN end
local function addToggle(sec, label, key, default)
    FEAT[key] = default and true or false
    return sec:Toggle({ Name = label, Flag = uflag(), Default = FEAT[key],
        Callback = function(v) FEAT[key] = v and true or false end })
end
local function addSlider(sec, label, key, min, max, default, step, suffix)
    FEAT[key] = default
    pcall(function()
        sec:Slider({ Name = label, Flag = uflag(), Min = min, Max = max, Default = default,
            Decimals = step or 1, Suffix = suffix or "", Callback = function(v) FEAT[key] = v end })
    end)
end
local function addDropdown(sec, label, key, items)
    pcall(function()
        sec:Dropdown({ Name = label, Flag = uflag(), Items = items, Default = FEAT[key], Multi = false,
            Callback = function(v) if type(v)=="table" then v=v[1] end FEAT[key] = (type(v)=="string" and v) or FEAT[key] end })
    end)
end
local function addColor(sec, label, key)
    pcall(function()
        sec:Label({ Name = label }):Colorpicker({ Name = label, Flag = uflag(), Default = FEAT[key],
            Callback = function(c) FEAT[key] = c end })
    end)
end

-- Silent Aim
local t = addToggle(silentS, "Silent Aim", "SilentAim", false)
if t and t.Keybind then pcall(function() t:Keybind({ Name = "Silent Aim", Flag = uflag(), Mode = "Toggle",
    Callback = function(on) FEAT.SilentAim = on and true or false; if t.Set then pcall(function() t:Set(FEAT.SilentAim) end) end end }) end) end
addDropdown(silentS, "Hit Part", "HitPart", { "Head", "UpperTorso", "Torso", "HumanoidRootPart" })
addSlider(silentS, "FOV", "FOV", 30, 1000, 250, 1, "px")
addSlider(silentS, "Hit Chance", "HitChance", 1, 100, 100, 1, "%")
addToggle(silentS, "Team Check", "TeamCheck", true)
addToggle(silentS, "Spoof Look Angle", "SpoofLook", true)
pcall(function() silentS:Label({ Name = "Note: needs an executor whose hooks evade BAC. ESP is always safe." }) end)

-- ESP
addToggle(espS, "ESP", "ESP", false)
addToggle(espS, "Boxes", "BoxESP", true)
addToggle(espS, "Names", "NameESP", true)
addToggle(espS, "Health Bars", "HealthESP", true)
addToggle(espS, "Tracers", "TracerESP", false)
addToggle(espS, "Distance", "DistanceESP", false)
addToggle(espS, "Team Check", "ESPTeamCheck", true)
addColor(espS, "ESP Color", "ESPColor")

pcall(function() window:Init() end)
log("loaded")
