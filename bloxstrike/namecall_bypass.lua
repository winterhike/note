-- this is easily patchable btw frog pls patch the shit out of this
-- https://github.com/mental1illness/fixed/blob/main/Games/BloxStrike/BadNamecallDetectorBypass.luau


local ToNotTrust = nil;
local Old; Old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    local Method = getnamecallmethod()
    local ScriptCalling = getcallingscript()

    if Method == "FakeIndex" then
        if ScriptCalling then
            ToNotTrust = ScriptCalling
        end
        return false, 'FakeIndex is not a valid member of DataModel "Ugc"'
    end

    if ScriptCalling and ToNotTrust and ScriptCalling == ToNotTrust then
        -- warn("yo", ScriptCalling, "i ain't gon trust u")
        return Old(self, ...)
    end

    return Old(self, ...)
end))


--[[
OLD DO NOT USE.
local Constants = {
    ["IgnoredScript"] = {
        ["KnitClient"] = true;
        ["CameraShaker"] = true;
        ["FriendList"] = true;
        ["LoadingScreen"] = true;
        ["KnitClient"] = true;
        ["RobloxCore"] = true;
        ["ControlScript"] = true;
        ["ControlModule"] = true;
        ["LoadingScreen"] = true;
        -- ["Startup"] = true;
    },
}
        local Old; Old = hookfunction(getrenv().xpcall, newcclosure(function(...)
            local CallingScript = getcallingscript()
                if CallingScript then
                    local Name = tostring(CallingScript)
                    if Name and Constants["IgnoredScript"][Name] then
                        return false, "frog im here lul"
                    end
                end
            return Old(...)
        end))

]]
---

-- OR:

--------------


    local CheckIfMethodIsValid = function(Self, Method)
        return Self[Method] ~= nil;
    end

local ToNotTrust = nil;
local Old; Old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    local Method = getnamecallmethod()
    local ScriptCalling = getcallingscript()
        
        if self == game and Method == "WaitForChild" then
            if typeof(Arguments[1]) == "table" then
                return false, "invalid argument #1 to 'WaitForChild' (string expected, got table)"
            end
        end

        if Method == "OmgUnvirNamecall" or Method == "FakeIndex" or not CheckIfMethodIsValid(self, Method) then
            if ScriptCalling then
                ToNotTrust = ScriptCalling;
            end
            return false, Method .. ' is not a valid member of DataModel "Ugc"'
        end

        if ScriptCalling and ToNotTrust and ScriptCalling == ToNotTrust then
            return Old(self, ...)
        end
    return Old(self, ...)
end))


