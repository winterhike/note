--======================================================================
-- $$ banknote $$  -  Phantom Forces (main PlaceId 292439477)
--
-- The classic Phantom Forces place (292439477 / universe 113491250) shares
-- the exact same helper integration as the Console place (254965063). Rather
-- than duplicate the whole integration, this file redirects to the canonical
-- logic file.
--
-- NOTE: the string "BanknoteLibrary" below is what the loader scans for to
-- classify this as a full-logic game (builds its own UI). Keep it present.
--======================================================================
local BASE_URL = "https://raw.githubusercontent.com/winterhike/banknote-hub/refs/heads/master/"

assert(getgenv().BanknoteLibrary, "[banknote] BanknoteLibrary not set by loader")

local ok, err = pcall(function()
    local src = game:HttpGet(BASE_URL .. "games/logic/254965063.lua?_=" .. tostring(tick()) .. tostring(math.random(1, 1e6)))
    local fn = loadstring(src)
    assert(fn, "failed to compile shared PF logic")
    fn()
end)

if not ok then
    warn("[$$ banknote $$] PF logic redirect failed: " .. tostring(err))
end
