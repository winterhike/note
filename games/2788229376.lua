--[[
    Game Config - Da Hood (PlaceId 2788229376)
    The real feature set is provided by the full logic file
    (games/logic/2788229376.lua) - the "sample.hit" Da Hood feature set ported
    onto the banknote UI via a UI shim (ESP and telemetry excluded). This config
    only exists so the loader resolves a valid game instead of universal.
]]

return {
    Pages = {
        {
            Name = "main",
            Sections = {
                {
                    Name = "Info",
                    Side = 1,
                    Elements = {
                        { Type = "Label", Name = "Loading Da Hood..." },
                    }
                }
            }
        }
    }
}
