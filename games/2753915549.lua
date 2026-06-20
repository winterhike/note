--[[
    Game Config - Blade Ball (PlaceId: 2753915549)
    Features specific to this game.
]]

return {
    Pages = {
        {
            Name = "combat",
            Sections = {
                {
                    Name = "Parry",
                    Side = 1,
                    Elements = {
                        {Type = "Toggle", Name = "Auto Parry", Flag = "AutoParry", Default = false},
                        {Type = "Slider", Name = "Parry Distance", Flag = "ParryDist", Min = 1, Max = 50, Default = 15, Decimals = 1, Suffix = " studs"},
                        {Type = "Dropdown", Name = "Parry Mode", Flag = "ParryMode", Items = {"Normal", "Spam", "Perfect"}, Default = "Normal"},
                        {Type = "Toggle", Name = "Auto Spam", Flag = "AutoSpam", Default = false},
                    }
                },
                {
                    Name = "Movement",
                    Side = 2,
                    Elements = {
                        {Type = "Toggle", Name = "Auto Dodge", Flag = "AutoDodge", Default = false},
                        {Type = "Slider", Name = "Dodge Distance", Flag = "DodgeDist", Min = 5, Max = 100, Default = 20, Decimals = 1, Suffix = " studs"},
                        {Type = "Toggle", Name = "Speed Boost", Flag = "SpeedBoost", Default = false},
                        {Type = "Slider", Name = "Speed Value", Flag = "SpeedValue", Min = 16, Max = 150, Default = 40, Decimals = 1, Suffix = ""},
                    }
                }
            }
        },
        {
            Name = "misc",
            Sections = {
                {
                    Name = "Utilities",
                    Side = 1,
                    Elements = {
                        {Type = "Toggle", Name = "Anti AFK", Flag = "AntiAFK", Default = false},
                        {Type = "Toggle", Name = "Auto Collect Coins", Flag = "AutoCoins", Default = false},
                        {Type = "Toggle", Name = "Auto Ability", Flag = "AutoAbility", Default = false},
                        {Type = "Dropdown", Name = "Ability", Flag = "Ability", Items = {"Dash", "Forcefield", "Teleport", "Invisibility"}, Default = "Dash"},
                        {Type = "Button", Name = "Rejoin Server"},
                        {Type = "Button", Name = "Server Hop"},
                    }
                },
                {
                    Name = "Player",
                    Side = 2,
                    Elements = {
                        {Type = "Toggle", Name = "Infinite Jump", Flag = "InfJump", Default = false},
                        {Type = "Toggle", Name = "Fly", Flag = "FlyEnabled", Default = false},
                        {Type = "Slider", Name = "Fly Speed", Flag = "FlySpeed", Min = 1, Max = 300, Default = 50, Decimals = 1, Suffix = " studs/s"},
                        {Type = "Toggle", Name = "No Clip", Flag = "NoClip", Default = false},
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
                        {Type = "Toggle", Name = "Ball ESP", Flag = "BallESP", Default = false},
                        {Type = "Toggle", Name = "Ball Tracers", Flag = "BallTracers", Default = false},
                        {Type = "Toggle", Name = "Player ESP", Flag = "PlayerESP", Default = false},
                        {Type = "Toggle", Name = "Name ESP", Flag = "NameESP", Default = false},
                        {Type = "Label", Name = "ESP Color", Colorpicker = {Name = "ESP Color", Flag = "ESPColor", Default = Color3.fromRGB(255, 50, 50)}},
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
                        {Type = "Dropdown", Name = "Target Priority", Flag = "TargetPriority", Items = {"Closest", "Most Wins", "Random"}, Default = "Closest"},
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
