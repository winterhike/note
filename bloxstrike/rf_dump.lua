--[[ Dump every script in ReplicatedFirst to workspace/rf_dump/ via lua.expert.
     Self-contained (embeds the decompiler). Run it, then send me the files in
     the rf_dump folder - especially anything named DataController. ]]

assert(getscriptbytecode, "exploit does not support getscriptbytecode")
local HttpService = (cloneref and cloneref(game:GetService("HttpService"))) or game:GetService("HttpService")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local req = request or http_request or (syn and syn.request)

local function b64(data)
    if base64_encode then return base64_encode(data) end
    local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
    return ((data:gsub('.', function(x)
        local r, byte = '', x:byte()
        for i = 8, 1, -1 do r = r .. (byte % 2^i - byte % 2^(i-1) > 0 and '1' or '0') end
        return r
    end) .. '0000'):gsub('%d%d%d?%d?%d?%d?', function(x)
        if #x < 6 then return '' end
        local c = 0
        for i = 1, 6 do c = c + (x:sub(i, i) == '1' and 2^(6 - i) or 0) end
        return b:sub(c + 1, c + 1)
    end) .. ({ '', '==', '=' })[#data % 3 + 1])
end

local last = 0
local function decompile(scr)
    local ok, bc = pcall(getscriptbytecode, scr)
    if not ok or not bc then return "-- no bytecode: " .. tostring(bc) end
    if #bc == 0 then return "-- empty bytecode" end
    local elapsed = os.clock() - last
    if elapsed < 0.15 then task.wait(0.15 - elapsed) end
    local res = req({
        Url = "https://api.lua.expert/decompile",
        Method = "POST",
        Headers = { ["content-type"] = "application/json" },
        Body = HttpService:JSONEncode({ script = b64(bc) }),
    })
    last = os.clock()
    if not res or res.StatusCode ~= 200 then return "-- api error: " .. (res and tostring(res.Body) or "no response") .. "\n-- bytecode_len=" .. #bc end
    return res.Body
end

pcall(function() if makefolder then makefolder("rf_dump") end end)

local n = 0
local function dumpOne(inst)
    if not inst:IsA("LuaSourceContainer") then return end
    n += 1
    local safe = (inst.Name:gsub("[^%w_]", "_"))
    local path = "rf_dump/" .. n .. "_" .. safe .. ".lua"
    local header = "-- " .. inst:GetFullName() .. " (" .. inst.ClassName .. ")\n"
    local body = "-- decompile errored"
    pcall(function() body = decompile(inst) end)
    pcall(writefile, path, header .. body)
    print("[rf_dump] " .. inst:GetFullName() .. " -> " .. path .. " (" .. #body .. " bytes)")
end

dumpOne(ReplicatedFirst)
for _, d in ipairs(ReplicatedFirst:GetDescendants()) do dumpOne(d) end
print("[rf_dump] done - " .. n .. " script(s) written to rf_dump/")
