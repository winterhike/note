--[[ BAC beat sample collector
     Run it, play a round, let it get kicked. Every heartbeat is appended to
     workspace file "bac_beats.txt" (survives the kick). Then send me that file.

     IMPORTANT: all samples must be from ONE session/account - the digest key is
     derived from your Name + UserId, so do NOT mix accounts. Collect as many
     beats as you can in the ~60s before the kick. Repeat on the SAME account if
     you can rejoin; different account = different key = unusable together.
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
assert(remote, "no BAC remote found")

local getnc = getnamecallmethod or get_namecall_method
local file  = "bac_beats.txt"
local count = 0

-- header: identity so I know the key for this batch
local header = string.format("# name=%s userid=%d f2=%d f4=%d\n# nonce_dec,seq,digest_hex\n",
    lp.Name, lp.UserId, lp.UserId * 2, lp.UserId * 4)
if writefile then pcall(writefile, file, header) end
print(header)

local function logBeat(s)
    -- unescape "!<dec>!" -> raw bytes
    local b, i = {}, 1
    while i <= #s do
        local n = s:match("^!(%d+)!", i)
        if n then b[#b+1] = tonumber(n); i = i + #n + 2 else b[#b+1] = s:byte(i); i = i + 1 end
    end
    local nonce = (b[1] or 0) + (b[2] or 0) * 256
    local seq   = b[3]
    local dash
    for j = 1, #b do if b[j] == 0x2D then dash = j break end end
    local hx = {}
    if dash then for j = dash + 1, #b do hx[#hx+1] = string.format("%02x", b[j]) end end
    local line = string.format("%d,%s,%s", nonce, tostring(seq), table.concat(hx))
    count += 1
    print("[beat " .. count .. "] " .. line)
    if appendfile then pcall(appendfile, file, line .. "\n") end
end

local old
old = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    if self == remote and getnc() == "FireServer" then
        local a = (...)
        if type(a) == "string" and #a > 0 then pcall(logBeat, a) end
    end
    return old(self, ...)
end))

print("[BAC] collector armed - play normally. Beats are saved to " .. file)
