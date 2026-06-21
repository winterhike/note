--[[
    Game Config - D.I.G (PlaceId 98129535207266, universe 7304084567)
    The real feature set is provided by the full logic file
    (games/logic/98129535207266.lua), a native banknote implementation of the
    D.I.G combat features. This config only exists so the loader resolves a
    valid game instead of universal.
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
                        { Type = "Label", Name = "Loading D.I.G..." },
                    }
                }
            }
        }
    }
}
