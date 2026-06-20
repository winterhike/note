--[[
    Universal Config - Works for any game without a specific config.
    This is the fallback when no PlaceId match is found.
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
                        {Type = "Slider", Name = "FOV Radius", Flag = "AimFOV", Min = 10, Max = 500, Default = 100, Decimals = 1, Suffix = "px"},
                        {Type = "Toggle", Name = "Show FOV Circle", Flag = "ShowFOV", Default = false},
                        {Type = "Toggle", Name = "Team Check", Flag = "TeamCheck", Default = true},
                        {Type = "Toggle", Name = "Wall Check", Flag = "WallCheck", Default = true},
                    }
                },
                {
                    Name = "Melee",
                    Side = 2,
                    Elements = {
                        {Type = "Toggle", Name = "Auto Parry", Flag = "AutoParry", Default = false},
                        {Type = "Toggle", Name = "Kill Aura", Flag = "KillAura", Default = false},
                        {Type = "Slider", Name = "Aura Range", Flag = "AuraRange", Min = 1, Max = 50, Default = 10, Decimals = 1, Suffix = " studs"},
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
                        {Type = "Toggle", Name = "Infinite Jump", Flag = "InfJump", Default = false},
                        {Type = "Toggle", Name = "Fly", Flag = "FlyEnabled", Default = false},
                        {Type = "Slider", Name = "Fly Speed", Flag = "FlySpeed", Min = 1, Max = 300, Default = 50, Decimals = 1, Suffix = " studs/s"},
                        {Type = "Toggle", Name = "No Clip", Flag = "NoClip", Default = false},
                    }
                },
                {
                    Name = "Exploits",
                    Side = 2,
                    Elements = {
                        {Type = "Toggle", Name = "Anti AFK", Flag = "AntiAFK", Default = false},
                        {Type = "Toggle", Name = "No Fall Damage", Flag = "NoFallDmg", Default = false},
                        {Type = "Toggle", Name = "God Mode", Flag = "GodMode", Default = false},
                        {Type = "Slider", Name = "Jump Power", Flag = "JumpPower", Min = 50, Max = 500, Default = 50, Decimals = 1},
                        {Type = "Slider", Name = "Gravity", Flag = "Gravity", Min = 0, Max = 500, Default = 196, Decimals = 1},
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
                        {Type = "Dropdown", Name = "Tracer Origin", Flag = "TracerOrigin", Items = {"Bottom", "Center", "Mouse"}, Default = "Bottom"},
                        {Type = "Label", Name = "ESP Color", Colorpicker = {Name = "ESP Color", Flag = "ESPColor", Default = Color3.fromRGB(255, 0, 0)}},
                        {Type = "Toggle", Name = "Chams", Flag = "Chams", Default = false},
                        {Type = "Label", Name = "Chams Color", Colorpicker = {Name = "Chams Color", Flag = "ChamsColor", Default = Color3.fromRGB(128, 0, 255)}},
                    }
                },
                {
                    Name = "World",
                    Side = 2,
                    Elements = {
                        {Type = "Toggle", Name = "Fullbright", Flag = "Fullbright", Default = false},
                        {Type = "Slider", Name = "Field of View", Flag = "FOV", Min = 30, Max = 120, Default = 70, Decimals = 1, Suffix = "°"},
                        {Type = "Toggle", Name = "No Fog", Flag = "NoFog", Default = false},
                        {Type = "Slider", Name = "Time of Day", Flag = "TimeOfDay", Min = 0, Max = 24, Default = 14, Decimals = 1, Suffix = " hrs"},
                        {Type = "Toggle", Name = "Remove Shadows", Flag = "NoShadows", Default = false},
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
                        {Type = "Dropdown", Name = "Aim Target", Flag = "AimTarget", Items = {"Closest to Cursor", "Closest Distance", "Lowest Health", "Random"}, Default = "Closest to Cursor"},
                        {Type = "Slider", Name = "Max Distance", Flag = "MaxAimDist", Min = 50, Max = 2000, Default = 500, Decimals = 1, Suffix = " studs"},
                        {Type = "Toggle", Name = "Highlight Target", Flag = "HighlightTarget", Default = false},
                    }
                },
                {
                    Name = "Player Info",
                    Side = 2,
                    Elements = {
                        {Type = "Button", Name = "Refresh Player List"},
                        {Type = "Textbox", Name = "Spectate Player", Flag = "SpectatePlayer", Placeholder = "Username", Finished = true},
                        {Type = "Button", Name = "Stop Spectating"},
                        {Type = "Textbox", Name = "Copy Player Info", Flag = "CopyPlayerInfo", Placeholder = "Username", Finished = true},
                    }
                }
            }
        }
    }
}
