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
    RB_AutoPen  = true,       -- auto penetration: true = shoot through walls
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
local ShootSend, LookSend
local InvController, SkinsModule
do
    local ok, Remotes = pcall(require, ReplicatedStorage.Database.Security.Remotes)
    if ok and Remotes and Remotes.Inventory and Remotes.Inventory.ShootWeapon then
        ShootSend = Remotes.Inventory.ShootWeapon.Send
        if Remotes.Character and Remotes.Character.UpdateLookAngle then
            LookSend = Remotes.Character.UpdateLookAngle.Send
        end
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

-- live equipped weapon state (read-only attribute, no hook, NO getgc - fast)
local function getEquipped()
    local j = lplr:GetAttribute("CurrentEquipped")
    if not j then return nil end
    local ok, eq = pcall(function() return HttpService:JSONDecode(j) end)
    return ok and eq or nil
end

-- shot origin = current weapon muzzle, else head height
local function getMuzzle()
    local char = lplr.Character
    if not char then return nil end
    local wm = char:FindFirstChild("WeaponModel")
    if wm then
        local mp = wm:FindFirstChild("MuzzlePart", true)
            or wm:FindFirstChild("MuzzlePartR", true)
            or wm:FindFirstChild("MuzzlePartL", true)
        if mp and mp:IsA("BasePart") then return mp.Position end
    end
    local head = char:FindFirstChild("Head")
    if head then return head.Position end
    local hrp = char:FindFirstChild("HumanoidRootPart")
    return hrp and (hrp.Position + v3(0, 1.5, 0))
end

