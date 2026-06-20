--[[
    Game Config - Arsenal (PlaceId: 286090429)
]]

return {
    Pages = {
        {
            Name = "combat",
            Sections = {
                {
                    Name = "Silent Aim",
                    Side = 1,
                    Elements = {
                        {Type = "Toggle", Name = "Enable", Flag = "SilentAim", Default = false},
                        {Type = "Dropdown", Name = "Hit Part", Flag = "SilentHitPart", Items = {"Head", "Torso", "HumanoidRootPart"}, Default = "Head"},
                        {Type = "Slider", Name = "FOV Radius", Flag = "SilentFOV", Min = 10, Max = 800, Default = 200, Decimals = 1, Suffix = "px"},
                        {Type = "Toggle", Name = "Wall Check", Flag = "WallCheck", Default = true},
                        {Type = "Toggle", Name = "Show FOV Circle", Flag = "ShowFOVCircle", Default = false},
                        {Type = "Label", Name = "FOV Color", Colorpicker = {Name = "FOV Color", Flag = "FOVCircleColor", Default = Color3.fromRGB(255, 255, 255)}},
                    }
                },
                {
                    Name = "Gun Mods",
                    Side = 2,
                    Elements = {
                        {Type = "Toggle", Name = "Infinite Ammo", Flag = "InfiniteAmmo", Default = false, Detection = "detected"},
                        {Type = "Toggle", Name = "Fast Fire", Flag = "FastFire", Default = false, Detection = "detected"},
                        {Type = "Slider", Name = "Fire Rate", Flag = "FireRate", Min = 0.01, Max = 0.5, Default = 0.05, Decimals = 0.01, Suffix = "s", Detection = "detected"},
                        {Type = "Toggle", Name = "No Recoil", Flag = "NoRecoil", Default = false, Detection = "detected"},
                        {Type = "Toggle", Name = "Full Auto", Flag = "FullAuto", Default = false, Detection = "detected"},
                        {Type = "Toggle", Name = "No Spread", Flag = "NoSpread", Default = false, Detection = "detected"},
                    }
                }
            }
        },
        {
            Name = "misc",
            Sections = {
                {
                    Name = "Movement",
                    Side = 1,
                    Elements = {
                        {Type = "Toggle", Name = "Speed Hack", Flag = "SpeedHack", Default = false},
                        {Type = "Slider", Name = "Speed Value", Flag = "SpeedValue", Min = 16, Max = 200, Default = 50, Decimals = 1, Suffix = " studs/s"},
                        {Type = "Toggle", Name = "Fly", Flag = "FlyEnabled", Default = false},
                        {Type = "Slider", Name = "Fly Speed", Flag = "FlySpeed", Min = 1, Max = 300, Default = 50, Decimals = 1, Suffix = " studs/s"},
                        {Type = "Toggle", Name = "No Clip", Flag = "NoClip", Default = false},
                        {Type = "Toggle", Name = "Infinite Jump", Flag = "InfJump", Default = false},
                    }
                },
                {
                    Name = "Exploits",
                    Side = 2,
                    Elements = {
                        {Type = "Toggle", Name = "Anti AFK", Flag = "AntiAFK", Default = false},
                        {Type = "Toggle", Name = "God Mode", Flag = "GodMode", Default = false},
                        {Type = "Toggle", Name = "Instant Win", Flag = "InstantWin", Default = false},
                        {Type = "Button", Name = "Old Case Access", Flag = "OldCaseAccess", Detection = "warn"},
                        {Type = "Button", Name = "Skip Gun"},
                        {Type = "Button", Name = "Rejoin Server"},
                        {Type = "Button", Name = "Server Hop"},
                        {Type = "Textbox", Name = "Teleport to Player", Flag = "TpToPlayer", Placeholder = "Username", Finished = true},
                    }
                }
            }
        },
        {
            Name = "visuals",
            Sections = {
                {
                    Name = "ESP",
                    Side = 1,
                    Elements = {
                        {Type = "Toggle", Name = "Player ESP", Flag = "PlayerESP", Default = false},
                        {Type = "Toggle", Name = "Box ESP", Flag = "BoxESP", Default = false},
                        {Type = "Toggle", Name = "Name ESP", Flag = "NameESP", Default = false},
                        {Type = "Toggle", Name = "Health Bar", Flag = "HealthBar", Default = false},
                        {Type = "Toggle", Name = "Tracers", Flag = "Tracers", Default = false},
                        {Type = "Label", Name = "ESP Color", Colorpicker = {Name = "ESP Color", Flag = "ESPColor", Default = Color3.fromRGB(255, 50, 50)}},
                        {Type = "Toggle", Name = "Chams", Flag = "Chams", Default = false},
                    }
                },
                {
                    Name = "World",
                    Side = 2,
                    Elements = {
                        {Type = "Toggle", Name = "Fullbright", Flag = "Fullbright", Default = false},
                        {Type = "Slider", Name = "Field of View", Flag = "FOV", Min = 30, Max = 120, Default = 90, Decimals = 1, Suffix = "°"},
                        {Type = "Toggle", Name = "No Fog", Flag = "NoFog", Default = false},
                        {Type = "Button", Name = "Remove Decorations"},
                    }
                }
            }
        },
        {
            Name = "players",
            Sections = {
                {
                    Name = "Targeting",
                    Side = 1,
                    Elements = {
                        {Type = "Dropdown", Name = "Target Priority", Flag = "TargetPriority", Items = {"Closest to Cursor", "Closest Distance", "Lowest Health", "Random"}, Default = "Closest to Cursor"},
                        {Type = "Slider", Name = "Max Distance", Flag = "MaxAimDist", Min = 50, Max = 2000, Default = 600, Decimals = 1, Suffix = " studs"},
                    }
                },
                {
                    Name = "Info",
                    Side = 2,
                    Elements = {
                        {Type = "Button", Name = "Refresh Player List"},
                        {Type = "Textbox", Name = "Spectate Player", Flag = "SpectatePlayer", Placeholder = "Username", Finished = true},
                        {Type = "Button", Name = "Stop Spectating"},
                    }
                }
            }
        }
    }
}
