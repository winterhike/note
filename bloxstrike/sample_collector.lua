--[[ BAC beat LOCAL generator (NO hook - namecall hooks are detected in ~3s).
     Uses one getgc pass (which survives ~60s) to find the heartbeat producer
     function, then calls it locally thousands of times - WITHOUT firing the
     remote - and logs every produced beat to "bac_beats.txt".

     Run it, wait ~10-15s (it writes incrementally so data survives the kick),
     then send me bac_beats.txt. One account/session only (key = Name+UserId).
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

local function looksBeat(s)
    return type(s) == "string" and #s >= 8 and s:find("-", 1, true) ~= nil and s:find("!0!", 1, true) ~= nil
end

local seen = {}
local count = 0
local function decodeAndLog(s)
    if seen[s] then return end
    seen[s] = true
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
    count += 1
    pcall(appendfile, file, string.format("%d,%s,%s\n", nonce, tostring(seq), table.concat(hx)))
end

-- ONE getgc pass: collect functions related to the heartbeat (hold the BAC
-- remote, or carry the secret/salt in constants), plus any function upvalues
-- they hold (the inner producer/encryptor).
local cands = {}
for _, v in ipairs(getgc(true)) do
    if type(v) == "function" then
        local rel = false
        local okU, ups = pcall(debug.getupvalues, v)
        if okU then
            for _, u in pairs(ups) do
                if u == remote then rel = true end
                if type(u) == "function" then cands[u] = true end
            end
        end
        local okK, ks = pcall(debug.getconstants, v)
        if okK then
            for _, c in pairs(ks) do
                if type(c) == "string" and (c:find("GuelpBAC", 1, true) or c:find("PleaseDontFind", 1, true)) then rel = true end
            end
        end
        if rel then cands[v] = true end
    end
end

-- find a function that, when called, returns a beat-format string
local producer
for f in pairs(cands) do
    local ok, res = pcall(f)
    if ok and looksBeat(res) then producer = f; break end
    local ok2, res2 = pcall(f, 1, 1)
    if ok2 and looksBeat(res2) then producer = f; break end
end

if not producer then
    warn("[BAC] no beat producer found among " .. tostring((function() local n=0 for _ in pairs(cands) do n+=1 end return n end)()) .. " candidates")
    return
end

print("[BAC] producer found - generating samples to " .. file)
for _ = 1, 4000 do
    local ok, res = pcall(producer)
    if ok and looksBeat(res) then decodeAndLog(res) end
    if count >= 1500 then break end
end
print("[BAC] done - " .. count .. " unique beats saved to " .. file)
