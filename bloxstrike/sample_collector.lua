--[[ BAC beat collector - MINIMAL canary hook (matches namecall_bypass.lua).
     Only special-cases FakeIndex (like your working bypass) and passes every
     other namecall straight through, so legit game calls are untouched. We just
     additionally record Remotes.BAC FireServer beats to "bac_beats.txt".

     Run it, play a round, then send me bac_beats.txt (one account/session only).
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

-- EXACTLY the working namecall_bypass logic (FakeIndex only) + capture.
local ToNotTrust = nil
local Old
Old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    local Method = getnamecallmethod()
    local ScriptCalling = getcallingscript()

    if Method == "FakeIndex" then
        if ScriptCalling then ToNotTrust = ScriptCalling end
        return false, 'FakeIndex is not a valid member of DataModel "Ugc"'
    end

    -- record heartbeats (does not alter the call)
    if self == remote and Method == "FireServer" then
        local a1 = (...)
        if type(a1) == "string" and #a1 > 0 then pcall(logBeat, a1) end
    end

    return Old(self, ...)
end))

print("[BAC] collector armed (FakeIndex-only canary). Play normally; beats -> " .. file)
