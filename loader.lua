--[[
    Loader - $$ banknote $$
    Automatically detects the current PlaceId and loads the matching game config.
    Caches files locally in the workspace folder "banknote" to avoid re-downloading.
]]

local VERSION = "1.0.1"
local BASE_URL = "https://raw.githubusercontent.com/endmylifehahahahahahahahaha/banknote-hub/refs/heads/master/"
local LIBRARY_URL = "https://raw.githubusercontent.com/sametexe001/juanitahaxx/refs/heads/main/Library.lua"
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
local librarySource = cachedGet(LIBRARY_URL, "Library.lua")
local Library = loadstring(librarySource)()

-- Load the UI builder (cached)
local uiSource = cachedGet(BASE_URL .. "UI.lua", "UI.lua")
local UI = loadstring(uiSource)()

-- Try to load the game-specific config based on PlaceId
local PlaceId = tostring(game.PlaceId)
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

-- Build the UI with the loaded config
if GameConfig then
    UI:Build(GameConfig, Library, placeName)
else
    warn("[$$ banknote $$] Failed to load any game config.")
end
