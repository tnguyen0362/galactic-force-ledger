-- Phase 15: BASEKIT assembly recipes (guard post, checkpoint, supply depot, compound, stronghold).
-- Run in a Studio EDIT datamodel after install_bk.luau. Builds workspace.GF_ArtTest (render rig; delete afterwards).
-- Recipes are written against the module grid (W = 14.28 studs, wall H = 10). Wall front faces -Z; yaw 0 = front toward -Z.
-- Reuse for beta's InstallationBuilder: copy ring/tower/roof helpers, parent output into the installation Model.
local ART = game.ServerStorage.GF.Art
local W, H = 14.28, 10
local BASEY = 3000
local old = workspace:FindFirstChild("GF_ArtTest"); if old then old:Destroy() end
local ROOT = Instance.new("Folder"); ROOT.Name = "GF_ArtTest"; ROOT.Parent = workspace

local function put(p, name, x, y, z, yaw, scale)
	local m = ART["Kit_BK_" .. name]:Clone()
	if scale and scale ~= 1 then m:ScaleTo(scale) end
	m:PivotTo(CFrame.new(x, BASEY + y, z) * CFrame.Angles(0, yaw or 0, 0))
	m.Parent = p
	return m
end

local function solid() return "Wall_Solid" end
local function mix(side, i)
	if i % 3 == 0 then return "Wall_Window" end
	if i % 3 == 2 and side == "N" then return "Wall_Vent" end
	return "Wall_Solid"
end
local function windows(side, i) return (i % 2 == 0) and "Wall_Window" or "Wall_Solid" end

-- rectangular wall ring of nx x nz modules centred at (ox, oz); gapS = module index on the south side to leave as a doorway
local function ring(p, ox, oz, nx, nz, y, kind, gapS)
	local hx, hz = nx * W / 2, nz * W / 2
	for i = 1, nx do
		local x = ox - hx + (i - 0.5) * W
		if gapS == i then put(p, "Door_Frame", x, y, oz - hz, 0) else put(p, kind("S", i, nx), x, y, oz - hz, 0) end
		put(p, kind("N", i, nx), x, y, oz + hz, math.pi)
	end
	for j = 1, nz do
		local z = oz - hz + (j - 0.5) * W
		put(p, kind("W", j, nz), ox - hx, y, z, math.pi / 2)
		put(p, kind("E", j, nz), ox + hx, y, z, -math.pi / 2)
	end
	for _, sx in { -1, 1 } do for _, sz in { -1, 1 } do
		put(p, "Corner_Column", ox + sx * hx, y, oz + sz * hz, 0)
	end end
end

local function roof(p, cx, cz, size, y) return put(p, "Roof_Slab", cx, y, cz, 0, size / 33.6) end

-- two-storey tower: walls, roof, windowed cab, roof, top piece
local function tower(p, cx, cz, top)
	ring(p, cx, cz, 1, 1, 0, solid)
	roof(p, cx, cz, 15.6, H)
	local y2 = H + 0.7
	ring(p, cx, cz, 1, 1, y2, function() return "Wall_Window" end)
	roof(p, cx, cz, 15.6, y2 + H)
	local yt = y2 + H + 0.7
	if top == "Turret" then put(p, "Turret", cx, yt, cz, 0)
	elseif top == "Mast" then put(p, "Light_Mast", cx, yt, cz, 0)
	elseif top == "Antenna" then put(p, "Antenna", cx, yt, cz, 0) end
end

local function plot(name, ox, oz)
	local f = Instance.new("Model"); f.Name = name; f.Parent = ROOT
	return f, ox, oz
end

-- 1) GUARD POST ---------------------------------------------------------
do
	local p, ox, oz = plot("GuardPost", 0, 0)
	ring(p, ox, oz, 1, 1, 0, mix)
	roof(p, ox, oz, 16.6, H)
	-- rooftop cab
	ring(p, ox, oz, 1, 1, H + 0.75, function() return "Wall_Window" end)
	roof(p, ox, oz, 16.6, 2 * H + 0.75)
	put(p, "Light_Mast", ox + 6, 2 * H + 1.5, oz + 4, 0, 0.7)
	put(p, "Barricade", ox - 13, 0, oz - 14, 0.2)
	put(p, "Barricade", ox + 14, 0, oz - 14, -0.2)
	put(p, "Crates", ox + 14, 0, oz + 3, 0.3)
	put(p, "Railing", ox - 7, H + 0.75, oz - 8, 0)
