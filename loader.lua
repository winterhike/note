--[[
    Loader - $$ banknote $$
    Automatically detects the current PlaceId and loads the matching game config.
    Caches files locally in the workspace folder "banknote" to avoid re-downloading.
]]

local VERSION = "1.1.1"
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

-- Check whether this game ships a full logic script (builds its own UI)
local PlaceId = tostring(game.PlaceId)
local hasLogic = false
do
    local probe = game:HttpGet(BASE_URL .. "games/logic/" .. PlaceId .. ".lua")
    if probe and #probe > 0 and not probe:find("404: Not Found") then
        hasLogic = true
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

-- If the game has a full logic script, let it build the whole UI itself.
-- Otherwise build the generic config-driven UI.
if hasLogic then
    print("[$$ banknote $$] Running full logic for PlaceId: " .. PlaceId)
    local logicSuccess, logicErr = pcall(function()
        local logicSource = game:HttpGet(BASE_URL .. "games/logic/" .. PlaceId .. ".lua")
        loadstring(logicSource)()
    end)
    if not logicSuccess then
        -- The logic builds its own UI; do NOT fall back to the generic UI
        -- (that would create a second window). Just report the error.
        warn("[$$ banknote $$] Logic error: " .. tostring(logicErr))
    end
elseif GameConfig then
    UI:Build(GameConfig, Library, placeName)
else
    warn("[$$ banknote $$] Failed to load any game config.")
end
