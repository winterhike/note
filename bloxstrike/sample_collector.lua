--[[ BAC beat collector v3 - hook the FireServer FUNCTION (not __namecall).
     The beats are sent via a direct FireServer function call, NOT a `:method`
     namecall, so a __namecall hook never sees them (that's why the file was
     header-only). This hooks remote.FireServer itself - the exact mechanism
     that captured beats in the first place - and also installs the FakeIndex
     namecall canary so it survives BAC's probe.

     Run it, play a round, send me bac_beats.txt. One account/session only.
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

-- 1) FakeIndex canary so the hook survives BAC's namecall probe
do
    local Old
    Old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
        if getnamecallmethod() == "FakeIndex" then
            return false, 'FakeIndex is not a valid member of DataModel "Ugc"'
        end
        return Old(self, ...)
    end))
end

-- 2) hook the FireServer FUNCTION (this is where the beat actually goes)
local hookfn = hookfunction or replaceclosure
local fs = remote.FireServer
local old
old = hookfn(fs, newcclosure(function(self, ...)
    if self == remote then
        local a1 = (...)
        if type(a1) == "string" and #a1 > 0 then pcall(logBeat, a1) end
    end
    return old(self, ...)
end))

print("[BAC] collector v3 armed (FireServer fn hook). Play normally; beats -> " .. file)