end

-- 2) CHECKPOINT ---------------------------------------------------------
do
	local p, ox, oz = plot("Checkpoint", 110, 0)
	for _, sx in { -1, 1 } do
		tower(p, ox + sx * 28, oz, "Turret")
		for k = 1, 2 do put(p, "Wall_Solid", ox + sx * (28 + k * W), 0, oz, 0) end
		put(p, "Barricade", ox + sx * (12), 0, oz - 20, sx * 0.25)
	end
	-- canopy on four columns
	for _, sx in { -1, 1 } do for _, sz in { -1, 1 } do
		put(p, "Corner_Column", ox + sx * 15, 0, oz + sz * 7, 0)
	end end
	roof(p, ox, oz, 33.6, H)
	put(p, "Boom_Gate", ox - 7.5, 0, oz - 9, 0)
	put(p, "Boom_Gate", ox + 7.5, 0, oz - 9, math.pi)
	put(p, "Light_Mast", ox, H + 1.5, oz + 8, 0, 0.6)
	put(p, "Generator", ox + 36, 0, oz + 12, 0)
	put(p, "Crates", ox - 40, 0, oz + 12, 0.4)
end

-- 3) SUPPLY DEPOT -------------------------------------------------------
do
	local p, ox, oz = plot("SupplyDepot", 250, 0)
	for _, x in { -21, 0, 21 } do for _, z in { -14, 14 } do
		put(p, "Corner_Column", ox + x, 0, oz + z, 0)
	end end
	put(p, "Roof_Gable", ox, H, oz, 0)
	for i = -1, 1 do put(p, "Wall_Solid", ox + i * W, 0, oz + 15.2, math.pi) end
	put(p, "Wall_Vent", ox - 21.6, 0, oz, math.pi / 2)
	put(p, "Wall_Solid", ox + 21.6, 0, oz, -math.pi / 2)
	-- bay contents
	put(p, "Crates", ox - 12, 0, oz + 7, 0.1)
	put(p, "Crates", ox - 3, 0, oz + 8, -0.1)
	put(p, "Generator", ox + 10, 0, oz + 8, math.pi)
	put(p, "Crates", ox + 14, 0, oz - 4, 0.5)
	-- yard
	put(p, "Container", ox - 40, 0, oz + 6, 0)
	put(p, "Container", ox - 40, 0, oz - 6, 0.05)
	put(p, "Container", ox - 40, 7.6, oz, 0.0)
	put(p, "Fuel_Tank", ox + 40, 0, oz + 6, 0)
	put(p, "Fuel_Tank", ox + 54, 0, oz + 6, 0)
	put(p, "Fuel_Tank", ox + 47, 0, oz - 8, 0)
	put(p, "Light_Mast", ox + 33, 0, oz - 16, 0)
	put(p, "Light_Mast", ox - 30, 0, oz - 20, 0)
	put(p, "Barricade", ox, 0, oz - 24, 0)
end

