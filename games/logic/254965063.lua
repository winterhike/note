--======================================================================
-- $$ banknote $$  -  Phantom Forces (PlaceId 254965063)
-- Full feature integration of the "helper" Phantom Forces codebase, rendered
-- entirely through the banknote (juanitahaxx) UI library.
--
-- Approach (mirrors the established shim pattern, adapted to helper' custom
-- Drawing-based UI): run helper.lua intact, hide its own Drawing menu, then
-- walk its live menu structure (tabs -> sections -> elements) and rebuild
-- every control inside banknote. Each banknote control drives the matching
-- helper element via element:SetValue(v), which fires helper' real feature
-- callback. Nothing about helper' feature logic is reimplemented.
--======================================================================
-- allow re-execution within the same session (re-running the loader): tear
-- down a previous integration's menu guard so we don't stack heartbeats.
if getgenv()._HelperMenuGuard then
    pcall(function() getgenv()._HelperMenuGuard:Disconnect() end)
end
getgenv()._HelperBanknoteLoaded = true

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
-- returns nothing useful), which is exactly what we hit. The official helper
-- loader fixes this by enabling the DebugRunParallelLuaOnMainThread fast flag
-- and rejoining; after that, PF's parallel Lua runs on the main thread and
-- everything (helper + the banknote UI) lives in one VM.
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
        if getgenv()._HelperFflagTried then
            warn("[banknote/PF] parallel-Lua-on-main still off after rejoin; proceeding best-effort")
        elseif setfflag then
            getgenv()._HelperFflagTried = true
            log("enabling DebugRunParallelLuaOnMainThread + rejoining ...")
            notify("Phantom Forces: enabling cheat engine, rejoining...")
            pcall(function() setfflag("DebugRunParallelLuaOnMainThread", "True") end)
            if queue_on_teleport then
                pcall(function()
                    queue_on_teleport('getgenv()._HelperFflagTried=true; loadstring(game:HttpGet("' .. BASE_URL .. 'loader.lua"))()')
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

-- Resolve an always-fresh URL for helper.lua. raw.githubusercontent.com caches
-- the master branch for ~5 min and ignores ?_= cache-busters, so we pin to the
-- latest commit SHA (commit-pinned raw URLs are immutable and never stale).
local function helperURL()
    local okSha, body = pcall(function()
        return game:HttpGet("https://api.github.com/repos/endmylifehahahahahahahahaha/banknote-hub/commits/master")
    end)
    if okSha and type(body) == "string" then
        local sha = body:match('"sha"%s*:%s*"(%x+)"')
        if sha then
            log("pinned to commit", sha:sub(1, 7))
            return "https://raw.githubusercontent.com/endmylifehahahahahahahahaha/banknote-hub/" .. sha .. "/pfH/helper.lua"
        end
    end
    log("commit SHA unavailable, falling back to master (may be cached)")
    return BASE_URL .. "pfH/helper.lua?_=" .. tostring(tick()) .. tostring(math.random(1, 1e6))
end

--======================================================================
-- 1. Run the helper codebase intact
--======================================================================
do
    log("fetching helper.lua ...")
    local url = helperURL()
    local src
    local okFetch, fetchErr = pcall(function()
        src = game:HttpGet(url)
    end)
    if not okFetch or type(src) ~= "string" or #src < 1000 then
        warn("[banknote/PF] helper.lua fetch failed:", fetchErr, "len:", src and #src)
    else
        log("helper.lua fetched, bytes:", #src, "- compiling ...")
        local fn, compileErr = loadstring(src)
        if not fn then
            warn("[banknote/PF] helper.lua COMPILE error:", compileErr)
        else
            log("helper.lua compiled - executing ...")
            -- Contain helper' files inside the banknote folder and start clean:
            -- pre-create its dirs (prevents "directory does not exist") and wipe
            -- any saved preset so helper boots on built-in defaults only.
            pcall(function()
                local root = "banknote/pf"
                local dirs = { "banknote", root, root .. "/cache", root .. "/configs",
                    root .. "/sounds", root .. "/chat spam lists", root .. "/cache/votekick data" }
                for _, d in ipairs(dirs) do
                    if not isfolder(d) then pcall(makefolder, d) end
                end
                writefile(root .. "/cache/lastfile.json", "{}")
                log("prepared clean banknote/pf config")
            end)
            local okRun, runErr = pcall(fn)
            if not okRun then
                warn("[banknote/PF] helper.lua RUNTIME error:", runErr)
            else
                log("helper.lua executed ok")
            end
        end
    end
end

--======================================================================
-- 2. Resolve the helper object + its built menu
--======================================================================
local helper
do
    local deadline = tick() + 15
    repeat
        helper = (getgenv and getgenv().helper) or (rawget and rawget(getfenv(), "helper"))
        if helper and helper.menus and helper.menus[1] and helper.menus[1].tabs and #helper.menus[1].tabs > 0 then
            break
        end
        task.wait(0.1)
    until tick() > deadline
end

if not helper then
    warn("[banknote/PF] getgenv().helper is nil - helper did not export its object")
    notify("Phantom Forces: failed to hook helper (no object)")
    return
end
if not (helper.menus and helper.menus[1]) then
    warn("[banknote/PF] helper.menus[1] missing - menu was not created")
    notify("Phantom Forces: failed to hook helper (no menu)")
    return
end
if not (helper.menus[1].tabs and #helper.menus[1].tabs > 0) then
    warn("[banknote/PF] helper menu has no tabs")
end

local menu = helper.menus[1]
log("hooked helper menu, tabs:", #(menu.tabs or {}))

--======================================================================
-- 3. Hide the helper Drawing menu (keep feature visuals intact)
--======================================================================
do
    -- move the helper menu toggle off a common key so it can't pop the
    -- Drawing UI back open over the banknote UI.
    pcall(function()
        if Enum.KeyCode.Pause then helper.toggleKeybind = "Pause" end
    end)

    local function hideMenuChrome()
        for _, m in ipairs(helper.menus) do
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

    helper.open = false
    hideMenuChrome()

    -- guard against the menu being re-shown (toggle key / config load)
    local conn
    conn = RunService.Heartbeat:Connect(function()
        if helper.open then
            helper.open = false
            hideMenuChrome()
        end
    end)
    getgenv()._HelperMenuGuard = conn
end

--======================================================================
-- 4. Helpers to walk + drive the helper menu
--======================================================================
local function elName(el)
    if el.name then return el.name end
    if el.text and el.text.Text then return el.text.Text end
    return "?"
end

-- left/right side of a helper section, derived from its panel X position
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
-- 4b. Clean slate: helper loads a saved PRESET on init (random toggles on,
-- which also caused the chatSpam error). Turn every toggle off and reset
-- sliders to their defaults, then apply a curated banknote default config.
--======================================================================
do
    log("resetting helper preset to a clean state ...")
    local resetCount = 0
    for _, sec in pairs(helper.sectionIndexes) do
        if type(sec) == "table" and sec.flags then
            for _, flag in pairs(sec.flags) do
                if type(flag) == "table" then
                    if flag.type == "toggle" then
                        -- force every toggle OFF (even already-off ones): some
                        -- visuals like the FOV circles are drawn visible at
                        -- creation and only hide when the toggle callback runs.
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
        local sec = helper.sectionIndexes[secName]
        if sec and sec.flags and sec.flags[name] then
            pcall(function() sec.flags[name]:SetValue(val) end)
        end
    end
    -- start completely empty: nothing enabled by default.

    log("clean config applied (" .. resetCount .. " toggles cleared)")
end

--======================================================================
-- 5. Build the banknote window from the live helper menu
--======================================================================
local window = BN:Window({ Name = "$$ banknote: Phantom Forces $$" })
log("banknote window created:", window ~= nil)
pcall(function() window:Watermark({ Name = "$$ banknote $$" }) end)
pcall(function() window:KeybindList() end)

-- flags must be globally unique (helper reuses element names like "Enabled",
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
        -- NOTE: we deliberately do NOT chain helper' menu-hotkey keybinds here.
        -- banknote fires a keybind's callback at build time, which flipped the
        -- just-reset toggle back ON (re-enabling the whole preset). Features are
        -- controlled via the toggle itself instead.
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

-- sections removed from the banknote UI (user wants knifebot + ESP gone;
-- they'll add their own ESP library later).
local SKIP_SECTIONS = {
    ["Knife Bot"] = true,
    ["Enemy ESP"] = true,
    ["Team ESP"] = true,
}

local function buildSection(page, sec, side)
    if not sec or not sec.elements or #sec.elements == 0 then return end
    local secName = sec.name or "Section"
    if SKIP_SECTIONS[secName] then return end
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

    -- banknote provides its own settings page; skip helper' config/settings tab
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
-- 6. Clean unload: fire helper' own Unload button when banknote exits
--======================================================================
do
    local function fireHelperUnload()
        -- 1. turn every feature OFF so each feature's own callback reverts its
        -- visuals (ESP drawings, chams, world lighting, crosshair, etc.).
        pcall(function()
            for _, sec in pairs(helper.sectionIndexes) do
                if type(sec) == "table" and sec.flags then
                    for _, flag in pairs(sec.flags) do
                        if type(flag) == "table" and flag.type == "toggle" and flag.value == true then
                            pcall(function() flag:SetValue(false) end)
                        end
                    end
                end
            end
        end)
        -- 2. fire helper' own Unload button (unloadMain) for full teardown
        pcall(function()
            local sec = helper.sectionIndexes and helper.sectionIndexes["Cheat Settings"]
            if sec and sec.elements then
                for _, el in ipairs(sec.elements) do
                    if el.type == "button" and el.text and el.text.Text == "Unload" and el.callback then
                        el.callback()
                        return
                    end
                end
            end
        end)
        -- 3. nuke any leftover helper drawings + the menu guard
        pcall(function() if cleardrawcache then cleardrawcache() end end)
        pcall(function()
            if getgenv()._HelperMenuGuard then getgenv()._HelperMenuGuard:Disconnect() end
        end)
        getgenv()._HelperBanknoteLoaded = nil
    end

    local realExit = BN.Exit
    if realExit then
        BN.Exit = function(self, ...)
            fireHelperUnload()
            return realExit(self, ...)
        end
    end
    BN.OnUnload = fireHelperUnload
end

notify("Phantom Forces loaded into banknote")
