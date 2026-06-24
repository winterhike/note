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
    pcall(function() appendfile(file, "\n# --- sender dump ---\n") end)
    -- scan all stack frames; dump upvalues of any Lua function whose source is
    -- the AC sender (ReplicatedFirst.DataController) - that holds the encryptor.
    for lvl = 2, 20 do
        local ok, info = pcall(debug.getinfo, lvl, "slnf")
        if not ok or not info or not info.func then break end
        local src = tostring(info.source)
        local hdr = string.format("# L%d what=%s src=%s line=%s name=%s",
            lvl, tostring(info.what), src, tostring(info.currentline), tostring(info.name))
        pcall(function() appendfile(file, hdr .. "\n") end)
        print(hdr)
        if info.what == "Lua" and (src:find("Controller", 1, true) or src:find("ReplicatedFirst", 1, true) or info.currentline == 1) then
            local okU, ups = pcall(debug.getupvalues, info.func)
            if okU then
                for ui, u in pairs(ups) do
                    local d = "#    up" .. ui .. " = " .. typeof(u)
                    if type(u) == "function" then
                        local fi = debug.getinfo(u)
                        local okK, ks = pcall(debug.getconstants, u)
                        d = d .. string.format(" [%s nparams=%d nconst=%s src=%s]",
                            tostring(fi.what), fi.numparams, okK and #ks or "?", tostring(fi.source):sub(1, 30))
                    elseif type(u) == "table" then
                        -- full numeric dump for small int arrays (the lookup tables / state),
                        -- key listing for hash maps, and function fingerprints for vtables.
                        local n, allInt, sample = 0, true, {}
                        for k, v in pairs(u) do
                            n += 1
                            if type(k) ~= "number" then allInt = false end
                            if n <= 6 then
                                sample[#sample+1] = tostring(k) .. "=" .. (
                                    type(v) == "function" and "fn"
                                    or type(v) == "table" and "tbl"
                                    or type(v) == "string" and ('"' .. v:sub(1,20) .. '"')
                                    or tostring(v)
                                )
                            end
                        end
                        d = d .. " [tbl#" .. n .. " " .. table.concat(sample, " ") .. "]"
                        -- if it's a small int-keyed numeric table, dump every value
                        if allInt and n <= 64 then
                            local nums = {}
                            local hasFns = false
                            for k = 0, n do if u[k] ~= nil then nums[#nums+1] = tostring(k) .. "=" .. tostring(u[k]) end end
                            for _, v in pairs(u) do if type(v) == "function" then hasFns = true; break end end
                            if not hasFns then d = d .. "\n#       FULL: " .. table.concat(nums, ",") end
                        end
                        -- function-vtable: list each fn's nparams + first few constants for fingerprinting
                        if n > 0 and n <= 64 then
                            local fnLines = {}
                            for k, v in pairs(u) do
                                if type(v) == "function" then
                                    local fi = debug.getinfo(v)
                                    local okK, ks = pcall(debug.getconstants, v)
                                    local cs = {}
                                    if okK then for i = 1, math.min(#ks, 5) do
                                        local c = ks[i]
                                        cs[i] = type(c) == "string" and ('"' .. c:sub(1,20) .. '"') or tostring(c)
                                    end end
                                    fnLines[#fnLines+1] = string.format("       [%s] %s p=%d nc=%s {%s}",
                                        tostring(k), tostring(fi.what), fi.numparams, okK and #ks or "?",
                                        table.concat(cs, ","))
                                end
                            end
                            if #fnLines > 0 then d = d .. "\n#" .. table.concat(fnLines, "\n#") end
                        end
                    elseif type(u) == "string" then
                        d = d .. ' = "' .. u:sub(1, 50) .. '"'
                    elseif type(u) == "number" or type(u) == "boolean" then
                        d = d .. " = " .. tostring(u)
                    end
                    pcall(function() appendfile(file, d .. "\n") end)
                    print(d)
                end
            end
        end
    end
    pcall(function() appendfile(file, "# --- end sender dump ---\n") end)
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

print("[BAC] collector v5 armed (FireServer hook + sender upvalue dump). Play; beats -> " .. file)
