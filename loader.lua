--[[
    Loader - juanitahaxx
    Automatically detects the current PlaceId and loads the matching game config.
    Then loads the UI which builds itself from that config.
]]

local BASE_URL = "https://raw.githubusercontent.com/endmylifehahahahahahahahaha/banknote-hub/refs/heads/master/"

-- Load the UI builder
local UI = loadstring(game:HttpGet(BASE_URL .. "UI.lua"))()

-- Try to load the game-specific config based on PlaceId
local PlaceId = tostring(game.PlaceId)
local GameConfig = nil

local success, result = pcall(function()
    return loadstring(game:HttpGet(BASE_URL .. "games/" .. PlaceId .. ".lua"))()
end)

if success and result then
    GameConfig = result
    print("[juanitahaxx] Loaded config for PlaceId: " .. PlaceId)
else
    print("[juanitahaxx] No config found for PlaceId: " .. PlaceId .. " - loading universal features only")
    local fallbackSuccess, fallbackResult = pcall(function()
        return loadstring(game:HttpGet(BASE_URL .. "games/universal.lua"))()
    end)
    if fallbackSuccess and fallbackResult then
        GameConfig = fallbackResult
        print("[juanitahaxx] Loaded universal config")
    end
end

-- Build the UI with the loaded config
if GameConfig then
    UI:Build(GameConfig)
else
    warn("[juanitahaxx] Failed to load any game config.")
end
