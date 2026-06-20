--[[
    Loader - $$ banknote $$
    Automatically detects the current PlaceId and loads the matching game config.
    Caches files locally in the workspace folder "banknote" to avoid re-downloading.
]]

local VERSION = "1.1.4"
local BASE_URL = "https://raw.githubusercontent.com/endmylifehahahahahahahahaha/banknote-hub/refs/heads/master/"
local CACHE_FOLDER = "banknote"

-- Utility: ensure cache folder exists
if not isfolder(CACHE_FOLDER) then
    makefolder(CACHE_FOLDER)
end
if not isfolder(CACHE_FOLDER .. "/games") then
    makefolder(CACHE_FOLDER .. "/games")
end

-- Version check: clear cache if version changed
local versionFile = CACHE_FOLDER .. "/version.txt"
if isfile(versionFile) then
    if readfile(versionFile) ~= VERSION then
        -- Clear cache on version change
        for _, file in pairs(listfiles(CACHE_FOLDER)) do
            if isfile(file) then
                delfile(file)
            end
        end
        if isfolder(CACHE_FOLDER .. "/games") then
            for _, file in pairs(listfiles(CACHE_FOLDER .. "/games")) do
                if isfile(file) then
                    delfile(file)
                end
            end
        end
    end
else
    -- First run or missing version file
end
writefile(versionFile, VERSION)

-- Utility: fetch a file with local caching
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

-- Load the UI library (cached)
local librarySource = cachedGet(BASE_URL .. "library/Library.lua", "Library.lua")
local Library = loadstring(librarySource)()

-- Expose the banknote library globally so game-logic shims can build their own UI
getgenv().BanknoteLibrary = Library

-- Load the UI builder (cached)
local uiSource = cachedGet(BASE_URL .. "UI.lua", "UI.lua")
local UI = loadstring(uiSource)()

-- Check whether this game ships a FULL logic script (builds its own UI via shim)
local PlaceId = tostring(game.PlaceId)
local hasFullLogic = false -- only Rivals-style scripts that build their own window
local hasAddonLogic = false -- lightweight logic scripts that just hook game mechanics

do
    local probe = game:HttpGet(BASE_URL .. "games/logic/" .. PlaceId .. ".lua")
    if probe and #probe > 0 and not probe:find("404: Not Found") then
        -- If the logic file loads the shim (builds its own UI), it's full logic
        if probe:find("shim.lua", 1, true) or probe:find("BanknoteLibrary", 1, true) then
            hasFullLogic = true
        else
            hasAddonLogic = true
        end
    end
end

-- Try to load the game-specific config based on PlaceId
local GameConfig = nil
local isUniversal = false

local success, result = pcall(function()
    local source = cachedGet(BASE_URL .. "games/" .. PlaceId .. ".lua", "games/" .. PlaceId .. ".lua")
    return loadstring(source)()
end)

if success and result then
    GameConfig = result
    print("[$$ banknote $$] Loaded config for PlaceId: " .. PlaceId)
else
    print("[$$ banknote $$] No config found for PlaceId: " .. PlaceId .. " - loading universal features only")
    isUniversal = true
    local fallbackSuccess, fallbackResult = pcall(function()
        local source = cachedGet(BASE_URL .. "games/universal.lua", "games/universal.lua")
        return loadstring(source)()
    end)
    if fallbackSuccess and fallbackResult then
        GameConfig = fallbackResult
        print("[$$ banknote $$] Loaded universal config")
    end
end

-- Get the place name
local placeName = "Universal"
if not isUniversal then
    local mps = game:GetService("MarketplaceService")
    local nameSuccess, nameResult = pcall(function()
        return mps:GetProductInfo(game.PlaceId).Name
    end)
    if nameSuccess and nameResult then
        placeName = nameResult
    end
end

-- Cache-buster so GitHub's raw CDN always serves the freshest logic
local function bust()
    return "?_=" .. tostring(tick()) .. tostring(math.random(1, 1e6))
end

-- If the game has a full logic script, let it build the whole UI itself.
-- Otherwise build the generic config-driven UI, then load addon logic if available.
if hasFullLogic then
    print("[$$ banknote $$] Running full logic for PlaceId: " .. PlaceId)
    local logicSuccess, logicErr = pcall(function()
        local logicSource = game:HttpGet(BASE_URL .. "games/logic/" .. PlaceId .. ".lua" .. bust())
        loadstring(logicSource)()
    end)
    if not logicSuccess then
        warn("[$$ banknote $$] Logic error: " .. tostring(logicErr))
    end
elseif GameConfig then
    UI:Build(GameConfig, Library, placeName)
    if hasAddonLogic then
        local logicSuccess, logicErr = pcall(function()
            local logicSource = game:HttpGet(BASE_URL .. "games/logic/" .. PlaceId .. ".lua" .. bust())
            loadstring(logicSource)()
        end)
        if logicSuccess then
            print("[$$ banknote $$] Loaded addon logic for PlaceId: " .. PlaceId)
        else
            warn("[$$ banknote $$] Addon logic error: " .. tostring(logicErr))
        end
    end
else
    warn("[$$ banknote $$] Failed to load any game config.")
end
