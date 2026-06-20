--[[
    Game Config - Bedwars (PlaceId: 6872274481)
]]

return {
    Pages = {
        {
            Name = "combat",
            Sections = {
                {
                    Name = "Aimbot",
                    Side = 1,
                    Elements = {
                        {Type = "Toggle", Name = "Silent Aim", Flag = "SilentAim", Default = false},
                        {Type = "Dropdown", Name = "Target Part", Flag = "TargetPart", Items = {"Head", "Torso", "Random"}, Default = "Head"},
                        {Type = "Slider", Name = "FOV Radius", Flag = "AimFOV", Min = 10, Max = 500, Default = 150, Decimals = 1, Suffix = "px"},
                        {Type = "Toggle", Name = "Show FOV Circle", Flag = "ShowFOV", Default = false},
                        {Type = "Toggle", Name = "Team Check", Flag = "TeamCheck", Default = true},
                    }
                },
                {
                    Name = "Combat",
                    Side = 2,
                    Elements = {
                        {Type = "Toggle", Name = "Kill Aura", Flag = "KillAura", Default = false},
                        {Type = "Slider", Name = "Aura Range", Flag = "AuraRange", Min = 5, Max = 50, Default = 15, Decimals = 1, Suffix = " studs"},
                        {Type = "Toggle", Name = "Auto Clicker", Flag = "AutoClick", Default = false},
                        {Type = "Slider", Name = "CPS", Flag = "CPS", Min = 1, Max = 50, Default = 15, Decimals = 1, Suffix = " clicks/s"},
                        {Type = "Toggle", Name = "Reach", Flag = "Reach", Default = false},
                        {Type = "Slider", Name = "Reach Distance", Flag = "ReachDist", Min = 5, Max = 30, Default = 12, Decimals = 1, Suffix = " studs"},
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
                        {Type = "Toggle", Name = "Spider", Flag = "Spider", Default = false},
                    }
                },
                {
                    Name = "Exploits",
                    Side = 2,
                    Elements = {
                        {Type = "Toggle", Name = "Anti AFK", Flag = "AntiAFK", Default = false},
                        {Type = "Toggle", Name = "God Mode", Flag = "GodMode", Default = false},
                        {Type = "Toggle", Name = "Auto Bed Break", Flag = "AutoBedBreak", Default = false},
                        {Type = "Toggle", Name = "Infinite Resources", Flag = "InfResources", Default = false},
                        {Type = "Toggle", Name = "Auto Bridge", Flag = "AutoBridge", Default = false},
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
                        {Type = "Toggle", Name = "Bed ESP", Flag = "BedESP", Default = false},
                        {Type = "Toggle", Name = "Box ESP", Flag = "BoxESP", Default = false},
                        {Type = "Toggle", Name = "Name ESP", Flag = "NameESP", Default = false},
                        {Type = "Toggle", Name = "Tracers", Flag = "Tracers", Default = false},
                        {Type = "Label", Name = "ESP Color", Colorpicker = {Name = "ESP Color", Flag = "ESPColor", Default = Color3.fromRGB(255, 100, 0)}},
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
                        {Type = "Slider", Name = "Max Distance", Flag = "MaxAimDist", Min = 50, Max = 2000, Default = 500, Decimals = 1, Suffix = " studs"},
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
