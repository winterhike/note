--[[
    Game Config - Phantom Forces (PlaceId: 254965063)
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
                        {Type = "Dropdown", Name = "Target Part", Flag = "TargetPart", Items = {"Head", "Torso", "Limbs", "Random"}, Default = "Head"},
                        {Type = "Slider", Name = "FOV Radius", Flag = "AimFOV", Min = 10, Max = 500, Default = 100, Decimals = 1, Suffix = "px"},
                        {Type = "Toggle", Name = "Show FOV Circle", Flag = "ShowFOV", Default = false},
                        {Type = "Toggle", Name = "Team Check", Flag = "TeamCheck", Default = true},
                        {Type = "Toggle", Name = "Wall Check", Flag = "WallCheck", Default = true},
                        {Type = "Slider", Name = "Prediction", Flag = "AimPrediction", Min = 0, Max = 10, Default = 1, Decimals = 1, Suffix = ""},
                    }
                },
                {
                    Name = "Weapons",
                    Side = 2,
                    Elements = {
                        {Type = "Toggle", Name = "No Recoil", Flag = "NoRecoil", Default = false},
                        {Type = "Toggle", Name = "No Spread", Flag = "NoSpread", Default = false},
                        {Type = "Toggle", Name = "No Sway", Flag = "NoSway", Default = false},
                        {Type = "Toggle", Name = "Rapid Fire", Flag = "RapidFire", Default = false},
                        {Type = "Toggle", Name = "Instant Reload", Flag = "InstantReload", Default = false},
                        {Type = "Toggle", Name = "Infinite Ammo", Flag = "InfAmmo", Default = false},
                        {Type = "Toggle", Name = "No Bullet Drop", Flag = "NoBulletDrop", Default = false},
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
                        {Type = "Toggle", Name = "Super Jump", Flag = "SuperJump", Default = false},
                    }
                },
                {
                    Name = "Exploits",
                    Side = 2,
                    Elements = {
                        {Type = "Toggle", Name = "Anti AFK", Flag = "AntiAFK", Default = false},
                        {Type = "Toggle", Name = "God Mode", Flag = "GodMode", Default = false},
                        {Type = "Toggle", Name = "Instant Respawn", Flag = "InstantRespawn", Default = false},
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
                        {Type = "Label", Name = "ESP Color", Colorpicker = {Name = "ESP Color", Flag = "ESPColor", Default = Color3.fromRGB(0, 255, 100)}},
                        {Type = "Toggle", Name = "Chams", Flag = "Chams", Default = false},
                    }
                },
                {
                    Name = "World",
                    Side = 2,
                    Elements = {
                        {Type = "Toggle", Name = "Fullbright", Flag = "Fullbright", Default = false},
                        {Type = "Slider", Name = "Field of View", Flag = "FOV", Min = 30, Max = 120, Default = 80, Decimals = 1, Suffix = "°"},
                        {Type = "Toggle", Name = "No Fog", Flag = "NoFog", Default = false},
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
                        {Type = "Dropdown", Name = "Target Priority", Flag = "TargetPriority", Items = {"Closest to Cursor", "Closest Distance", "Lowest Health"}, Default = "Closest to Cursor"},
                        {Type = "Slider", Name = "Max Distance", Flag = "MaxAimDist", Min = 50, Max = 5000, Default = 1000, Decimals = 1, Suffix = " studs"},
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
