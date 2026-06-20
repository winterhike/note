--======================================================================
-- $$ banknote $$  -  Phantom Forces (PlaceId 254965063)
-- Full feature integration of the "wapus" Phantom Forces codebase, rendered
-- entirely through the banknote (juanitahaxx) UI library.
--
-- Approach (mirrors the established shim pattern, adapted to wapus' custom
-- Drawing-based UI): run wapus.lua intact, hide its own Drawing menu, then
-- walk its live menu structure (tabs -> sections -> elements) and rebuild
-- every control inside banknote. Each banknote control drives the matching
-- wapus element via element:SetValue(v), which fires wapus' real feature
-- callback. Nothing about wapus' feature logic is reimplemented.
--======================================================================
-- allow re-execution within the same session (re-running the loader): tear
-- down a previous integration's menu guard so we don't stack heartbeats.
if getgenv()._WapusMenuGuard then
    pcall(function() getgenv()._WapusMenuGuard:Disconnect() end)
end
getgenv()._WapusBanknoteLoaded = true

local BASE_URL = "https://raw.githubusercontent.com/endmylifehahahahahahahahaha/banknote-hub/refs/heads/master/"

local BN = getgenv().BanknoteLibrary
assert(BN, "[banknote] BanknoteLibrary not set by loader")

local RunService = game:GetService("RunService")

local function notify(msg)
    pcall(function() BN:Notification(tostring(msg), 4) end)
end

local function log(...) print("[banknote/PF]", ...) end

--======================================================================
-- 0. Ensure PF's parallel-Luau modules are reachable on the MAIN thread.
--
-- Phantom Forces runs its client code in parallel-Luau Actors. On a normal
-- join the cheat engine can't see PF's modules from the main thread (getgc
-- returns nothing useful), which is exactly what we hit. The official wapus
-- loader fixes this by enabling the DebugRunParallelLuaOnMainThread fast flag
-- and rejoining; after that, PF's parallel Lua runs on the main thread and
-- everything (wapus + the banknote UI) lives in one VM.
--======================================================================
do
    local function parallelOnMain()
        if not getfflag then return nil end
        local ok, val = pcall(getfflag, "DebugRunParallelLuaOnMainThread")
        if not ok then return nil end
        return tostring(val):lower() == "true"
    end

    local pom = parallelOnMain()
    if pom ~= true then
        if getgenv()._WapusFflagTried then
            warn("[banknote/PF] parallel-Lua-on-main still off after rejoin; proceeding best-effort")
        elseif setfflag then
            getgenv()._WapusFflagTried = true
            log("enabling DebugRunParallelLuaOnMainThread + rejoining ...")
            notify("Phantom Forces: enabling cheat engine, rejoining...")
            pcall(function() setfflag("DebugRunParallelLuaOnMainThread", "True") end)
            if queue_on_teleport then
                pcall(function()
                    queue_on_teleport('getgenv()._WapusFflagTried=true; loadstring(game:HttpGet("' .. BASE_URL .. 'loader.lua"))()')
                end)
            end
            task.wait(0.5)
            pcall(function()
                game:GetService("TeleportService"):Teleport(game.PlaceId)
            end)
            return
        else
            warn("[banknote/PF] parallel Lua is off-main-thread and setfflag is unavailable on this executor")
            notify("PF: executor can't enable main-thread parallel Lua")
        end
    end
end

-- Resolve an always-fresh URL for wapus.lua. raw.githubusercontent.com caches
-- the master branch for ~5 min and ignores ?_= cache-busters, so we pin to the
-- latest commit SHA (commit-pinned raw URLs are immutable and never stale).
local function wapusURL()
    local okSha, body = pcall(function()
        return game:HttpGet("https://api.github.com/repos/endmylifehahahahahahahahaha/banknote-hub/commits/master")
    end)
    if okSha and type(body) == "string" then
        local sha = body:match('"sha"%s*:%s*"(%x+)"')
        if sha then
            log("pinned to commit", sha:sub(1, 7))
            return "https://raw.githubusercontent.com/endmylifehahahahahahahahaha/banknote-hub/" .. sha .. "/wapus.lua"
        end
    end
    log("commit SHA unavailable, falling back to master (may be cached)")
    return BASE_URL .. "wapus.lua?_=" .. tostring(tick()) .. tostring(math.random(1, 1e6))
