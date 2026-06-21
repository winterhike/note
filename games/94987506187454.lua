--[[
    Game Config - REDLINER (universe 7265339759, sub-places included)
    The real feature set is provided by the full logic file
    (games/logic/94987506187454.lua), which runs the VapeV4 REDLINER feature
    logic through a Vape-compatibility shim on the banknote UI. This config
    only exists so the loader resolves a valid game instead of universal.
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
