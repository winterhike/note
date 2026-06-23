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
local dumped = false
local function dumpCaller()
    -- walk the stack to find the AC beat sender + its encryptor
    pcall(function() appendfile(file, "\n# --- caller chain ---\n") end)
    for lvl = 2, 8 do
        local ok, info = pcall(debug.getinfo, lvl, "slnf")
        if ok and info and info.func then
            local line = string.format("# L%d what=%s src=%s line=%s name=%s nparams=%s",
                lvl, tostring(info.what), tostring(info.source), tostring(info.currentline),
                tostring(info.name), tostring(info.numparams))
            pcall(function() appendfile(file, line .. "\n") end)
            print(line)
            -- dump upvalues of the immediate sender (level 2) - encryptor lives here
            if lvl == 2 then
                local okU, ups = pcall(debug.getupvalues, info.func)
                if okU then
                    for ui, u in pairs(ups) do
                        local d = "#   up" .. ui .. " = " .. typeof(u)
                        if type(u) == "function" then
                            local fi = debug.getinfo(u)
                            local okK, ks = pcall(debug.getconstants, u)
                            d = d .. string.format(" [%s nparams=%d nconst=%s]", tostring(fi.what), fi.numparams, okK and #ks or "?")
                        elseif type(u) == "table" then
                            local n = 0 for _ in pairs(u) do n += 1 end
                            d = d .. " [tbl#" .. n .. "]"
                        elseif type(u) == "string" or type(u) == "number" then
                            d = d .. " = " .. tostring(u):sub(1, 40)
                        end
                        pcall(function() appendfile(file, d .. "\n") end)
                        print(d)
                    end
                end
            end
        end
    end
    pcall(function() appendfile(file, "# --- end caller chain ---\n") end)
end

local hookfn = hookfunction or replaceclosure
local fs = remote.FireServer
local old
old = hookfn(fs, newcclosure(function(self, ...)
    if self == remote then
        local a1 = (...)
        if type(a1) == "string" and #a1 > 0 then
            pcall(logBeat, a1)
            if not dumped then dumped = true; pcall(dumpCaller) end
        end
    end
    return old(self, ...)
end))

print("[BAC] collector v4 armed (FireServer fn hook + caller dump). Play normally; beats -> " .. file)
