# banknote

A multi-game Roblox script hub. One loader detects the game you're in and
pulls the matching feature set, all behind a single self-hosted UI.

## Usage

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/winterhike/note/refs/heads/master/loader.lua?_=" .. tostring(tick()) .. tostring(math.random(1, 1e6))))()
```

## How it works

- **`loader.lua`** identifies the game by PlaceId (falling back to UniverseId
  for games with per-match sub-places), then loads that game's config + logic.
  It caches files locally and pins to the latest commit so updates are instant.
- **`library/Library.lua`** is the UI library every game draws into.
- **`UI.lua`** builds the menu from a game's config table.
- **`games/<id>.lua`** is a game's config; **`games/logic/<id>.lua`** is its
  feature logic. Games without an entry fall back to `games/universal.lua`.

## Supported games

Phantom Forces, Rivals, REDLINER, D.I.G, Da Hood, and more, plus a universal
fallback for everything else.

## Custom luas

Drop your own `.lua` files into the `banknote/ui/Luas` folder on your executor.
Open the **lua** tab in-game, refresh, and load them — each one declares a
category (Combat / Misc / Visuals / ...) and shows up there as native features.
See `luas/skeleton.lua` for the format.

## Disclaimer

For educational use. Using exploits can get your account banned — use at your
own risk.
