--======================================================================
-- $$ banknote $$  -  REDLINER (universe 7265339759)
--
-- Integrates the VapeV4ForRoblox REDLINER feature logic (game-specific
-- combat/movement hooks) through a Vape-compatibility shim that maps Vape's
-- module/category API onto the banknote UI library. Their feature code runs
-- mostly intact; only the UI + module lifecycle is reimplemented. No ESP /
-- chams / drawing visuals are used (visual sub-options are made inert).
--
-- Source (fork-friendly): https://github.com/7GrandDadPGN/VapeV4ForRoblox
-- (contains BanknoteLibrary marker so the loader treats this as full logic)
--======================================================================
if getgenv()._RedlinerLoaded then return end
getgenv()._RedlinerLoaded = true

local BN = getgenv().BanknoteLibrary
assert(BN, "[banknote] BanknoteLibrary not set by loader")

local BASE = "https://raw.githubusercontent.com/endmylifehahahahahahahahaha/banknote-hub/refs/heads/master/"
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local function log(...) print("[banknote/REDLINER]", ...) end
local function notify(msg) pcall(function() BN:Notification(tostring(msg), 4) end) end

-- pin fetches to the latest commit so edits aren't served stale by the CDN
do
    local ok, body = pcall(function()
        return game:HttpGet("https://api.github.com/repos/endmylifehahahahahahahahaha/banknote-hub/commits/master")
    end)
    if ok and type(body) == "string" then
        local sha = body:match('"sha"%s*:%s*"(%x+)"')
        if sha then
            BASE = "https://raw.githubusercontent.com/endmylifehahahahahahahahaha/banknote-hub/" .. sha .. "/"
            log("pinned to commit", sha:sub(1, 7))
        end
    end
end

--======================================================================
-- 1. (no scratch files needed: the feature script's warning prompt and
--    drawing download were removed, so nothing is written outside banknote.)
--======================================================================

--======================================================================
-- 2. banknote window + lazy pages (one page per Vape category)
--======================================================================
local window = BN:Window({ Name = "$$ banknote: REDLINER $$" })
pcall(function() window:Watermark({ Name = "$$ banknote $$" }) end)
pcall(function() window:KeybindList() end)

local pages = {}
local pageSideCounter = {}
local function getPage(name)
    if not pages[name] then
        pages[name] = window:Page({ Name = name })
        pageSideCounter[name] = 0
    end
    return pages[name]
end
local function nextSide(name)
    pageSideCounter[name] = (pageSideCounter[name] or 0) + 1
    return ((pageSideCounter[name] % 2) == 1) and 1 or 2
end

local flagN = 0
local function uflag() flagN = flagN + 1 return "rl_" .. flagN end

--======================================================================
-- 3. Vape-compatibility shim (shared.vape)
--======================================================================
local vape = {}
vape.Loaded = true
vape.Modules = {}
vape.Libraries = {}

