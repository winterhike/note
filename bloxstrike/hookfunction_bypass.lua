local _spoofed_registry = {}
local _original_tostring = tostring
local _original_type = type
local _original_typeof = typeof
local _hooks_installed = false

local function install_global_spoofs()
	if _hooks_installed then
		return
	end
	_hooks_installed = true

	local old_tostring = _original_tostring
	local new_tostring = newcclosure(function(v)
		if _original_type(v) == "table" and _spoofed_registry[v] then
			return _spoofed_registry[v]
		end
		return old_tostring(v)
	end)

	local old_type = _original_type
	local new_type = newcclosure(function(v)
		if old_type(v) == "table" and _spoofed_registry[v] then
			return "function"
		end
		return old_type(v)
	end)

	local old_typeof = _original_typeof
	local new_typeof = newcclosure(function(v)
		if old_type(v) == "table" and _spoofed_registry[v] then
			return "function"
		end
		return old_typeof(v)
	end)

	getgenv().tostring = new_tostring
	getgenv().type = new_type
	getgenv().typeof = new_typeof
end

local function hookToStringSpoof(target_table, func_name, hook_fn)
	local original_func = target_table[func_name]
	if not original_func then
		warn("func not found")
		return nil
	end

	local original_str = _original_tostring(original_func)

	install_global_spoofs()

	local proxy = setmetatable({}, {
		__call = function(_, ...)
			local success, result = pcall(hook_fn, original_func, ...)
			if success then
				return result
			else
				return original_func(...)
			end
		end,
		__tostring = function()
			return original_str
		end,
		__metatable = getmetatable(original_func),
	})

	_spoofed_registry[proxy] = original_str

	target_table[func_name] = proxy

	return original_func
end