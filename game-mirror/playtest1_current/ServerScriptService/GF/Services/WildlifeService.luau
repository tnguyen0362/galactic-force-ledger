--!strict
-- S07-009 nonhostile alien wildlife: 0-4 simple ambient creatures per mission site. They flee nearby
-- shots and explosions, carry no loot, never attack, and despawn off-mission. Pure ambience.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WildlifeService = {}
local creatures: { { model: Model, root: BasePart, fleeUntil: number, home: Vector3, seed: number } } = {}

local function makeCreature(pos: Vector3, seed: number): Model
	local model = Instance.new("Model")
	model.Name = "Wildlife" .. seed
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(1.6, 1.2, 1.2)
	body.Color = Color3.fromRGB(120 + seed * 30, 160, 140)
	body.Material = Enum.Material.SmoothPlastic
	body.Anchored = true
	body.CanCollide = false
	body.CFrame = CFrame.new(pos)
	body.Parent = model
	model.PrimaryPart = body
	model:SetAttribute("Wildlife", true)
	model.Parent = workspace
	return model
end

function WildlifeService.spawnForSite(center: Vector3, count: number)
	WildlifeService.clear()
	for i = 1, math.clamp(count, 0, 4) do
		local angle = math.rad(i * 137.5)
		local pos = center + Vector3.new(math.cos(angle) * (20 + i * 6), 2, math.sin(angle) * (20 + i * 6))
		local model = makeCreature(pos, i)
		creatures[i] = { model = model, root = model.PrimaryPart :: BasePart, fleeUntil = 0, home = pos, seed = i }
	end
	workspace:SetAttribute("GF_WildlifeCount", #creatures)
end

function WildlifeService.clear()
	for _, c in ipairs(creatures) do
		if c.model.Parent then c.model:Destroy() end
	end
	creatures = {}
end

-- gunfire/explosions within 30 studs panic wildlife for 4 seconds
function WildlifeService.start()
	RunService.Heartbeat:Connect(function(dt)
		local shots = workspace:GetAttribute("GF_LastShotPos")
		local now = os.clock()
		for _, c in ipairs(creatures) do
			if not c.model.Parent then continue end
			if typeof(shots) == "Vector3" and (shots - c.root.Position).Magnitude < 30 then
				c.fleeUntil = now + 4
			end
			if now < c.fleeUntil then
				-- flee directly away from the noise at speed
				if typeof(shots) == "Vector3" then
					local away = (c.root.Position - shots) * Vector3.new(1, 0, 1)
					if away.Magnitude > 0.5 then
						c.root.CFrame = c.root.CFrame + away.Unit * 9 * dt
					end
				end
			else
				-- idle graze: slow deterministic wander near home
				local t = now * 0.3 + c.seed * 2.1
				local wander = Vector3.new(math.cos(t), 0, math.sin(t * 1.3)) * 1.5 * dt
				local next = c.root.Position + wander
				if (Vector3.new(next.X, 0, next.Z) - Vector3.new(c.home.X, 0, c.home.Z)).Magnitude < 14 then
					c.root.CFrame = c.root.CFrame + wander
				end
			end
		end
	end)
end

return WildlifeService