-- a real (hidden) ScreenGui for the few non-visual things Vape parents to gui
do
    local sg = Instance.new("ScreenGui")
    sg.Name = "\0rl"
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true
    pcall(function() sg.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
    vape.gui = sg
end

function vape:CreateNotification(title, text, dur, kind)
    pcall(function() BN:Notification(tostring(text or title), tonumber(dur) or 4) end)
end

local globalCleans = {}
function vape:Clean(conn)
    table.insert(globalCleans, conn)
    return conn
end

function vape:Remove(name)
    -- universal modules we don't load simply don't exist; nothing to remove.
    vape.Modules[name] = nil
end

function vape:Uninject() end

-- Vape "list/option" categories the feature file reads from
vape.Categories = {}
local function optionTable()
    return setmetatable({}, { __index = function(self, k) self[k] = { Enabled = false } return self[k] end })
end
vape.Categories.Friends = { Options = optionTable(), ListEnabled = {} }
vape.Categories.Targets = { Options = optionTable(), ListEnabled = {} }
vape.Categories.Main = { Options = optionTable(), ListEnabled = {} }

--======================================================================
-- 3a. Module factory (Vape module -> banknote section)
--======================================================================
local function makeModuleFactory(categoryName)
    return function(_, data)
        data = data or {}
        local module = {
            Name = data.Name or "Module",
            Enabled = data.Default or false,
            Function = data.Function,
            CleanList = {},
        }

        local page = getPage(categoryName)
        local side = nextSide(categoryName)
        local bnSection
        pcall(function() bnSection = page:Section({ Name = module.Name, Side = side }) end)
        module._section = bnSection

        local function disableCleans()
            for _, c in ipairs(module.CleanList) do
                pcall(function() if typeof(c) == "RBXScriptConnection" or (type(c) == "table" and c.Disconnect) then c:Disconnect() end end)
            end
            table.clear(module.CleanList)
        end

        local function setEnabled(v)
            v = v and true or false
            if module.Enabled == v then return end
            module.Enabled = v
            if v then
                if module.Function then task.spawn(function() pcall(module.Function, true) end) end
            else
                disableCleans()
                if module.Function then task.spawn(function() pcall(module.Function, false) end) end
            end
        end
        module.setEnabled = setEnabled

        function module:Clean(conn)
            table.insert(module.CleanList, conn)
            return conn
        end

        -- main on/off toggle
        if bnSection then
            module._bnToggle = bnSection:Toggle({
                Name = "Enabled",
                Flag = uflag(),
                Default = module.Enabled,
                Callback = function(v) setEnabled(v) end,
            })
            -- native banknote keybind (Toggle / Hold / Always selectable in
            -- the keybind UI) that drives the module, restoring Vape's keybinds.
            if module._bnToggle and module._bnToggle.Keybind then
                pcall(function()
                    module._bnToggle:Keybind({
                        Name = module.Name,
                        Flag = uflag(),
                        Mode = "Toggle",
                        Callback = function(active)
                            setEnabled(active and true or false)
                            if module._bnToggle and module._bnToggle.Set then
                                pcall(function() module._bnToggle:Set(module.Enabled) end)
                            end
                        end,
                    })
                end)
            end
        end

        function module:Toggle()
            setEnabled(not module.Enabled)
            if module._bnToggle and module._bnToggle.Set then pcall(function() module._bnToggle:Set(module.Enabled) end) end
        end

        -- ExtraText/Tooltip are cosmetic in Vape; ignore safely.

        ----------------------------------------------------------------
        -- sub-element constructors
        ----------------------------------------------------------------
        local function sliderStep(d)
            if d.Decimal and d.Decimal > 0 then return 1 / d.Decimal end
            return 1
        end

        function module:CreateSlider(d)
            d = d or {}
            local obj = { Value = d.Default or d.Min or 0, Object = { Visible = true } }
            if d.Visible == false or not bnSection then
                -- hidden/visual sub-option: stay inert
                obj.Object.Visible = false
                if d.Function then pcall(d.Function, obj.Value) end
                return obj
            end
            pcall(function()
                bnSection:Slider({
                    Name = d.Name or "Slider",
                    Flag = uflag(),
                    Min = d.Min or 0,
                    Max = d.Max or 100,
                    Default = obj.Value,
                    Decimals = sliderStep(d),
                    Suffix = (type(d.Suffix) == "string" and d.Suffix) or "",
                    Callback = function(val)
                        obj.Value = val
                        if d.Function then pcall(d.Function, val) end
                    end,
                })
            end)
            if d.Function then pcall(d.Function, obj.Value) end
            return obj
        end

        function module:CreateToggle(d)
            d = d or {}
            local obj = { Enabled = d.Default or false, Object = { Visible = true } }
            if d.Visible == false or not bnSection then
                obj.Object.Visible = false
                if d.Function then pcall(d.Function, obj.Enabled) end
                return obj
            end
            pcall(function()
                bnSection:Toggle({
                    Name = d.Name or "Toggle",
                    Flag = uflag(),
                    Default = obj.Enabled,
                    Callback = function(v)
                        obj.Enabled = v
                        if d.Function then pcall(d.Function, v) end
                    end,
                })
            end)
            if d.Function then pcall(d.Function, obj.Enabled) end
            return obj
        end

        function module:CreateDropdown(d)
            d = d or {}
            local obj = { Value = d.Default, Object = { Visible = true } }
            if not bnSection then return obj end
            local items = d.List or {}
            if type(items) ~= "table" then items = {} end
            pcall(function()
                bnSection:Dropdown({
                    Name = d.Name or "Dropdown",
                    Flag = uflag(),
                    Items = items,
                    Default = obj.Value,
                    Multi = false,
                    Callback = function(v)
                        obj.Value = v
                        if d.Function then pcall(d.Function, v) end
                    end,
                })
            end)
            return obj
        end

        -- color sliders are purely visual -> inert
        function module:CreateColorSlider(d)
            d = d or {}
            return {
                Hue = 0, Sat = 0, Value = 1,
                Opacity = d.DefaultOpacity or 1,
                Object = { Visible = false },
            }
        end

        -- text box only used for a particle texture (visual) -> inert
        function module:CreateTextBox(d)
            d = d or {}
            return { Value = d.Default or "", Object = { Visible = false } }
        end

        -- text lists (chat spam / sound ids) -> inert (kept harmless)
        function module:CreateTextList(d)
            d = d or {}
            return { ListEnabled = {}, Object = { Visible = false } }
        end

        function module:CreateTargets(d)
            d = d or {}
            local targets = {
                Players = { Enabled = d.Players and true or false },
                NPCs = { Enabled = false },
                Walls = { Enabled = d.Walls and false or false },
            }
            if bnSection then
                pcall(function()
                    bnSection:Toggle({ Name = "Target Players", Flag = uflag(), Default = targets.Players.Enabled,
                        Callback = function(v) targets.Players.Enabled = v end })
                    bnSection:Toggle({ Name = "Target NPCs", Flag = uflag(), Default = targets.NPCs.Enabled,
                        Callback = function(v) targets.NPCs.Enabled = v end })
                    if d.Walls then
                        bnSection:Toggle({ Name = "Wall Check", Flag = uflag(), Default = targets.Walls.Enabled,
                            Callback = function(v) targets.Walls.Enabled = v end })
                    end
                end)
            end
            return targets
        end

        vape.Modules[module.Name] = module
        return module
    end
end

-- combat / blatant / utility / world / legit categories
for _, catName in ipairs({ "Combat", "Blatant", "Utility", "World", "Legit" }) do
    vape.Categories[catName] = { CreateModule = makeModuleFactory(catName) }
end
-- Vape also exposes vape.Legit (alias for the Legit category)
vape.Legit = vape.Categories.Legit

--======================================================================
-- 3b. Support libraries the feature file reads
--======================================================================
vape.Libraries.targetinfo = { Targets = setmetatable({}, { __mode = "k" }) }
vape.Libraries.sessioninfo = {
    AddItem = function(_, name)
        return { Name = name, Value = 0, Increment = function(self) self.Value = (self.Value or 0) + 1 end }
    end,
}
-- everyone targetable (second return = "passes whitelist")
vape.Libraries.whitelist = { get = function() return nil, true end }

shared.vape = vape

--======================================================================
-- 4. Load Vape's self-contained entity library (reused as-is)
--======================================================================
do
    local ok, lib = pcall(function()
        local src = game:HttpGet(BASE .. "redliner/entity.lua")
        return loadstring(src)()
    end)
    if ok and type(lib) == "table" then
        vape.Libraries.entity = lib
        log("entity library loaded")
    else
        warn("[banknote/REDLINER] failed to load entity library:", lib)
        notify("REDLINER: entity library failed to load")
        return
    end
end

--======================================================================
-- 5. Run the REDLINER feature logic (passing a truthy vararg so it runs
--    on this thread instead of taking Vape's actor-injection path).
--======================================================================
do
    log("fetching REDLINER feature logic ...")
    local ok, err = pcall(function()
        local src = game:HttpGet(BASE .. "redliner/features.lua?_=" .. tostring(tick()))
        local fn = loadstring(src)
        assert(fn, "failed to compile features.lua")
        fn(true)
    end)
    if not ok then
        warn("[banknote/REDLINER] feature logic error:", err)
        notify("REDLINER: feature logic error (see console)")
    else
        log("feature logic loaded")
    end
end

--======================================================================
-- 6. Build the banknote window + clean unload
--======================================================================
pcall(function() window:Init() end)

do
    local function unloadAll()
        -- turn every Vape module off (runs each feature's own teardown)
        for _, m in pairs(vape.Modules) do
            if type(m) == "table" and m.Enabled and m.setEnabled then
                pcall(function() m.setEnabled(false) end)
            end
        end
        -- disconnect global vape:Clean connections
        for _, c in ipairs(globalCleans) do
            pcall(function() if c and c.Disconnect then c:Disconnect() end end)
        end
        vape.Loaded = nil
        pcall(function() if vape.gui then vape.gui:Destroy() end end)
        getgenv()._RedlinerLoaded = nil
    end

    local realExit = BN.Exit
    if realExit then
        BN.Exit = function(self, ...)
            unloadAll()
            return realExit(self, ...)
        end
    end
    BN.OnUnload = unloadAll
end

notify("REDLINER loaded into banknote")