-- self-fire one shot at a part (no hooks, no getgc - direct remote calls)
-- THIS IS THE PROVEN WORKING PACKET (commit 900b6e3). Do not change it.
local function fireAt(part)
    if not ShootSend then return end
    local eq = getEquipped()
    if not eq or not eq.Identifier then return end   -- need a gun equipped
    local origin = getMuzzle()
    if not origin then return end
    local dir = (part.Position - origin)
    if LookSend then
        local ld = (part.Position - camera.CFrame.Position).Unit
        pcall(LookSend, { HorizontalAngle = math.atan2(-ld.X, -ld.Z), VerticalLook = ld.Y })
    end
    pcall(ShootSend, {
        IsSniperScoped = false,
        ShootingHand   = "Right",
        Identifier     = eq.Identifier,
        Capacity       = eq.Capacity or 30,
        Rounds         = eq.Rounds or 1,
        Bullets        = { {
            Direction = dir.Unit,
            Origin    = origin,
            Hits      = { {
                Instance = part, Position = part.Position,
                Normal = v3(0, 0, 1), Material = "Plastic",
                Distance = dir.Magnitude, Exit = false,
            } },
        } },
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

-- closest enemy by 3D world distance (for ragebot - 360, ignores screen).
-- requireVisible=true (auto-pen OFF) only returns targets with clear LOS.
local function worldNearestEnemy(want, maxDist, teamCheck, requireVisible)
    local myRoot = lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart")
    local myPos = (myRoot and myRoot.Position) or camera.CFrame.Position
    local camPos = camera.CFrame.Position
    local best, bd
    for _, p in ipairs(Players:GetPlayers()) do
        if isEnemy(p, teamCheck) then
            local hum = p.Character:FindFirstChildOfClass("Humanoid")
            local part = hitPart(p.Character, want)
            if hum and hum.Health > 0 and part then
                local dist = (myPos - part.Position).Magnitude
                if dist <= maxDist and (not requireVisible or losClear(camPos, part))
                    and (not bd or dist < bd) then best, bd = part, dist end
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

-- Ragebot: auto-fires (no click). Auto-pen ON = through walls; OFF = only
-- fires at targets with clear line of sight (still the same remote/packet).
local rbLast = 0
RunService.Heartbeat:Connect(function()
    if not FEAT.Ragebot or not ShootSend then return end
    if os.clock() - rbLast < 60 / math.max(FEAT.RB_RPM, 1) then return end
    local part = worldNearestEnemy(FEAT.RB_HitPart, FEAT.RB_MaxDist, FEAT.RB_TeamCheck, not FEAT.RB_AutoPen)
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
-- SKIN CHANGER (no hooks): pick a skin per weapon from the game's real skin
-- list, then re-inject each inventory item via removeInventoryItem +
-- newInventoryItem (the same API the game uses).
--======================================================================
local SKIN = { Map = {}, Float = 0, StatTrak = false }  -- Map[weaponName] = skinName

local KNIFE_SET = {
    ["Butterfly Knife"]=true, ["Flip Knife"]=true, ["Gut Knife"]=true, ["Karambit"]=true,
    ["M9 Bayonet"]=true, ["Stiletto Knife"]=true, ["Skeleton Knife"]=true,
    ["CT Knife"]=true, ["T Knife"]=true,
}
local GLOVE_SET = {
    ["Sports Gloves"]=true, ["Operator Gloves"]=true, ["Hand Wraps"]=true,
    ["Driver Gloves"]=true, ["CT Glove"]=true, ["T Glove"]=true,
}

-- list every weapon name (from the game's weapon DB, with a fallback)
local function getWeaponList()
    local list = {}
    pcall(function()
        local f = ReplicatedStorage:FindFirstChild("Database")
        f = f and f:FindFirstChild("Custom")
        f = f and f:FindFirstChild("Weapons")
        if f then for _, c in ipairs(f:GetChildren()) do list[#list+1] = c.Name end end
    end)
    if #list == 0 then
        list = { "AK-47","AUG","AWP","Butterfly Knife","CT Glove","CT Knife","Desert Eagle",
            "Dual Berettas","FAMAS","Five-SeveN","Flip Knife","Galil AR","Glock-18","Gut Knife",
            "Karambit","M4A1-S","M4A4","M9 Bayonet","MAC-10","MP9","Negev","Nova","P250","P90",
            "Tec-9","SG 553","SSG 08","XM1014","USP-S","T Glove","T Knife","MAG-7","R8 Revolver",
            "Stiletto Knife","Sawed-Off","Skeleton Knife","Sports Gloves","Operator Gloves",
            "Hand Wraps","Driver Gloves" }
    end
    table.sort(list)
    return list
end

-- skin names available for a given weapon (always includes "Stock")
local function skinsForWeapon(weapon)
    local names, seen = {}, {}
    if SkinsModule and SkinsModule.GetAllSkinsForWeapon then
        local ok, res = pcall(SkinsModule.GetAllSkinsForWeapon, weapon)
        if ok and type(res) == "table" then
            for _, v in pairs(res) do
                local sn = type(v) == "table" and v.skin
                if sn and not seen[sn] then seen[sn] = true; names[#names+1] = sn end
            end
        end
    end
    if not seen["Stock"] then table.insert(names, 1, "Stock") end
    return names
end

-- choose target weapon+skin for an inventory item (handles knife/glove swaps)
local function resolveTarget(itemName)
    if SKIN.Map[itemName] then return itemName, SKIN.Map[itemName] end
    if KNIFE_SET[itemName] then
        for w, s in pairs(SKIN.Map) do if KNIFE_SET[w] then return w, s end end
    elseif GLOVE_SET[itemName] then
        for w, s in pairs(SKIN.Map) do if GLOVE_SET[w] then return w, s end end
    end
    return nil
end

local function reinjectItem(slot, item, equipIdent)
    if not item or not item.Identifier then return end
    local weapon, skin = resolveTarget(item.Name)
    if not weapon or not skin then return end          -- nothing mapped for this item
    local vm = item.Viewmodel or {}
    local id = item._id
    if weapon ~= item.Name then id = weapon .. "_Stock" end   -- weapon swap (knife/glove)
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
addToggle(aimS, "Wall Check", "SA_WallCheck", true)
addToggle(aimS, "Team Check", "SA_TeamCheck", true)
addToggle(aimS, "Aim Key Only (RMB)", "SA_AimKeyOnly", false)

addToggle(rageS, "Ragebot (auto-fire)", "Ragebot", false)
addToggle(rageS, "Auto Penetration (through walls)", "RB_AutoPen", true)
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
-- Skins page (pick a skin per weapon from the game's real list, no hooks)
--======================================================================
local skinsPage = window:Page({ Name = "Skins" })
local skinS     = skinsPage:Section({ Name = "Skin Changer", Side = 1 })

local weaponList = getWeaponList()
local curWeapon  = weaponList[1]
local skinDD                       -- forward ref so the weapon dropdown can refresh it

pcall(function()
    skinS:Dropdown({ Name = "Weapon", Flag = uflag(), Items = weaponList, Default = curWeapon, Multi = false,
        Callback = function(v)
            if type(v) == "table" then v = v[1] end
            if type(v) == "string" then
                curWeapon = v
                if skinDD then
                    local list = skinsForWeapon(curWeapon)
                    pcall(function() skinDD:Refresh(list) end)
                    pcall(function() skinDD:Set(SKIN.Map[curWeapon] or list[1]) end)
                end
            end
        end })
end)
pcall(function()
    skinDD = skinS:Dropdown({ Name = "Skin", Flag = uflag(), Items = skinsForWeapon(curWeapon), Default = (skinsForWeapon(curWeapon))[1], Multi = false,
        Callback = function(v)
            if type(v) == "table" then v = v[1] end
            if type(v) == "string" then SKIN.Map[curWeapon] = v end
        end })
end)
pcall(function()
    skinS:Slider({ Name = "Float (wear)", Flag = uflag(), Min = 0, Max = 1, Default = 0, Decimals = 0.01, Suffix = "",
        Callback = function(v) SKIN.Float = v end })
end)
skinS:Toggle({ Name = "StatTrak", Flag = uflag(), Default = false, Callback = function(v) SKIN.StatTrak = v and true or false end })
pcall(function()
    skinS:Button({ Name = "Apply Skins", Callback = function() applySkins() end })
end)
pcall(function()
    skinS:Button({ Name = "Clear Selections", Callback = function() SKIN.Map = {} end })
end)

pcall(function() window:Init() end)
log("loaded (no-hook build)")
