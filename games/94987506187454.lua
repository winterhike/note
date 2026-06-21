--[[
    Game Config - REDLINER (universe 7265339759, sub-places included)
    The real feature set is provided by the full logic file
    (games/logic/94987506187454.lua), a NATIVE banknote implementation of the
    REDLINER features (no Vape framework / shim). This config only exists so
    the loader resolves a valid game instead of universal.
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
                        { Type = "Label", Name = "Loading REDLINER..." },
                    }
                }
            }
        }
    }
}
