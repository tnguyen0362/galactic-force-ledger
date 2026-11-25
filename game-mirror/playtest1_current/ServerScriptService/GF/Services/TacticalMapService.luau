--!strict
-- Publishes a coarse height field plus markers so the client can draw a terrain-aware map without
-- a second copy of the sampler. Everything goes out as attributes: no new remote, no per-frame cost.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TerrainService = require(script.Parent.TerrainService)
local ObjectiveService = require(script.Parent.ObjectiveService)
local State = require(script.Parent.State)

local TacticalMapService = {}
local GRID = 16
local SPAN = 320
local lastPublish = 0

local function round(n)
	return math.floor(n * 10 + 0.5) / 10
end

local function center()
	-- The minimap is a local navigation instrument, not a strategic objective map. Centre its terrain
	-- window on the active squad; objective/LZ markers are separately edge-clamped by the client.
	local sum = Vector3.zero
	local count = 0
	for _, player in ipairs(Players:GetPlayers()) do
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if root then
			sum += root.Position
			count += 1
		end
	end
	if count > 0 then
		return sum / count
	end
	local lz = workspace:GetAttribute("GF_LZ")
	if typeof(lz) == "Vector3" then
		return lz
	end
	local relay = ObjectiveService.getRelay()
	if relay and relay.PrimaryPart then
		return relay.PrimaryPart.Position
	end
	return Vector3.new(0, 0, 0)
end

function TacticalMapService.sample()
	local origin = center()
	local half = SPAN / 2
	local heights = {}
	local minH, maxH = math.huge, -math.huge
	for gz = 0, GRID - 1 do
		for gx = 0, GRID - 1 do
			local wx = origin.X - half + (gx / (GRID - 1)) * SPAN
			local wz = origin.Z - half + (gz / (GRID - 1)) * SPAN
			local h = TerrainService.groundSurface(wx, wz) or 0
			table.insert(heights, round(h))
			if h < minH then minH = h end
			if h > maxH then maxH = h end
		end
	end
	workspace:SetAttribute("GF_MapMeta", string.format("%.1f,%.1f,%.1f,%.1f,%.1f", origin.X, origin.Z, SPAN, minH, maxH))
	workspace:SetAttribute("GF_MapHeights", table.concat(heights, ","))
	return origin, minH, maxH
end

function TacticalMapService.markers()
	local parts = {}
	local relay = ObjectiveService.getRelay()
	if relay and relay.PrimaryPart then
		local p = relay.PrimaryPart.Position
		table.insert(parts, string.format("obj,%.1f,%.1f", p.X, p.Z))
	end
	local lz = workspace:GetAttribute("GF_LZ")
	if typeof(lz) == "Vector3" then
		table.insert(parts, string.format("lz,%.1f,%.1f", lz.X, lz.Z))
	end
	for _, player in ipairs(Players:GetPlayers()) do
		local ch = player.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if ch and hum and hum.Health > 0 then
			local root = ch:FindFirstChild("HumanoidRootPart")
			if root then
				local s = State.get(player)
				local tag = (s and s.downed) and "down" or "sq"
				table.insert(parts, string.format("%s,%.1f,%.1f", tag, root.Position.X, root.Position.Z))
			end
		end
	end
	workspace:SetAttribute("GF_MapMarkers", table.concat(parts, ";"))
	workspace:SetAttribute("GF_MapMarkerCount", #parts)
end

function TacticalMapService.start()
	TacticalMapService.sample()
	TacticalMapService.markers()
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - lastPublish < 1 then
			return
		end
		lastPublish = now
		TacticalMapService.sample()
		TacticalMapService.markers()
	end)
	print("[GF] tactical map online")
end

TacticalMapService.start()
return TacticalMapService

