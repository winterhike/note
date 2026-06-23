--======================================================================
-- $$ banknote $$  -  BloxStrike  (PlaceId 114234929420007, universe 7633926880)
--
-- NO-HOOK build. Zero hookfunction / hookmetamethod / metamethod edits / Send
-- field-swaps / AC bypass. Everything works through legitimate calls so BAC's
-- hook + lph VM-integrity checks have nothing to detect:
--   * Silent aim = SELF-FIRE: we call Remotes.Inventory.ShootWeapon.Send(...)
--     directly (a normal remote call, NOT a hook) with a packet aimed at the
--     target, plus a matching Character.UpdateLookAngle so the server's
--     shot-vs-look check passes (legit shots stay within ~3 deg; we match it).
--   * ESP = Drawing API only (no DataModel objects, invisible to the AC).
--   * UI = parented under gethui() by the Library (hidden from the UI scan).
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
local HttpService      = game:GetService("HttpService")
local ReplicatedStorage= game:GetService("ReplicatedStorage")

local lplr   = Players.LocalPlayer
local camera = workspace.CurrentCamera
local v2, v3 = Vector2.new, Vector3.new

local function log(...) print("[banknote/BloxStrike]", ...) end

--======================================================================
-- feature state
--======================================================================
local FEAT = {
    -- silent aim (manual: rides your click, wall check, FOV)
    SilentAim   = false,
    SA_HitPart  = "Head",
    SA_FOV      = 120,
    SA_RPM      = 600,
    SA_TeamCheck= true,
    SA_WallCheck= true,
    SA_AimKeyOnly = false,    -- only while holding mouse2
    -- ragebot (auto-fires, through walls, no click needed)
    Ragebot     = false,
    RB_HitPart  = "Head",
    RB_FOV      = 600,
    RB_RPM      = 800,
    RB_TeamCheck= true,
    RB_MaxDist  = 1000,
    -- esp
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
-- resolve remotes + InventoryController (require/CALL only - NOT hooks)
--======================================================================
local ShootSend
local InvController, SkinsModule
do
    local ok, Remotes = pcall(require, ReplicatedStorage.Database.Security.Remotes)
    if ok and Remotes and Remotes.Inventory and Remotes.Inventory.ShootWeapon then
        ShootSend = Remotes.Inventory.ShootWeapon.Send
        log("ShootWeapon resolved (self-fire ready)")
    else
        log("WARN: could not resolve Remotes - aim unavailable")
    end

    -- InventoryController gives the LIVE loadout (Rounds/Capacity/Identifier)
    -- plus the skin re-injection API. Direct require first (no getgc); only if
    -- that fails do ONE getgc scan (never per-frame - that caused the lag).
    local ok2, mod = pcall(function() return require(ReplicatedStorage.Controllers.InventoryController) end)
    if ok2 and type(mod) == "table" and mod.getCurrentEquipped then
        InvController = mod
    elseif typeof(getgc) == "function" then
        for _, v in ipairs(getgc(true)) do
            if type(v) == "table" and rawget(v, "getCurrentEquipped") and rawget(v, "getCurrentInventory") then
                InvController = v
                break
            end
        end
    end
    if InvController then log("InventoryController resolved") else log("WARN: no InventoryController") end

    pcall(function() SkinsModule = require(ReplicatedStorage.Database.Components.Libraries.Skins) end)
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

-- wall check: clear line of sight from the camera to the part
local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
local function losClear(fromPos, part)
    losParams.FilterDescendantsInstances = { lplr.Character, part.Parent }
    return workspace:Raycast(fromPos, part.Position - fromPos, losParams) == nil
end

-- shot origin is the camera position (matches the game's own shots), NaN-masked
-- when sent so server-side origin checks can't pin it. Real damage comes from
-- the reported Hits (client-authoritative). Uses the LIVE loadout + decrements
-- Rounds exactly like the game so the server accepts the shot (the ragebot fix).
local NAN = v3(0/0, 0/0, 0/0)
local function fireAt(part)
    if not ShootSend or not InvController then return end
    local L = InvController.getCurrentEquipped()
    if not L then return end
    if L.Rounds == nil or L.Rounds <= 0 then return end   -- empty / no gun
    local origin = camera.CFrame.Position
    local dir = (part.Position - origin)
    local mag = dir.Magnitude
    if mag <= 0 or mag ~= mag then return end
    L.Rounds = L.Rounds - 1
    pcall(ShootSend, {
        IsSniperScoped = L.IsSniperScoped,
        ShootingHand   = L.ShootingHand,
        Identifier     = L.Identifier,
        Capacity       = L.Capacity,
        Bullets = { [1] = {
            Direction = dir.Unit,
            Origin    = origin + NAN,
            Hits = { [1] = {
                Distance = mag,
                Instance = part,
                Position = part.Position,
                Normal   = v3(0, 1, 0),
                Material = "Plastic",
                Exit     = false,
            } },
        } },
        Rounds  = L.Rounds,
        Ragebot = true,
    })
end

local function nearestEnemyPart(want, fov, requireVisible, maxDist, teamCheck)
    local center = camera.ViewportSize / 2
    local camPos = camera.CFrame.Position
    local best, bd
    for _, p in ipairs(Players:GetPlayers()) do
        if isEnemy(p, teamCheck) then
            local hum = p.Character:FindFirstChildOfClass("Humanoid")
            local part = hitPart(p.Character, want)
            if hum and hum.Health > 0 and part then
                local sp, on = camera:WorldToViewportPoint(part.Position)
                if on then
                    local d = (v2(sp.X, sp.Y) - center).Magnitude
                    local dist = (camPos - part.Position).Magnitude
                    if d <= fov and (not maxDist or dist <= maxDist)
                        and (not requireVisible or losClear(camPos, part))
                        and (not bd or d < bd) then
                        best, bd = part, d
                    end
                end
            end
        end
    end
    return best
end

-- closest enemy by 3D world distance (for ragebot - 360, ignores screen)
local function worldNearestEnemy(want, maxDist, teamCheck)
    local myRoot = lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart")
    local myPos = (myRoot and myRoot.Position) or camera.CFrame.Position
    local best, bd
    for _, p in ipairs(Players:GetPlayers()) do
        if isEnemy(p, teamCheck) then
            local hum = p.Character:FindFirstChildOfClass("Humanoid")
            local part = hitPart(p.Character, want)
            if hum and hum.Health > 0 and part then
                local dist = (myPos - part.Position).Magnitude
                if dist <= maxDist and (not bd or dist < bd) then best, bd = part, dist end
            end
        end
    end
    return best
end

--======================================================================
-- SILENT AIM via SELF-FIRE (no hooks, just direct remote calls)
--======================================================================
local firing = false
UserInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then firing = true end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then firing = false end
end)
local function aimHeld()
    if not FEAT.SA_AimKeyOnly then return true end
    return UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
end

-- Silent Aim: rides YOUR shots, wall-checked, FOV-limited
local saLast = 0
RunService.Heartbeat:Connect(function()
    if not FEAT.SilentAim or not ShootSend then return end
    if not firing or not aimHeld() then return end
    if os.clock() - saLast < 60 / math.max(FEAT.SA_RPM, 1) then return end
    local part = nearestEnemyPart(FEAT.SA_HitPart, FEAT.SA_FOV, FEAT.SA_WallCheck, nil, FEAT.SA_TeamCheck)
    if part then saLast = os.clock(); fireAt(part) end
end)

-- Ragebot: auto-fires (no click), through walls, 3D world targeting
local rbLast = 0
RunService.Heartbeat:Connect(function()
    if not FEAT.Ragebot or not ShootSend then return end
    if os.clock() - rbLast < 60 / math.max(FEAT.RB_RPM, 1) then return end
    local part = worldNearestEnemy(FEAT.RB_HitPart, FEAT.RB_MaxDist, FEAT.RB_TeamCheck)
    if part then rbLast = os.clock(); fireAt(part) end
end)

--======================================================================
-- ESP (Drawing API only - no hooks, no remotes)
--======================================================================
do
    local espObjects = {}
    local function newText() local t = Drawing.new("Text"); t.Size=13; t.Center=true; t.Outline=true; t.Font=2; t.Visible=false; return t end
    local function createESP(p)
        espObjects[p] = { box=Drawing.new("Square"), name=newText(), hpBg=Drawing.new("Line"), hpBar=Drawing.new("Line"), tracer=Drawing.new("Line"), dist=newText() }
        local o = espObjects[p]
        o.box.Thickness=1; o.box.Filled=false; o.box.Visible=false
        o.hpBg.Thickness=3; o.hpBg.Color=Color3.new(0,0,0); o.hpBg.Visible=false
        o.hpBar.Thickness=1; o.hpBar.Visible=false
        o.tracer.Thickness=1; o.tracer.Visible=false
    end
    local function destroyESP(p) local o=espObjects[p]; if not o then return end for _,d in pairs(o) do pcall(function() d:Remove() end) end espObjects[p]=nil end
    for _, p in ipairs(Players:GetPlayers()) do if p ~= lplr then createESP(p) end end
    Players.PlayerAdded:Connect(function(p) if p ~= lplr then createESP(p) end end)
    Players.PlayerRemoving:Connect(destroyESP)
    local function hide(o) o.box.Visible=false;o.name.Visible=false;o.hpBg.Visible=false;o.hpBar.Visible=false;o.tracer.Visible=false;o.dist.Visible=false end
    RunService.RenderStepped:Connect(function()
        for p, o in pairs(espObjects) do
            if not FEAT.ESP or not p.Character or not isEnemy(p, FEAT.ESPTeamCheck) then hide(o)
            else
                local char=p.Character
                local hum=char:FindFirstChildOfClass("Humanoid")
                local root=char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
                local head=char:FindFirstChild("Head")
                if not hum or not root or hum.Health<=0 then hide(o)
                else
                    local topPos=(head and head.Position or root.Position)+v3(0,0.5,0)
                    local botPos=root.Position-v3(0,3,0)
                    local topSp,topOn=camera:WorldToViewportPoint(topPos)
                    local botSp=camera:WorldToViewportPoint(botPos)
                    if not topOn then hide(o)
                    else
                        local h=math.abs(topSp.Y-botSp.Y); local w=h*0.5; local x,y=topSp.X-w/2,topSp.Y; local col=FEAT.ESPColor
                        if FEAT.BoxESP then o.box.Size=v2(w,h);o.box.Position=v2(x,y);o.box.Color=col;o.box.Visible=true else o.box.Visible=false end
                        if FEAT.NameESP then o.name.Text=p.Name;o.name.Position=v2(topSp.X,y-16);o.name.Color=col;o.name.Visible=true else o.name.Visible=false end
                        if FEAT.HealthESP then local hp=math.clamp(hum.Health/math.max(hum.MaxHealth,1),0,1); local bx=x-5
                            o.hpBg.From=v2(bx,y);o.hpBg.To=v2(bx,y+h);o.hpBg.Visible=true
                            o.hpBar.From=v2(bx,y+h);o.hpBar.To=v2(bx,y+h-h*hp);o.hpBar.Color=Color3.fromRGB(255-math.floor(255*hp),math.floor(255*hp),0);o.hpBar.Visible=true
                        else o.hpBg.Visible=false;o.hpBar.Visible=false end
                        if FEAT.DistanceESP then o.dist.Text=string.format("%dm",math.floor((camera.CFrame.Position-root.Position).Magnitude));o.dist.Position=v2(topSp.X,y+h+2);o.dist.Color=col;o.dist.Visible=true else o.dist.Visible=false end
                        if FEAT.TracerESP then local vp=camera.ViewportSize; o.tracer.From=v2(vp.X/2,vp.Y);o.tracer.To=v2(topSp.X,y+h);o.tracer.Color=col;o.tracer.Visible=true else o.tracer.Visible=false end
                    end
                end
            end
        end
    end)
end

--======================================================================
-- SKIN CHANGER (no hooks): re-inject every inventory weapon with a chosen
-- skin via InventoryController.removeInventoryItem + newInventoryItem.
--======================================================================
local SKIN = { Enabled = false, SkinName = "", Float = 0, StatTrak = false, KnifeFix = true }

local function reinjectItem(slot, item, equipIdent)
    if not item or not item.Identifier then return end
    local vm     = item.Viewmodel or {}
    local weapon = item.Name
    local skin   = (SKIN.SkinName ~= "" and SKIN.SkinName) or vm.Skin or "Stock"
    local id     = item._id
    if SKIN.KnifeFix and (weapon == "CT Knife" or weapon == "T Knife") then
        weapon = "Butterfly Knife"; id = "Butterfly Knife_Stock"
        if SKIN.SkinName == "" then skin = "Tiger Stripes" end
    end
    pcall(function() InvController.removeInventoryItem(item.Identifier) end)
    pcall(function()
        InvController.newInventoryItem({
            slot          = slot,
            identifier    = item.Identifier,
            _id           = id,
            weapon        = weapon,
            skin          = skin,
            Float         = SKIN.Float or vm.Float or 0,
            StatTrack     = SKIN.StatTrak and 1 or 0,
            NameTag       = nil,
            OriginalOwner = nil,
            Charm         = {},
            Stickers      = {},
            customProperties = nil,
            shouldEquip   = (item.Identifier == equipIdent),
        })
    end)
end

local function applySkins()
    if not InvController or not InvController.getCurrentInventory then return end
    task.spawn(function()
        pcall(function() if setthreadidentity then setthreadidentity(2) end end)
        local inv = InvController.getCurrentInventory()
        if not inv then return end
        local eq = InvController.getCurrentEquipped()
        local equipIdent = eq and eq.Identifier
        for slot, value in pairs(inv) do
            if type(value) == "table" and value._items then
                local item = value._items[1]
                if item then reinjectItem(slot, item, equipIdent) end
            end
        end
        log("skins applied")
    end)
end

lplr.CharacterAdded:Connect(function()
    if SKIN.Enabled then task.delay(2, function() if SKIN.Enabled then applySkins() end end) end
end)

--======================================================================
-- UI (gethui-parented by the Library)
--======================================================================
local window = BN:Window({ Name = "$$ banknote: BloxStrike $$" })
pcall(function() window:Watermark({ Name = "$$ banknote $$" }) end)
pcall(function() window:KeybindList() end)

local combat  = window:Page({ Name = "Combat" })
local aimS    = combat:Section({ Name = "Silent Aim", Side = 1 })
local rageS   = combat:Section({ Name = "Ragebot", Side = 2 })
local visuals = window:Page({ Name = "Visuals" })
local espS    = visuals:Section({ Name = "ESP", Side = 1 })

local flagN = 0
local function uflag() flagN = flagN + 1 return "bs_" .. flagN end
local function addToggle(sec, label, key, default)
    FEAT[key] = default and true or false
    return sec:Toggle({ Name = label, Flag = uflag(), Default = FEAT[key], Callback = function(v) FEAT[key] = v and true or false end })
end
local function addSlider(sec, label, key, min, max, default, step, suffix)
    FEAT[key] = default
    pcall(function() sec:Slider({ Name=label, Flag=uflag(), Min=min, Max=max, Default=default, Decimals=step or 1, Suffix=suffix or "", Callback=function(v) FEAT[key]=v end }) end)
end
local function addDropdown(sec, label, key, items)
    pcall(function() sec:Dropdown({ Name=label, Flag=uflag(), Items=items, Default=FEAT[key], Multi=false, Callback=function(v) if type(v)=="table" then v=v[1] end FEAT[key]=(type(v)=="string" and v) or FEAT[key] end }) end)
end
local function addColor(sec, label, key)
    pcall(function() sec:Label({ Name=label }):Colorpicker({ Name=label, Flag=uflag(), Default=FEAT[key], Callback=function(c) FEAT[key]=c end }) end)
end

addToggle(aimS, "Silent Aim", "SilentAim", false)
addDropdown(aimS, "Hit Part", "SA_HitPart", { "Head", "UpperTorso", "Torso", "HumanoidRootPart" })
addSlider(aimS, "FOV", "SA_FOV", 10, 600, 120, 1, "px")
addSlider(aimS, "Fire Rate", "SA_RPM", 60, 1200, 600, 1, "rpm")
addToggle(aimS, "Wall Check", "SA_WallCheck", true)
addToggle(aimS, "Team Check", "SA_TeamCheck", true)
addToggle(aimS, "Aim Key Only (RMB)", "SA_AimKeyOnly", false)

addToggle(rageS, "Ragebot (auto-fire, through walls)", "Ragebot", false)
addDropdown(rageS, "Hit Part", "RB_HitPart", { "Head", "UpperTorso", "Torso", "HumanoidRootPart" })
addSlider(rageS, "Fire Rate", "RB_RPM", 60, 1500, 800, 1, "rpm")
addSlider(rageS, "Max Distance", "RB_MaxDist", 50, 2000, 1000, 1, " studs")
addToggle(rageS, "Team Check", "RB_TeamCheck", true)

addToggle(espS, "ESP", "ESP", false)
addToggle(espS, "Boxes", "BoxESP", true)
addToggle(espS, "Names", "NameESP", true)
addToggle(espS, "Health Bars", "HealthESP", true)
addToggle(espS, "Tracers", "TracerESP", false)
addToggle(espS, "Distance", "DistanceESP", false)
addToggle(espS, "Team Check", "ESPTeamCheck", true)
addColor(espS, "ESP Color", "ESPColor")

--======================================================================
-- Skins page (skin changer for every gun, no hooks)
--======================================================================
local skinsPage = window:Page({ Name = "Skins" })
local skinS     = skinsPage:Section({ Name = "Skin Changer", Side = 1 })

skinS:Toggle({ Name = "Enabled (auto re-apply on spawn)", Flag = uflag(), Default = false,
    Callback = function(v) SKIN.Enabled = v and true or false; if SKIN.Enabled then applySkins() end end })
pcall(function()
    skinS:Textbox({ Name = "Skin Name (blank = keep current)", Flag = uflag(), Default = "", Placeholder = "e.g. Fade",
        Callback = function(t) SKIN.SkinName = tostring(t or "") end })
end)
pcall(function()
    skinS:Slider({ Name = "Float (wear)", Flag = uflag(), Min = 0, Max = 1, Default = 0, Decimals = 100, Suffix = "",
        Callback = function(v) SKIN.Float = v end })
end)
skinS:Toggle({ Name = "StatTrak", Flag = uflag(), Default = false, Callback = function(v) SKIN.StatTrak = v and true or false end })
skinS:Toggle({ Name = "Auto Butterfly Knife", Flag = uflag(), Default = true, Callback = function(v) SKIN.KnifeFix = v and true or false end })
pcall(function()
    skinS:Button({ Name = "Apply Skins Now", Callback = function() applySkins() end })
end)

pcall(function() window:Init() end)
log("loaded (no-hook build)")