end

--======================================================================
-- 1. Run the wapus codebase intact
--======================================================================
do
    log("fetching wapus.lua ...")
    local url = wapusURL()
    local src
    local okFetch, fetchErr = pcall(function()
        src = game:HttpGet(url)
    end)
    if not okFetch or type(src) ~= "string" or #src < 1000 then
        warn("[banknote/PF] wapus.lua fetch failed:", fetchErr, "len:", src and #src)
    else
        log("wapus.lua fetched, bytes:", #src, "- compiling ...")
        local fn, compileErr = loadstring(src)
        if not fn then
            warn("[banknote/PF] wapus.lua COMPILE error:", compileErr)
        else
            log("wapus.lua compiled - executing ...")
            -- wipe wapus' saved preset BEFORE it loads so no preset is applied
            -- (it auto-loads Phantom Forces/cache/lastfile.json on init).
            pcall(function()
                local p = "Phantom Forces/cache/lastfile.json"
                if isfile and isfile(p) then
                    writefile(p, "{}")
                    log("cleared saved preset (lastfile.json)")
                end
            end)
            local okRun, runErr = pcall(fn)
            if not okRun then
                warn("[banknote/PF] wapus.lua RUNTIME error:", runErr)
            else
                log("wapus.lua executed ok")
            end
        end
    end
end

--======================================================================
-- 2. Resolve the wapus object + its built menu
--======================================================================
local wapus
do
    local deadline = tick() + 15
    repeat
        wapus = (getgenv and getgenv().wapus) or (rawget and rawget(getfenv(), "wapus"))
        if wapus and wapus.menus and wapus.menus[1] and wapus.menus[1].tabs and #wapus.menus[1].tabs > 0 then
            break
        end
        task.wait(0.1)
    until tick() > deadline
end

if not wapus then
    warn("[banknote/PF] getgenv().wapus is nil - wapus did not export its object")
    notify("Phantom Forces: failed to hook wapus (no object)")
    return
end
if not (wapus.menus and wapus.menus[1]) then
    warn("[banknote/PF] wapus.menus[1] missing - menu was not created")
    notify("Phantom Forces: failed to hook wapus (no menu)")
    return
end
if not (wapus.menus[1].tabs and #wapus.menus[1].tabs > 0) then
    warn("[banknote/PF] wapus menu has no tabs")
end

local menu = wapus.menus[1]
log("hooked wapus menu, tabs:", #(menu.tabs or {}))

--======================================================================
-- 3. Hide the wapus Drawing menu (keep feature visuals intact)
--======================================================================
do
    -- move the wapus menu toggle off a common key so it can't pop the
    -- Drawing UI back open over the banknote UI.
    pcall(function()
        if Enum.KeyCode.Pause then wapus.toggleKeybind = "Pause" end
    end)

    local function hideMenuChrome()
        for _, m in ipairs(wapus.menus) do
            m.open = false
            if m.drawCache then
                for _, d in ipairs(m.drawCache) do
                    pcall(function() d.Visible = false end)
                end
            end
            if m.keys and m.keys.drawCache then
                for _, d in ipairs(m.keys.drawCache) do
                    pcall(function() d.Visible = false end)
                end
            end
        end
    end

    wapus.open = false
    hideMenuChrome()

    -- guard against the menu being re-shown (toggle key / config load)
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if wapus.open then
            wapus.open = false
            hideMenuChrome()
        end
    end)
    getgenv()._WapusMenuGuard = conn
end

--======================================================================
-- 4. Helpers to walk + drive the wapus menu
--======================================================================
local function elName(el)
    if el.name then return el.name end
    if el.text and el.text.Text then return el.text.Text end
    return "?"
end

-- left/right side of a wapus section, derived from its panel X position
local sbgX = nil
pcall(function() sbgX = menu.sectionbg and menu.sectionbg.Position.X end)
local function sideOf(mainSection)
    if not sbgX then return 1 end
    local ok, x = pcall(function() return mainSection.outline.Position.X end)
    if ok and x and (x - sbgX) > 120 then return 2 end
    return 1
end

local function toKeyCode(v)
    if v == nil then return nil end
    local s = tostring(v):gsub("Enum%.KeyCode%.", ""):gsub("Enum%.UserInputType%.", "")
    if s == "" or s == "None" or s == "none" then return nil end
    if Enum.KeyCode[s] then return Enum.KeyCode[s] end
    if Enum.UserInputType[s] then return Enum.UserInputType[s] end
    return nil
end

--======================================================================
-- 4b. Clean slate: wapus loads a saved PRESET on init (random toggles on,
-- which also caused the chatSpam error). Turn every toggle off and reset
-- sliders to their defaults, then apply a curated banknote default config.
--======================================================================
do
    log("resetting wapus preset to a clean state ...")
    local resetCount = 0
    for _, sec in pairs(wapus.sectionIndexes) do
        if type(sec) == "table" and sec.flags then
            for _, flag in pairs(sec.flags) do
                if type(flag) == "table" then
                    if flag.type == "toggle" and flag.value == true then
                        pcall(function() flag:SetValue(false) end)
                        resetCount = resetCount + 1
                    elseif flag.type == "slider" and flag.default ~= nil and flag.value ~= flag.default then
                        pcall(function() flag:SetValue(flag.default) end)
                    end
                end
            end
        end
    end

    -- curated default config (everything else stays OFF; user opts in)
    local function setF(secName, name, val)
        local sec = wapus.sectionIndexes[secName]
        if sec and sec.flags and sec.flags[name] then
            pcall(function() sec.flags[name]:SetValue(val) end)
        end
    end
    -- clean, low-risk legit baseline: enemy ESP only
    setF("Enemy ESP", "Enabled", true)
    setF("Enemy ESP", "Boxes", true)
    setF("Enemy ESP", "Names", true)
    setF("Enemy ESP", "Health Bar", true)
    setF("Enemy ESP", "Distances", true)

    log("clean config applied (" .. resetCount .. " toggles cleared)")
end

--======================================================================
-- 5. Build the banknote window from the live wapus menu
--======================================================================
local window = BN:Window({ Name = "$$ banknote: Phantom Forces $$" })
log("banknote window created:", window ~= nil)
pcall(function() window:Watermark({ Name = "$$ banknote $$" }) end)
pcall(function() window:KeybindList() end)

-- flags must be globally unique (wapus reuses element names like "Enabled",
-- "Use FOV", "FOV Radius" across many sections); key by section + name.
local function mkFlag(prefix, prefix2, name)
    return (prefix .. "_" .. prefix2 .. "_" .. name):gsub("%s+", "_")
end

local function buildElement(bnSection, el, secName)
    local t = el.type
    if t == "toggle" then
        local bnToggle = bnSection:Toggle({
            Name = elName(el),
            Flag = mkFlag("wp", secName, elName(el)),
            Default = el.value and true or false,
            Callback = function(v) pcall(function() el:SetValue(v and true or false) end) end,
        })
        -- chained colorpickers (live in el.colors)
        if el.colors then
            for _, color in ipairs(el.colors) do
                pcall(function()
                    bnToggle:Colorpicker({
                        Name = color.name or "Color",
                        Flag = mkFlag("wpc", secName, color.name or (elName(el) .. "_color")),
                        Default = (typeof(color.value) == "Color3") and color.value or Color3.fromRGB(255, 255, 255),
                        Callback = function(c) pcall(function() color:SetValue(c) end) end,
                    })
                end)
            end
        end
        -- chained keybind (toggles the feature with a hotkey)
        if el.keybind and bnToggle.Keybind then
            pcall(function()
                local data = {
                    Name = elName(el),
                    Flag = mkFlag("wpk", secName, elName(el)),
                    Mode = "Toggle",
                    Callback = function()
                        local nv = not el.value
                        pcall(function() el:SetValue(nv) end)
                        pcall(function() bnToggle:Set(nv) end)
                    end,
                }
                local def = toKeyCode(el.keybind.value)
                if def then data.Default = def end
                bnToggle:Keybind(data)
            end)
        end
    elseif t == "slider" then
        bnSection:Slider({
            Name = elName(el),
            Flag = mkFlag("wp", secName, elName(el)),
            Min = el.min or 0,
            Max = el.max or 100,
            Default = el.value or el.default or el.min or 0,
            Decimals = el.step or 1,
            Suffix = el.suffix or "",
            Callback = function(v) pcall(function() el:SetValue(v) end) end,
        })
    elseif t == "dropdown" then
        local items = el.options
        if type(items) ~= "table" or #items == 0 then items = { el.value or "None" } end
        bnSection:Dropdown({
            Name = elName(el),
            Flag = mkFlag("wp", secName, elName(el)),
            Items = items,
            Default = el.value,
            Multi = false,
            Callback = function(v) pcall(function() el:SetValue(v) end) end,
        })
    elseif t == "textbox" then
        bnSection:Textbox({
            Name = elName(el),
            Flag = mkFlag("wp", secName, elName(el)),
            Default = tostring(el.value or ""),
            Callback = function(v) pcall(function() el:SetValue(v) end) end,
        })
    elseif t == "button" then
        bnSection:Button({
            Name = elName(el),
            Callback = function() pcall(function() if el.callback then el.callback() end end) end,
        })
    end
end

local function buildSection(page, sec, side)
    if not sec or not sec.elements or #sec.elements == 0 then return end
    local secName = sec.name or "Section"
    local bnSection
    local ok = pcall(function()
        bnSection = page:Section({ Name = secName, Side = side })
    end)
    if not ok or not bnSection then return end
    for _, el in ipairs(sec.elements) do
        pcall(buildElement, bnSection, el, secName)
    end
end

local pageCount, sectionCount = 0, 0
for _, tab in ipairs(menu.tabs) do
    local tabName = "Tab"
    pcall(function() tabName = tab.title and tab.title.Text or tabName end)

    -- banknote provides its own settings page; skip wapus' config/settings tab
    if tostring(tabName):lower() ~= "settings" then
        local page
        local okPage = pcall(function() page = window:Page({ Name = tabName }) end)
        if okPage and page then
            pageCount = pageCount + 1
            if tab.mainSections then
                for _, mainSection in ipairs(tab.mainSections) do
                    if mainSection.type ~= "playerlist" then
                        local side = sideOf(mainSection)
                        -- mainSection.sections = { mainSection, subsection1, ... }
                        local subs = mainSection.sections or { mainSection }
                        for _, sub in ipairs(subs) do
                            buildSection(page, sub, side)
                            sectionCount = sectionCount + 1
                        end
                    end
                end
            end
        else
            warn("[banknote/PF] failed to create page:", tabName)
        end
    end
end
log("built pages:", pageCount, "sections:", sectionCount)

local okInit, initErr = pcall(function() window:Init() end)
if not okInit then warn("[banknote/PF] window:Init() error:", initErr) end
log("window:Init() done:", okInit)

--======================================================================
-- 6. Clean unload: fire wapus' own Unload button when banknote exits
--======================================================================
do
    local function fireWapusUnload()
        -- 1. turn every feature OFF so each feature's own callback reverts its
        -- visuals (ESP drawings, chams, world lighting, crosshair, etc.).
        pcall(function()
            for _, sec in pairs(wapus.sectionIndexes) do
                if type(sec) == "table" and sec.flags then
                    for _, flag in pairs(sec.flags) do
                        if type(flag) == "table" and flag.type == "toggle" and flag.value == true then
                            pcall(function() flag:SetValue(false) end)
                        end
                    end
                end
            end
        end)
        -- 2. fire wapus' own Unload button (unloadMain) for full teardown
        pcall(function()
            local sec = wapus.sectionIndexes and wapus.sectionIndexes["Cheat Settings"]
            if sec and sec.elements then
                for _, el in ipairs(sec.elements) do
                    if el.type == "button" and el.text and el.text.Text == "Unload" and el.callback then
                        el.callback()
                        return
                    end
                end
            end
        end)
        -- 3. nuke any leftover wapus drawings + the menu guard
        pcall(function() if cleardrawcache then cleardrawcache() end end)
        pcall(function()
            if getgenv()._WapusMenuGuard then getgenv()._WapusMenuGuard:Disconnect() end
        end)
        getgenv()._WapusBanknoteLoaded = nil
    end

    local realExit = BN.Exit
    if realExit then
        BN.Exit = function(self, ...)
            fireWapusUnload()
            return realExit(self, ...)
        end
    end
    BN.OnUnload = fireWapusUnload
end

notify("Phantom Forces (wapus) loaded into banknote")