-- 4) FORTIFIED COMPOUND ------------------------------------------------
do
	local p, ox, oz = plot("Compound", 430, 0)
	local nx, nz = 5, 4
	ring(p, ox, oz, nx, nz, 0, mix, 3)
	local hx, hz = nx * W / 2, nz * W / 2
	for _, sx in { -1, 1 } do for _, sz in { -1, 1 } do
		tower(p, ox + sx * (hx + W / 2), oz + sz * (hz + W / 2), (sz < 0) and "Turret" or "Mast")
	end end
	-- command bunker 2x2 against the back wall
	local bz = oz + hz - W - 1.2
	ring(p, ox, bz, 2, 2, 0, windows, 1)
	roof(p, ox, bz, 28.6, H)
	put(p, "Radar", ox + 6, H + 0.7, bz + 4, 0, 0.8)
	-- yard
	put(p, "Howitzer", ox - 22, 0, oz - 12, 0.3, 0.8)
	put(p, "Howitzer", ox + 22, 0, oz - 12, -0.3, 0.8)
	put(p, "Generator", ox - 27, 0, oz + 12, 0)
	put(p, "Fuel_Tank", ox + 28, 0, oz + 14, 0, 0.8)
	put(p, "Crates", ox - 28, 0, oz + 0, 0.2)
	put(p, "Container", ox + 29, 0, oz - 1, math.pi / 2, 0.9)
	put(p, "Boom_Gate", ox, 0, oz - hz + 7, 0)
	put(p, "Light_Mast", ox - 14, 0, oz - 18, 0, 0.8)
	put(p, "Light_Mast", ox + 14, 0, oz - 18, 0, 0.8)
	put(p, "Turret", ox - 12, 0, oz - hz - 6, 0)
	put(p, "Turret", ox + 12, 0, oz - hz - 6, 0)
	put(p, "Barricade", ox - 18, 0, oz - hz - 12, 0.15)
	put(p, "Barricade", ox + 18, 0, oz - hz - 12, -0.15)
end

-- 5) PRIMARY STRONGHOLD ------------------------------------------------
do
	local p, ox, oz = plot("Stronghold", 660, 0)
	local nx, nz = 7, 5
	ring(p, ox, oz, nx, nz, 0, mix, 4)
	local hx, hz = nx * W / 2, nz * W / 2
	for _, sx in { -1, 1 } do for _, sz in { -1, 1 } do
		tower(p, ox + sx * (hx + W / 2), oz + sz * (hz + W / 2), "Turret")
	end end
	-- stepped keep
	local kz = oz + 8
	ring(p, ox, kz, 3, 3, 0, windows, 2)
	roof(p, ox, kz, 3 * W + 2.4, H)
	local y1 = H + 1.9
	ring(p, ox, kz, 2, 2, y1, windows)
	roof(p, ox, kz, 2 * W + 2.2, y1 + H)
	local y2 = y1 + H + 1.3
	ring(p, ox, kz, 1, 1, y2, function() return "Wall_Window" end)
	roof(p, ox, kz, W + 2, y2 + H)
	local y3 = y2 + H + 0.7
	put(p, "Antenna", ox, y3, kz, 0)
	for _, sx in { -1, 1 } do for _, sz in { -1, 1 } do
		local e = put(p, "Shield_Emitter", ox + sx * 6, y3, kz + sz * 6, 0, 0.7)
		local g = e:FindFirstChild("Glow"); if g then g.Color = Color3.fromRGB(51, 217, 255) end
	end end
	-- yard
	put(p, "Howitzer", ox - 38, 0, oz - 6, 0.3)
	put(p, "Howitzer", ox + 38, 0, oz - 6, -0.3)
	put(p, "Radar", ox - 42, 0, oz + 22, 0.5, 0.9)
	put(p, "Generator", ox + 40, 0, oz + 22, 0)
	put(p, "Fuel_Tank", ox + 32, 0, oz - 20, 0, 0.8)
	put(p, "Container", ox - 34, 0, oz - 24, 0, 0.9)
	put(p, "Crates", ox + 44, 0, oz + 8, 0.3)
	put(p, "Boom_Gate", ox + W / 2 - 0.3, 0, oz - hz + 7, 0)
	for _, sx in { -1, 1 } do
		put(p, "Light_Mast", ox + sx * 8, 0, oz - hz - 8, 0, 0.9)
		put(p, "Turret", ox + sx * 20, 0, oz - hz - 8, 0)
		put(p, "Barricade", ox + sx * 30, 0, oz - hz - 16, sx * 0.2)
	end
end

-- ground
local g = Instance.new("Part")
g.Name = "Ground"; g.Anchored = true; g.Size = Vector3.new(900, 2, 240)
g.Position = Vector3.new(330, BASEY - 1, 0)
g.Material = Enum.Material.Ground; g.Color = Color3.fromRGB(78, 92, 52)
g.Parent = ROOT
return #ROOT:GetDescendants()
