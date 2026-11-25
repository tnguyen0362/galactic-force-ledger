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
local CELL_SIZE = 20
local SPAN = (GRID - 1) * CELL_SIZE
local lastPublish = 0
local heightCache: { [string]: number } = {}
local heightCacheCount = 0
workspace:GetAttributeChangedSignal("GF_MissionId"):Connect(function()
	table.clear(heightCache)
	heightCacheCount = 0
end)

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
	local centerPos = center()
	-- World-aligned cells let us cache terrain heights across frames and missions. The previous
	-- implementation re-centered a continuous 16x16 grid on the player every second, causing 256 fresh
	-- long raycasts/sec even when the soldier was standing still.
	local centerIx = math.floor(centerPos.X / CELL_SIZE + 0.5)
	local centerIz = math.floor(centerPos.Z / CELL_SIZE + 0.5)
	local startIx = centerIx - math.floor(GRID / 2)
	local startIz = centerIz - math.floor(GRID / 2)
	local heights = {}
	local minH, maxH = math.huge, -math.huge
	for gz = 0, GRID - 1 do
		for gx = 0, GRID - 1 do
			local ix = startIx + gx
			local iz = startIz + gz
			local key = tostring(ix) .. ":" .. tostring(iz)
			local h = heightCache[key]
			if h == nil then
				h = TerrainService.groundSurface(ix * CELL_SIZE, iz * CELL_SIZE) or 0
				heightCache[key] = h
				heightCacheCount += 1
			end
			table.insert(heights, round(h))
			if h < minH then minH = h end
			if h > maxH then maxH = h end
		end
	end
	local originX = (startIx + (GRID - 1) / 2) * CELL_SIZE
	local originZ = (startIz + (GRID - 1) / 2) * CELL_SIZE
	workspace:SetAttribute("GF_MapMeta", string.format("%.1f,%.1f,%.1f,%.1f,%.1f", originX, originZ, SPAN, minH, maxH))
	workspace:SetAttribute("GF_MapHeights", table.concat(heights, ","))
	workspace:SetAttribute("GF_MapCacheSize", heightCacheCount)
	return Vector3.new(originX, centerPos.Y, originZ), minH, maxH
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
	for _, child in ipairs(workspace:GetChildren()) do
		if child:IsA("BasePart") and child:GetAttribute("GFSupplyCrate") == true and child:GetAttribute("Consumed") ~= true then
			table.insert(parts, string.format("sup,%.1f,%.1f", child.Position.X, child.Position.Z))
		end
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

