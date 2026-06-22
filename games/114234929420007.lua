--[[
    Game Config - BloxStrike (PlaceId 114234929420007, universe 7633926880)
    BloxStrike is a CS-style shooter that runs matches on per-match sub-places,
    so the loader resolves every sub-place to this id via the universe map.

    Skeleton only - no features implemented yet. This exists so the loader
    detects/supports the game (instead of falling back to universal). Add
    sections/elements here, or a full-logic file at
    games/logic/114234929420007.lua, once features are built.
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
