-- Wire matrix: which declared remotes are actually fired and actually listened to.
-- Paste into `execute_luau` (EDIT mode, place stopped). Returns a compact report + `dead` list.
--
-- WHY THIS EXISTS: `script_grep` silently skips ServerScriptService, so a grep for a remote
-- name reports "never fired" when the server fires it every shot. That false negative cost one
-- full misdiagnosis. Never trust grep for cross-datamodel wiring; use this scanner.

local Remotes = require(game:GetService("ReplicatedStorage").GF.Shared.Remotes)

local scripts = {}
for _, d in ipairs(game:GetDescendants()) do
	if d:IsA("LuaSourceContainer") then
		table.insert(scripts, d)
	end
end

local function isCDN(d) -- ignore engine + package noise
	local p = d.Parent
	while p do
		if p.Name == "Packages" or p.Name == "Assistant" then return true end
		p = p.Parent
	end
	return false
end

local fired, listened, dynamic = {}, {}, {}
for _, remote in ipairs(Remotes.Names) do
	fired[remote], listened[remote], dynamic[remote] = {}, {}, {}
end

for _, s in ipairs(scripts) do
	if not isCDN(s) then
		local src = s.Source
		for _, remote in ipairs(Remotes.Names) do
			local label = tostring(s:GetFullName())
			if src:find(remote .. ":FireClient", 1, true) or src:find(remote .. ":FireServer", 1, true)
				or src:find(remote .. ":FireAllClients", 1, true) or src:find(remote .. ":InvokeServer", 1, true) then
				table.insert(fired[remote], label)
			end
			if src:find(remote .. ".OnClientEvent", 1, true) or src:find(remote .. ".OnServerEvent", 1, true) then
				table.insert(listened[remote], label)
			end
			if src:find('"' .. remote .. '"', 1, true) then
				table.insert(dynamic[remote], label)
			end
		end
	end
end

local lines = { string.format("scanned %d scripts, %d remote channels", #scripts, #Remotes.Names) }
local dead = {}
for _, remote in ipairs(Remotes.Names) do
	local f, l = #fired[remote], #listened[remote]
	if f == 0 or l == 0 then
		local state = (f == 0 and l == 0) and "ORPHAN" or (f == 0 and "LISTEN-ONLY" or "FIRE-ONLY")
		table.insert(lines, string.format("%-11s %-18s fire=%d listen=%d", state, remote, f, l))
		table.insert(dead, remote)
	end
end
table.insert(lines, "dead channels: " .. (#dead == 0 and "none" or table.concat(dead, ", ")))

-- Client VFX surface: defined vs called
local vfx = game:GetService("StarterPlayer").StarterPlayerScripts:FindFirstChild("VFX")
if vfx then
	local defined, called = {}, {}
	for name in vfx.Source:gmatch("function VFX%.([%w_]+)") do
		table.insert(defined, name)
	end
	for _, s in ipairs(scripts) do
		if s ~= vfx and not isCDN(s) then
			for _, name in ipairs(defined) do
				if s.Source:find("VFX." .. name .. "(", 1, true) then
					called[name] = (called[name] or 0) + 1
				end
			end
		end
	end
	local uncalled = {}
	for _, name in ipairs(defined) do
		if not called[name] then table.insert(uncalled, name) end
	end
	table.insert(lines, string.format("VFX api: %d defined, %d called from outside, uncalled: %s",
		#defined, #defined - #uncalled, #uncalled == 0 and "none" or table.concat(uncalled, ", ")))
end

return table.concat(lines, "\n")