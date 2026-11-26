--!strict
-- CoverBuilder: physical cover objects at generated plan positions. Rocks/wrecks/terrain
-- forms per the generator's context-sensitive kinds; angular stylized silhouettes consistent
-- with the existing art direction. Cheap parts, anchored, no unnecessary detail — perf
-- budget per brief section 16. Positions come from Cover.distribute's Poisson-ish sampling
-- with objective/route density biasing already baked in.

local CoverBuilder = {}

local ROCK_C = Color3.fromRGB(96, 92, 86)
local ROCK_C2 = Color3.fromRGB(84, 82, 80)
local WRECK_C = Color3.fromRGB(72, 76, 82)
local WRECK_RUST = Color3.fromRGB(94, 74, 58)

local function mk(parent: Instance, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.Anchored = true
	p.CanCollide = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- deterministic per-position pseudo-random from coordinates (keeps cover stable across rebuilds)
local function hash01(x: number, z: number, salt: number): number
	local v = math.sin(x * 12.9898 + z * 78.233 + salt * 37.719) * 43758.5453
	return v - math.floor(v)
end

local function buildRock(folder: Instance, x: number, z: number, gy: number, s: number)
	-- angular boulder: 2-3 stacked rotated slabs read as stylized rock at distance
	local baseY = gy + 0.5 * s
	local yaw = hash01(x, z, 1) * math.pi * 2
	mk(folder, "RockA", Vector3.new(2.2 * s, 1.4 * s, 1.8 * s),
		CFrame.new(x, baseY, z) * CFrame.Angles(0, yaw, 0.12), ROCK_C, Enum.Material.Slate)
	mk(folder, "RockB", Vector3.new(1.5 * s, 1.1 * s, 1.4 * s),
		CFrame.new(x + 0.3 * s, baseY + 0.9 * s, z - 0.2 * s) * CFrame.Angles(0.1, yaw + 0.7, -0.08), ROCK_C2, Enum.Material.Slate)
	if s > 1.2 then
		mk(folder, "RockC", Vector3.new(0.9 * s, 0.7 * s, 0.8 * s),
			CFrame.new(x - 0.5 * s, baseY + 0.5 * s, z + 0.5 * s) * CFrame.Angles(-0.09, yaw - 0.5, 0.15), ROCK_C, Enum.Material.Slate)
	end
end

local function buildWreck(folder: Instance, x: number, z: number, gy: number, s: number)
	-- burnt-out vehicle/hull fragment: tilted hull plate + broken strut + debris block
	local yaw = hash01(x, z, 2) * math.pi * 2
	mk(folder, "WreckHull", Vector3.new(3.2 * s, 1.1 * s, 2.0 * s),
		CFrame.new(x, gy + 0.7 * s, z) * CFrame.Angles(0.06, yaw, 0.18), WRECK_C, Enum.Material.Metal)
	mk(folder, "WreckStrut", Vector3.new(0.5 * s, 2.2 * s, 0.5 * s),
		CFrame.new(x + 0.8 * s, gy + 1.1 * s, z) * CFrame.Angles(0.2, yaw, 0.35), WRECK_RUST, Enum.Material.Metal)
	mk(folder, "WreckDebris", Vector3.new(1.2 * s, 0.6 * s, 0.9 * s),
		CFrame.new(x - 1.1 * s, gy + 0.35 * s, z + 0.6 * s) * CFrame.Angles(0, yaw + 1.2, 0), WRECK_C, Enum.Material.DiamondPlate)
end

local function buildForm(folder: Instance, x: number, z: number, gy: number, s: number)
	-- terrain form: low angular ridge slab — reads as exposed rock spine, chest-high cover
	local yaw = hash01(x, z, 3) * math.pi * 2
	mk(folder, "FormA", Vector3.new(3.6 * s, 1.6 * s, 1.2 * s),
		CFrame.new(x, gy + 0.8 * s, z) * CFrame.Angles(0, yaw, 0.06), ROCK_C2, Enum.Material.Rock)
	mk(folder, "FormB", Vector3.new(2.2 * s, 1.0 * s, 1.0 * s),
		CFrame.new(x + 0.4 * s, gy + 1.7 * s, z + 0.2 * s) * CFrame.Angles(0, yaw + 0.3, -0.05), ROCK_C, Enum.Material.Rock)
end

-- scale class per cover kind: rocks vary, wrecks bigger, forms long-low
function CoverBuilder.buildAll(cover: { any }, groundY: (number, number) -> number, parent: Instance, budget: number?): number
	local root = Instance.new("Folder")
	root.Name = "BFCover"
	root.Parent = parent
	local maxCount = budget or 240
	local built = 0
	for i, c in cover do
		if built >= maxCount then
			break
		end
		local gy = groundY(c.x, c.z)
		if gy and gy > -100 then
			local s = 0.9 + hash01(c.x, c.z, 7) * 0.8 -- 0.9-1.7 scale jitter
			if c.kind == "wreck" then
				buildWreck(root, c.x, c.z, gy, s)
			elseif c.kind == "terrain_form" then
				buildForm(root, c.x, c.z, gy, s)
			else
				buildRock(root, c.x, c.z, gy, s)
			end
			built += 1
		end
	end
	return built
end

return CoverBuilder
