--[[
    Game Config - BloxStrike (PlaceId 114234929420007, universe 7633926880)
    BloxStrike is a CS-style shooter that runs matches on per-match sub-places,
    so the loader resolves every sub-place to this id via the universe map.

    The real feature set is provided by the full logic file
    (games/logic/114234929420007.lua): ESP (Drawing-based, AC-safe), a
    field-swap silent aim, and a best-effort BAC bypass. This config only
    exists so the loader resolves a valid game instead of universal.
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
                        { Type = "Label", Name = "BloxStrike - no features yet" },
                    }
                }
            }
        }
    }
}
