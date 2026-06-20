--[[
    Game Config - RIVALS (PlaceId: 17625359962)
    Features ported from Instance.lua
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
                        {Type = "Toggle", Name = "Backshoot", Flag = "BackshootToggle", Default = false},
                        {Type = "Toggle", Name = "Anti Katana", Flag = "AntiKatana", Default = false},
                        {Type = "Slider", Name = "Hit Chance", Flag = "HitChance", Min = 0, Max = 100, Default = 100, Decimals = 1, Suffix = "%"},
                        {Type = "Dropdown", Name = "Hit Part", Flag = "HitPartDropdown", Items = {"Head", "HumanoidRootPart", "Torso", "UpperTorso", "LowerTorso", "Left Arm", "Right Arm", "Left Leg", "Right Leg", "Closest", "Random"}, Default = "Head"},
                        {Type = "Toggle", Name = "Auto Shoot", Flag = "SilentAutoShoot", Default = false},
                        {Type = "Toggle", Name = "Show FOV", Flag = "ShowFOV", Default = false},
                        {Type = "Slider", Name = "FOV Radius", Flag = "FOVRadius", Min = 10, Max = 500, Default = 100, Decimals = 1, Suffix = "px"},
                        {Type = "Toggle", Name = "Follow Muzzle", Flag = "SilentFOVFollowMuzzle", Default = false},
                    }
                },
                {
                    Name = "Aimbot",
                    Side = 2,
                    Elements = {
                        {Type = "Toggle", Name = "Enable", Flag = "AimbotToggle", Default = false},
                        {Type = "Slider", Name = "Smoothness", Flag = "AimbotSmoothness", Min = 1, Max = 10, Default = 2, Decimals = 1},
                        {Type = "Dropdown", Name = "Aim Curve", Flag = "AimbotCurve", Items = {"Linear", "Expo", "EaseIn", "EaseOut", "EaseInOut", "Cubic", "Instant"}, Default = "Linear"},
                        {Type = "Dropdown", Name = "Hit Part", Flag = "AimbotHitPart", Items = {"Head", "HumanoidRootPart", "Torso", "UpperTorso", "LowerTorso"}, Default = "Head"},
                        {Type = "Toggle", Name = "Show FOV", Flag = "ShowAimbotFOV", Default = false},
                        {Type = "Slider", Name = "FOV Radius", Flag = "AimbotFOV", Min = 10, Max = 1000, Default = 500, Decimals = 1, Suffix = "px"},
                        {Type = "Toggle", Name = "Follow Muzzle", Flag = "AimbotFOVFollowMuzzle", Default = false},
                    }
                }
            }
        },
        {
            Name = "character",
            Sections = {
                {
                    Name = "Profile",
                    Side = 2,
                    Elements = {
                        {Type = "Toggle", Name = "Name Spoof", Flag = "NameSpoof", Default = false},
                        {Type = "Textbox", Name = "Custom Name", Flag = "CustomName", Placeholder = "Name", Finished = true},
                        {Type = "Toggle", Name = "Skin Changer", Flag = "SkinChanger", Default = false},
                    }
                },
                {
                    Name = "Movement",
                    Side = 2,
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
                    Name = "Spoofing",
                    Side = 1,
                    Elements = {
                        {Type = "Toggle", Name = "FPS Spoof", Flag = "FPSSpoof", Default = false},
                        {Type = "Slider", Name = "FPS Value", Flag = "FPSValue", Min = 1, Max = 500, Default = 60, Decimals = 1},
                        {Type = "Toggle", Name = "Ping Spoof", Flag = "PingSpoof", Default = false},
                        {Type = "Slider", Name = "Ping Value", Flag = "PingValue", Min = 0, Max = 999, Default = 30, Decimals = 1, Suffix = "ms"},
                        {Type = "Toggle", Name = "Region Spoof", Flag = "RegionSpoof", Default = false},
                        {Type = "Dropdown", Name = "Region", Flag = "RegionValue", Items = {"NA-East", "NA-West", "EU-West", "EU-East", "Asia", "OCE", "SA"}, Default = "NA-East"},
                    }
                },
                {
                    Name = "Self Material",
                    Side = 1,
                    Elements = {
                        {Type = "Toggle", Name = "Enable", Flag = "SelfMaterial", Default = false},
                        {Type = "Dropdown", Name = "Material", Flag = "SelfMaterialType", Items = {"ForceField", "Neon", "Glass", "SmoothPlastic", "Ice", "Foil"}, Default = "ForceField"},
                        {Type = "Label", Name = "Material Color", Colorpicker = {Name = "Material Color", Flag = "SelfMaterialColor", Default = Color3.fromRGB(0, 200, 255)}},
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
                        {Type = "Toggle", Name = "Box ESP", Flag = "BoxESP", Default = false},
                        {Type = "Toggle", Name = "Name ESP", Flag = "NameESP", Default = false},
                        {Type = "Toggle", Name = "Health Bar", Flag = "HealthBar", Default = false},
                        {Type = "Toggle", Name = "Tracers", Flag = "Tracers", Default = false},
                        {Type = "Toggle", Name = "Chams", Flag = "Chams", Default = false},
                        {Type = "Toggle", Name = "Skeleton ESP", Flag = "SkeletonESP", Default = false},
                        {Type = "Label", Name = "ESP Color", Colorpicker = {Name = "ESP Color", Flag = "ESPColor", Default = Color3.fromRGB(255, 0, 0)}},
                    }
                },
                {
                    Name = "Lighting",
                    Side = 2,
                    Elements = {
                        {Type = "Toggle", Name = "Custom Lighting", Flag = "CustomLighting", Default = false},
                        {Type = "Toggle", Name = "Fullbright", Flag = "Fullbright", Default = false},
                        {Type = "Toggle", Name = "No Fog", Flag = "NoFog", Default = false},
                        {Type = "Toggle", Name = "No Shadows", Flag = "NoShadows", Default = false},
                        {Type = "Slider", Name = "Brightness", Flag = "Brightness", Min = 0, Max = 5, Default = 1, Decimals = 1},
                        {Type = "Label", Name = "Ambient Color", Colorpicker = {Name = "Ambient Color", Flag = "AmbientColor", Default = Color3.fromRGB(128, 128, 128)}},
                    }
                }
            }
        },
        {
            Name = "world",
            Sections = {
                {
                    Name = "Bullet Tracers",
                    Side = 1,
                    Elements = {
                        {Type = "Toggle", Name = "Enable", Flag = "BulletTracers", Default = false},
                        {Type = "Dropdown", Name = "Style", Flag = "TracerStyle", Items = {"Line", "Beam", "Lightning", "Heartrate", "Chain", "Glitch", "Swirl", "Neon", "Plasma", "Laser"}, Default = "Line"},
                        {Type = "Slider", Name = "Size", Flag = "TracerSize", Min = 1, Max = 10, Default = 1, Decimals = 1},
                        {Type = "Slider", Name = "Duration", Flag = "TracerDuration", Min = 1, Max = 10, Default = 3, Decimals = 1, Suffix = "s"},
                        {Type = "Slider", Name = "Glow", Flag = "TracerGlow", Min = 0, Max = 5, Default = 0, Decimals = 1},
                        {Type = "Label", Name = "Tracer Color", Colorpicker = {Name = "Tracer Color", Flag = "TracerColor", Default = Color3.fromRGB(255, 255, 255)}},
                    }
                },
                {
                    Name = "Hit Effects",
                    Side = 2,
                    Elements = {
                        {Type = "Toggle", Name = "Hit Sound", Flag = "HitSoundEnabled", Default = false},
                        {Type = "Dropdown", Name = "Sound", Flag = "HitSoundStyle", Items = {"Rust HS", "Neverlose", "Minecraft Bow", "CSGO", "Bubble", "Pop", "Sans", "Skeet", "Fatality", "Bonk", "Osu", "TF2 Critical", "Saber"}, Default = "Rust HS"},
                        {Type = "Slider", Name = "Volume", Flag = "HitSoundVolume", Min = 0, Max = 3, Default = 1, Decimals = 1},
                        {Type = "Slider", Name = "Pitch", Flag = "HitSoundPitch", Min = 0, Max = 3, Default = 1, Decimals = 1},
                        {Type = "Toggle", Name = "Hit Notif", Flag = "HitNotif", Default = false},
                        {Type = "Toggle", Name = "Kill Sound", Flag = "KillSoundEnabled", Default = false},
                    }
                }
            }
        },
        {
            Name = "misc",
            Sections = {
                {
                    Name = "Auto Ban (Ranked)",
                    Side = 1,
                    Elements = {
                        {Type = "Toggle", Name = "Enable", Flag = "AutoBan", Default = false},
                        {Type = "Dropdown", Name = "Weapon", Flag = "AutoBanWeapon", Items = {"AK-47", "M4A1", "AWP", "Desert Eagle", "MP5"}, Default = "AK-47"},
                        {Type = "Toggle", Name = "Anti Aim", Flag = "AntiAim", Default = false},
                    }
                },
                {
                    Name = "QOL",
                    Side = 2,
                    Elements = {
                        {Type = "Toggle", Name = "Auto Queue", Flag = "AutoQueue", Default = false},
                        {Type = "Dropdown", Name = "Queue Mode", Flag = "QueueMode", Items = {"1v1", "2v2", "3v3", "4v4", "5v5"}, Default = "1v1"},
                        {Type = "Toggle", Name = "Anti AFK", Flag = "AntiAFK", Default = false},
                        {Type = "Toggle", Name = "Disable Gun Sounds", Flag = "DisableGunSounds", Default = false},
                        {Type = "Toggle", Name = "Device Spoof", Flag = "DeviceSpoof", Default = false},
                        {Type = "Dropdown", Name = "Device", Flag = "DeviceType", Items = {"PC", "Mobile", "Console", "VR"}, Default = "PC"},
                        {Type = "Toggle", Name = "Slide Boost", Flag = "SlideBoost", Default = false},
                        {Type = "Toggle", Name = "Motion Blur", Flag = "MotionBlur", Default = false},
                        {Type = "Toggle", Name = "Smooth Textures", Flag = "SmoothTextures", Default = false},
                        {Type = "Button", Name = "Rejoin Server"},
                        {Type = "Button", Name = "Server Hop"},
                    }
                }
            }
        }
    }
}
