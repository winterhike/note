--[[
    Game Config - Phantom Forces (main PlaceId: 292439477)
    The real feature set is provided by the full logic file
    (games/logic/292439477.lua), which renders the wapus codebase through the
    banknote UI. This config exists only so the loader resolves a valid game
    instead of falling back to universal on the cached loader.
]]

return {
    Pages = {
        {
            Name = "combat",
            Sections = {
                {
                    Name = "Info",
                    Side = 1,
                    Elements = {
                        {Type = "Label", Name = "Loading wapus integration..."},
                    }
                }
            }
        }
    }
}
