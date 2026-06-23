--[[ BAC beat collector - CANARY-DEFENDED namecall hook (survives BAC's probe).
     The raw hookmetamethod was caught in ~3s because it didn't answer BAC's
     FakeIndex / OmgUnvirNamecall / WaitForChild(table) canary probes. This hook
     answers them with the genuine error (per namecall_bypass.lua), so it lives,
     and we capture every Remotes.BAC FireServer beat to "bac_beats.txt".

     Run it, play a round (let beats accumulate), then send me bac_beats.txt.
     ONE account/session only (key = Name+UserId).
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local lp                = Players.LocalPlayer

local remote = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild("BAC")
if not remote then
    for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
        if d.Name == "BAC" and d:IsA("RemoteEvent") then remote = d break end
    end
end
assert(remote, "no BAC remote")

local file = "bac_beats.txt"
pcall(writefile, file, string.format("# name=%s userid=%d f2=%d f4=%d\n# nonce_dec,seq,digest_hex\n",
    lp.Name, lp.UserId, lp.UserId * 2, lp.UserId * 4))

local count = 0
local function logBeat(s)
    local b, i = {}, 1
    while i <= #s do
        local n = s:match("^!(%d+)!", i)
        if n then b[#b+1] = tonumber(n); i = i + #n + 2 else b[#b+1] = s:byte(i); i = i + 1 end
    end
    local nonce = (b[1] or 0) + (b[2] or 0) * 256
    local seq = b[3]
    local dash
    for j = 1, #b do if b[j] == 0x2D then dash = j break end end
    local hx = {}
    if dash then for j = dash + 1, #b do hx[#hx+1] = string.format("%02x", b[j]) end end
    local line = string.format("%d,%s,%s", nonce, tostring(seq), table.concat(hx))
    count += 1
    print("[beat " .. count .. "] " .. line)
    pcall(appendfile, file, line .. "\n")
end

local getnc = getnamecallmethod or get_namecall_method
local getcs  = getcallingscript

local function validMember(self, method)
    local ok, v = pcall(function() return self[method] end)
    return ok and v ~= nil
end

local ToNotTrust = nil
local Old
Old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    local method = getnc()
    local scriptCalling = getcs and getcs() or nil

    -- canary 1: WaitForChild with a table arg
    if self == game and method == "WaitForChild" then
        local a1 = (...)
        if typeof(a1) == "table" then
            return false, "invalid argument #1 to 'WaitForChild' (string expected, got table)"
        end
    end

    -- canary 2: invalid-member probes (OmgUnvirNamecall / FakeIndex / anything fake)
    if method == "OmgUnvirNamecall" or method == "FakeIndex" or (method and not validMember(self, method)) then
        if scriptCalling then ToNotTrust = scriptCalling end
        return false, method .. ' is not a valid member of DataModel "Ugc"'
    end

    -- capture the heartbeat
    if self == remote and method == "FireServer" then
        local a1 = (...)
        if type(a1) == "string" and #a1 > 0 then pcall(logBeat, a1) end
    end

    return Old(self, ...)
end))

print("[BAC] collector armed (canary-defended). Play normally; beats -> " .. file)
