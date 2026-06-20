--[[
    Loader - $$ banknote $$
    Detects the current game (by PlaceId, falling back to UniverseId for games
    with per-match sub-places like Rivals) and loads the matching config/logic.
    Caches files locally in the workspace folder "banknote".
]]

local VERSION = "1.2.0"
local BASE_URL = "https://raw.githubusercontent.com/endmylifehahahahahahahahaha/banknote-hub/refs/heads/master/"
local CACHE_FOLDER = "banknote"

-- Universe (GameId) -> canonical config/logic id, for games whose matches run
-- on different PlaceIds within the same universe.
local UNIVERSE_MAP = {
    ["6035872082"] = "17625359962", -- Rivals (all match sub-places)
}

-- Cache-buster so GitHub's raw CDN always serves the freshest files
local function bust()
    return "?_=" .. tostring(tick()) .. tostring(math.random(1, 1e6))
end

-- Ensure cache folders exist
if not isfolder(CACHE_FOLDER) then makefolder(CACHE_FOLDER) end
if not isfolder(CACHE_FOLDER .. "/games") then makefolder(CACHE_FOLDER .. "/games") end

-- Version check: clear cache if version changed
local versionFile = CACHE_FOLDER .. "/version.txt"
if isfile(versionFile) and readfile(versionFile) ~= VERSION then
    for _, file in pairs(listfiles(CACHE_FOLDER)) do
        if isfile(file) then delfile(file) end
    end
    if isfolder(CACHE_FOLDER .. "/games") then
        for _, file in pairs(listfiles(CACHE_FOLDER .. "/games")) do
            if isfile(file) then delfile(file) end
        end
    end
end
writefile(versionFile, VERSION)

-- Fetch with local caching (version-keyed)
local function cachedGet(url, localPath)
    local fullPath = CACHE_FOLDER .. "/" .. localPath
    if isfile(fullPath) then
        return readfile(fullPath)
    end
    local content = game:HttpGet(url)
    if content and #content > 0 and not content:find("404: Not Found") then
        writefile(fullPath, content)
    end
    return content
end

-- Fresh fetch (no cache); returns ok, content
local function freshGet(url)
    local content = game:HttpGet(url .. bust())
    local ok = content and #content > 0 and not content:find("404: Not Found")
    return ok, content
end

-- Load the UI library + builder (cached)
local Library = loadstring(cachedGet(BASE_URL .. "library/Library.lua", "Library.lua"))()
getgenv().BanknoteLibrary = Library
local UI = loadstring(cachedGet(BASE_URL .. "UI.lua", "UI.lua"))()

-- Resolve which id to use: prefer an exact PlaceId config, else the universe map
local PlaceId = tostring(game.PlaceId)
local GameId = tostring(game.GameId)
local effectiveId = PlaceId

local placeConfigOk = freshGet(BASE_URL .. "games/" .. PlaceId .. ".lua")
if not placeConfigOk and UNIVERSE_MAP[GameId] then
    effectiveId = UNIVERSE_MAP[GameId]
    print("[$$ banknote $$] Matched by universe " .. GameId .. " -> " .. effectiveId)
end

-- Detect whether this game ships a logic script and what kind
local hasFullLogic = false   -- builds its own UI via the shim (Rivals-style)
local hasAddonLogic = false  -- just hooks mechanics (MVSD-style)
do
    local ok, probe = freshGet(BASE_URL .. "games/logic/" .. effectiveId .. ".lua")
    if ok then
        if probe:find("shim.lua", 1, true) or probe:find("BanknoteLibrary", 1, true) then
            hasFullLogic = true
        else
            hasAddonLogic = true
        end
    end
end

-- Load the game-specific config (or universal fallback)
local GameConfig = nil
local isUniversal = false
local success, result = pcall(function()
    return loadstring(cachedGet(BASE_URL .. "games/" .. effectiveId .. ".lua", "games/" .. effectiveId .. ".lua"))()
end)

if success and result then
    GameConfig = result
    print("[$$ banknote $$] Loaded config for id: " .. effectiveId)
else
    isUniversal = true
    print("[$$ banknote $$] No config for " .. effectiveId .. " - loading universal")
    local fbOk, fbResult = pcall(function()
        return loadstring(cachedGet(BASE_URL .. "games/universal.lua", "games/universal.lua"))()
    end)
    if fbOk and fbResult then GameConfig = fbResult end
end

-- Resolve the place name for the window title
local placeName = "Universal"
if not isUniversal then
    local mps = game:GetService("MarketplaceService")
    local nameOk, nameResult = pcall(function()
        return mps:GetProductInfo(game.PlaceId).Name
    end)
    if nameOk and nameResult then placeName = nameResult end
end

-- Full logic builds its own UI; addon logic loads after the config-driven UI
if hasFullLogic then
    print("[$$ banknote $$] Running full logic for id: " .. effectiveId)
    local logicSuccess, logicErr = pcall(function()
        local _, src = freshGet(BASE_URL .. "games/logic/" .. effectiveId .. ".lua")
        loadstring(src)()
    end)
    if not logicSuccess then
        warn("[$$ banknote $$] Logic error: " .. tostring(logicErr))
    end
elseif GameConfig then
    UI:Build(GameConfig, Library, placeName)
    if hasAddonLogic then
        local logicSuccess, logicErr = pcall(function()
            local _, src = freshGet(BASE_URL .. "games/logic/" .. effectiveId .. ".lua")
            loadstring(src)()
        end)
        if logicSuccess then
            print("[$$ banknote $$] Loaded addon logic for id: " .. effectiveId)
        else
            warn("[$$ banknote $$] Addon logic error: " .. tostring(logicErr))
        end
    end
else
    warn("[$$ banknote $$] Failed to load any game config.")
end
